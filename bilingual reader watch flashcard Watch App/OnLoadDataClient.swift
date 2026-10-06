//
//  OnLoadDataClient.swift
//  bilingual reader watch flashcard Watch App
//

import Foundation

enum OnLoadDataClient {
    /// Matches backend `LanguageTypes` / language validation keys.
    static let knownLanguages = ["arabic", "chinese", "french", "japanese"]

    /// Loaded from `.env` → `GeneratedEnv` at build time.
    private static let endpoint = GeneratedEnv.getOnLoadDataURL

    /// Fetch one language from the API, persist, and return the bundle.
    /// Successful responses are saved even when there are 0 due words.
    static func fetchAndCache(language: String) async throws -> LanguageBundle {
        guard let bundle = try await fetchBundle(language: language) else {
            throw URLError(.cannotParseResponse)
        }
        LocalWordStore.save(language: language, bundle: bundle)
        return bundle
    }

    /// Use local cache when present; otherwise hit the API.
    static func loadLocalOrFetch(language: String) async throws -> LanguageBundle {
        if let cached = LocalWordStore.load(language: language) {
            print("[LocalWordStore] hit \(language) (\(cached.dueCount)/\(cached.words.count) due)")
            return cached
        }
        print("[getOnLoadData] fetching \(language)")
        return try await fetchAndCache(language: language)
    }

    private static func fetchBundle(language: String) async throws -> LanguageBundle? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "language": language,
            "refs": ["words", "content", "sentences"],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            print("[getOnLoadData] \(language) HTTP \(http.statusCode)")
            return nil
        }

        // Response shape: [{ "words": [...] }, { "content": [...] }, { "sentences": [...] }]
        guard let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let rawWords = root.first(where: { $0["words"] != nil })?["words"] as? [[String: Any]]
        let rawContent = root.first(where: { $0["content"] != nil })?["content"] as? [[String: Any]]
        let rawSentences = dictionaries(
            from: root.first(where: { $0["sentences"] != nil })?["sentences"]
        )

        guard let rawWords else { return nil }

        let topics = buildTopics(from: rawContent ?? [], language: language)
        var sentenceById = buildSentenceMap(from: rawContent ?? [])
        mergeStandaloneSentences(rawSentences, into: &sentenceById)
        let helperSentenceIds = collectAdhocSentenceIds(
            from: rawSentences,
            excluding: Set(topics.flatMap(\.sentenceIds))
        )
        let now = Date()

        let mapped = rawWords.compactMap { dict -> Word? in
            guard var word = Word(dictionary: dict, now: now) else { return nil }
            let sentenceId = word.contexts.first
            let sentence = sentenceId.flatMap { sentenceById[$0] }
            word = word.withSentence(sentence)

            if let sentenceId,
               let topic = topics.first(where: { $0.sentenceIds.contains(sentenceId) })
            {
                let playAt = resolvePlayAt(word: word, topic: topic, sentence: sentence)
                word = word.withAudio(fileName: topic.title, playAt: playAt)
            } else if let sentenceId {
                // Same as web WordCardSecondaryAudioWidget: `{language}-audio/{sentenceId}.mp3` from 0:00.
                word = word.withAudio(fileName: sentenceId, playAt: 0)
            }

            return word
        }

        let reviewableSentences = buildReviewableSentences(from: rawContent ?? [], now: now)
        let dueCount = mapped.filter(\.isDue).count
        let sentenceDue = reviewableSentences.filter(\.isDue).count
        let snippetCards = topics.reduce(0) { $0 + $1.snippets.filter { !$0.id.isEmpty && $0.card != nil }.count }
        let snippetDue = topics.reduce(0) { partial, topic in
            partial + topic.snippets.filter { snippet in
                guard let due = snippet.card?.due else { return false }
                return due < now
            }.count
        }
        print("[getOnLoadData] \(language): \(dueCount)/\(mapped.count) words due, \(sentenceDue)/\(reviewableSentences.count) sentences due, \(snippetDue)/\(snippetCards) snippets due, \(topics.count) topics, \(helperSentenceIds.count) adhoc sentences")
        return LanguageBundle(
            words: mapped,
            topics: topics,
            adhocSentenceIds: helperSentenceIds,
            sentences: reviewableSentences
        )
    }

    /// Prefer snippet cue (LearningScreenWordCard), else sentence time.
    private static func resolvePlayAt(
        word: Word,
        topic: ContentTopic,
        sentence: SentenceContext?
    ) -> TimeInterval? {
        if let snippetCue = snippetPlayAt(for: word, in: topic.snippets) {
            return max(0, snippetCue)
        }
        if let time = sentence?.time {
            return max(0, time)
        }
        return nil
    }

    /// Same matching as web LearningScreenWordCard.wordHasOverlappingSnippetTime.
    private static func snippetPlayAt(for word: Word, in snippets: [ContentSnippet]) -> TimeInterval? {
        func matches(_ item: ContentSnippet) -> Bool {
            let texts = [item.focusedText, item.suggestedFocusText].compactMap { $0 }
            return texts.contains { text in
                (!word.surfaceForm.isEmpty && text.contains(word.surfaceForm))
                    || (!word.baseForm.isEmpty && text.contains(word.baseForm))
            }
        }

        let matched = snippets.first(where: { matches($0) && !$0.isPreSnippet })
            ?? snippets.first(where: matches)

        guard let matched else { return nil }
        let padding: TimeInterval = matched.isContracted ? 0.75 : 1.5
        return matched.time - padding
    }

    /// Content rows: id + title + sentence ids + snippets.
    private static func buildTopics(from contentItems: [[String: Any]], language: String) -> [ContentTopic] {
        contentItems.compactMap { item in
            let id = item["id"] as? String ?? ""
            let title = item["title"] as? String ?? ""
            let sentences = item["content"] as? [[String: Any]] ?? []
            let sentenceIds = sentences.compactMap { $0["id"] as? String }
            guard !id.isEmpty, !sentenceIds.isEmpty else { return nil }

            let cues = transcriptCues(from: sentences)
            let rawSnippets = snippetDictionaries(from: item["snippets"])
            let snippets = rawSnippets.compactMap { snippet -> ContentSnippet? in
                guard let time = doubleValue(snippet["time"]) else { return nil }
                let isContracted = boolValue(snippet["isContracted"])
                    || boolValue(snippet["isContract"])
                return ContentSnippet(
                    id: snippet["id"] as? String ?? "",
                    targetLang: snippet["targetLang"] as? String ?? "",
                    baseLang: snippet["baseLang"] as? String ?? "",
                    focusedText: snippet["focusedText"] as? String,
                    suggestedFocusText: snippet["suggestedFocusText"] as? String,
                    time: time,
                    isContracted: isContracted,
                    isPreSnippet: boolValue(snippet["isPreSnippet"]),
                    card: ReviewDataParsing.card(from: snippet["reviewData"] as? [String: Any]),
                    vocab: overlappingBreakdown(time: time, isContracted: isContracted, cues: cues),
                    sentenceContext: overlappingSentences(
                        time: time,
                        isContracted: isContracted,
                        cues: cues,
                        language: language
                    )
                )
            }

            return ContentTopic(
                id: id,
                title: title.isEmpty ? "Untitled" : title,
                sentenceIds: sentenceIds,
                snippets: snippets
            )
        }
    }

    /// Transcript rows that already have FSRS `reviewData`.
    private static func buildReviewableSentences(
        from contentItems: [[String: Any]],
        now: Date
    ) -> [ReviewableSentence] {
        contentItems.flatMap { item -> [ReviewableSentence] in
            let contentId = item["id"] as? String ?? ""
            let title = item["title"] as? String ?? ""
            guard !contentId.isEmpty else { return [] }
            let audioFileName = title.isEmpty ? nil : title
            let sentences = item["content"] as? [[String: Any]] ?? []
            return sentences.enumerated().compactMap { index, sentence in
                let previous = index > 0 ? Self.neighborText(from: sentences[index - 1]) : ("", "")
                let next = index + 1 < sentences.count ? Self.neighborText(from: sentences[index + 1]) : ("", "")
                let nextTime = index + 1 < sentences.count
                    ? doubleValue(sentences[index + 1]["time"])
                    : nil
                return ReviewableSentence(
                    dictionary: sentence,
                    contentId: contentId,
                    audioFileName: audioFileName,
                    previous: previous,
                    next: next,
                    nextTime: nextTime,
                    now: now
                )
            }
        }
    }

    private static func neighborText(from sentence: [String: Any]) -> (targetLang: String, baseLang: String) {
        (
            sentence["targetLang"] as? String ?? "",
            sentence["baseLang"] as? String ?? ""
        )
    }

    /// Mirrors `initWords` sentenceId map, keeping targetLang/baseLang + time.
    private static func buildSentenceMap(
        from contentItems: [[String: Any]]
    ) -> [String: SentenceContext] {
        var map: [String: SentenceContext] = [:]

        for contentItem in contentItems {
            let sentences = contentItem["content"] as? [[String: Any]] ?? []
            for sentence in sentences {
                guard let id = sentence["id"] as? String else { continue }
                let targetLang = sentence["targetLang"] as? String ?? ""
                let baseLang = sentence["baseLang"] as? String ?? ""
                guard !targetLang.isEmpty || !baseLang.isEmpty else { continue }
                map[id] = SentenceContext(
                    targetLang: targetLang,
                    baseLang: baseLang,
                    time: doubleValue(sentence["time"])
                )
            }
        }

        return map
    }

    /// Sentence cues in transcript order. End is the next sentence's time, matching web overlap.
    private static func transcriptCues(from sentences: [[String: Any]]) -> [TranscriptCue] {
        let times = sentences.map { doubleValue($0["time"]) }
        return sentences.enumerated().compactMap { index, sentence in
            guard let time = times[index] else { return nil }
            let end: TimeInterval
            if index + 1 < times.count, let next = times[index + 1], next > time {
                end = next
            } else {
                end = time
            }
            let sentenceId = sentence["id"] as? String ?? ""
            let sentenceText = sentence["targetLang"] as? String ?? ""
            return TranscriptCue(
                id: sentenceId,
                time: time,
                end: end,
                targetLang: sentenceText,
                baseLang: sentence["baseLang"] as? String ?? "",
                meaning: sentenceMeaning(sentence["meaning"]),
                vocab: breakdownWords(
                    from: sentence,
                    sentenceId: sentenceId,
                    sentenceText: sentenceText,
                    sentenceTime: time
                )
            )
        }
    }

    /// Vocab from sentences whose span overlaps the snippet window (`time ± 1.5s`, or `± 0.75s`).
    private static func overlappingBreakdown(
        time: TimeInterval,
        isContracted: Bool,
        cues: [TranscriptCue]
    ) -> [BreakdownWord] {
        let padding: TimeInterval = isContracted ? 0.75 : 1.5
        let windowStart = time - padding
        let windowEnd = time + padding
        var seen = Set<String>()
        var words: [BreakdownWord] = []
        for cue in cues {
            guard cue.end > cue.time else { continue }
            let overlapStart = max(cue.time, windowStart)
            let overlapEnd = min(cue.end, windowEnd)
            guard overlapStart < overlapEnd else { continue }
            for word in cue.vocab where seen.insert(word.surfaceForm).inserted {
                words.append(word)
            }
        }
        return words
    }

    /// Sentences whose span overlaps the snippet window, plus the lines just outside it.
    private static func overlappingSentences(
        time: TimeInterval,
        isContracted: Bool,
        cues: [TranscriptCue],
        language: String
    ) -> SnippetSentenceContext {
        let padding: TimeInterval = isContracted ? 0.75 : 1.5
        let windowStart = time - padding
        let windowEnd = time + padding
        let indexes = cues.indices.filter { index in
            let cue = cues[index]
            guard cue.end > cue.time else { return false }
            let overlapStart = max(cue.time, windowStart)
            let overlapEnd = min(cue.end, windowEnd)
            return overlapStart < overlapEnd
        }
        guard let first = indexes.first, let last = indexes.last else {
            return SnippetSentenceContext()
        }
        let joiner = SnippetFocus.isTrimmedLanguage(language) ? "" : " "
        let current = cues[first...last]
        var breakdowns: [SnippetBreakdownGroup] = []
        if first > 0, let group = breakdownGroup(cues[first - 1]) {
            breakdowns.append(group)
        }
        for cue in current {
            if let group = breakdownGroup(cue) {
                breakdowns.append(group)
            }
        }
        if last + 1 < cues.count, let group = breakdownGroup(cues[last + 1]) {
            breakdowns.append(group)
        }
        var lines: [SnippetSentenceLine] = []
        if first > 0 {
            lines.append(sentenceLine(cues[first - 1], isCurrent: false, index: lines.count))
        }
        for cue in current {
            lines.append(sentenceLine(cue, isCurrent: true, index: lines.count))
        }
        if last + 1 < cues.count {
            lines.append(sentenceLine(cues[last + 1], isCurrent: false, index: lines.count))
        }
        return SnippetSentenceContext(
            previousTarget: first > 0 ? cues[first - 1].targetLang : "",
            currentTarget: current.map(\.targetLang).filter { !$0.isEmpty }.joined(separator: joiner),
            currentBase: current.map(\.baseLang).filter { !$0.isEmpty }.joined(separator: joiner),
            nextTarget: last + 1 < cues.count ? cues[last + 1].targetLang : "",
            breakdowns: breakdowns,
            lines: lines.filter { !$0.targetLang.isEmpty || !$0.baseLang.isEmpty }
        )
    }

    private static func sentenceLine(_ cue: TranscriptCue, isCurrent: Bool, index: Int) -> SnippetSentenceLine {
        let baseId = cue.id.isEmpty ? cue.targetLang : cue.id
        return SnippetSentenceLine(
            id: "\(index)-\(baseId)",
            targetLang: cue.targetLang,
            baseLang: cue.baseLang,
            meaning: cue.meaning,
            isCurrent: isCurrent
        )
    }

    private static func sentenceMeaning(_ value: Any?) -> String {
        let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || text == "n/a" { return "" }
        return text
    }

    private static func breakdownGroup(_ cue: TranscriptCue) -> SnippetBreakdownGroup? {
        guard !cue.vocab.isEmpty else { return nil }
        let id = cue.id.isEmpty ? cue.targetLang : cue.id
        return SnippetBreakdownGroup(id: id, targetLang: cue.targetLang, words: cue.vocab)
    }

    private static func breakdownWords(
        from sentence: [String: Any],
        sentenceId: String,
        sentenceText: String,
        sentenceTime: TimeInterval
    ) -> [BreakdownWord] {
        dictionaries(from: sentence["vocab"]).compactMap { item in
            let surface = (item["surfaceForm"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let meaning = (item["meaning"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !surface.isEmpty, !meaning.isEmpty, meaning != "n/a" else { return nil }
            return BreakdownWord(
                surfaceForm: surface,
                meaning: meaning,
                sentenceId: sentenceId,
                sentenceText: sentenceText,
                sentenceTime: sentenceTime
            )
        }
    }

    private struct TranscriptCue {
        let id: String
        let time: TimeInterval
        let end: TimeInterval
        let targetLang: String
        let baseLang: String
        let meaning: String
        let vocab: [BreakdownWord]
    }

    /// Firebase stores `content.snippets` as an id-keyed object. The web turns that into an array with `Object.values`.
    private static func snippetDictionaries(from value: Any?) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            return object.compactMap { key, raw in
                guard var snippet = raw as? [String: Any] else { return nil }
                if (snippet["id"] as? String)?.isEmpty != false {
                    snippet["id"] = key
                }
                return snippet
            }
        }
        return dictionaries(from: value)
    }

    /// Firebase `sentences` may be an array or a keyed object (`Object.values` on the server).
    private static func dictionaries(from value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        if let object = value as? [String: Any] {
            return object.values.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    /// Fill gaps only — content sentences keep `time` / article text when ids collide.
    private static func mergeStandaloneSentences(
        _ sentences: [[String: Any]],
        into map: inout [String: SentenceContext]
    ) {
        for sentence in sentences {
            guard let id = sentence["id"] as? String, map[id] == nil else { continue }
            let targetLang = sentence["targetLang"] as? String ?? ""
            let baseLang = sentence["baseLang"] as? String ?? ""
            guard !targetLang.isEmpty || !baseLang.isEmpty else { continue }
            map[id] = SentenceContext(
                targetLang: targetLang,
                baseLang: baseLang,
                time: doubleValue(sentence["time"])
            )
        }
    }

    private static func collectAdhocSentenceIds(
        from sentences: [[String: Any]],
        excluding contentSentenceIds: Set<String>
    ) -> [String] {
        sentences.compactMap { sentence -> String? in
            guard (sentence["topic"] as? String) == "sentence-helper",
                  let id = sentence["id"] as? String,
                  !id.isEmpty,
                  !contentSentenceIds.contains(id)
            else { return nil }
            return id
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}
