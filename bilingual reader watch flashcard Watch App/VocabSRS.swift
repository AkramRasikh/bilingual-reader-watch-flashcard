//
//  VocabSRS.swift
//  bilingual reader watch flashcard Watch App
//
//  Mirrors web ReviewSRSToggles + srs-algo.ts:
//  vocab 0.98 / sentences 0.97, maximum_interval: 1000, formattedToBe5am
//

import Foundation
import FSRS

enum VocabSRS {
    enum ContentType {
        case vocab
        case sentences

        var requestRetention: Double {
            switch self {
            case .vocab: return 0.98
            case .sentences: return 0.97
            }
        }
    }

    static let requestRetention = ContentType.vocab.requestRetention
    static let maximumInterval = 1000.0

    /// ~23h50m — same threshold as web `isMoreThanADayAhead`.
    private static let dayAheadThreshold: TimeInterval = (23 * 60 + 50) * 60

    private static let vocabScheduler = FSRS(
        parameters: FSRSParameters(
            requestRetention: ContentType.vocab.requestRetention,
            maximumInterval: maximumInterval
        )
    )

    private static let sentenceScheduler = FSRS(
        parameters: FSRSParameters(
            requestRetention: ContentType.sentences.requestRetention,
            maximumInterval: maximumInterval
        )
    )

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func scheduler(for contentType: ContentType) -> FSRS {
        switch contentType {
        case .vocab: return vocabScheduler
        case .sentences: return sentenceScheduler
        }
    }

    /// Full next cards for Again / Hard / Good / Easy (web `nextScheduledOptions`).
    static func nextReviewCards(
        card: Card,
        now: Date = Date(),
        contentType: ContentType = .vocab
    ) throws -> [Rating: Card] {
        let preview = try scheduler(for: contentType).repeat(card: card, now: now)
        var options: [Rating: Card] = [:]
        for rating: Rating in [.again, .hard, .good, .easy] {
            if let next = preview[rating]?.card {
                options[rating] = next
            }
        }
        return options
    }

    static func nextReviewOptions(
        card: Card,
        now: Date = Date(),
        contentType: ContentType = .vocab
    ) throws -> [Rating: Date] {
        try nextReviewCards(card: card, now: now, contentType: contentType).mapValues(\.due)
    }

    /// Same as ReviewSRSToggles: if next due is ≥ ~1 day ahead, snap due to 5:00 local.
    static func cardForPersist(_ card: Card, now: Date = Date()) -> Card {
        var next = card
        if isMoreThanADayAhead(due: next.due, now: now) {
            next.due = setToFiveAM(next.due)
        }
        return next
    }

    static func isMoreThanADayAhead(due: Date, now: Date) -> Bool {
        due.timeIntervalSince(now) >= dayAheadThreshold
    }

    /// Mirrors web `setToFiveAM` (`setHours(5, 0, 0, 0)` in local tz).
    static func setToFiveAM(_ date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 5
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }

    /// Snake_case payload matching Firebase / web `reviewData`.
    static func reviewDataDictionary(from card: Card) -> [String: Any] {
        var dict: [String: Any] = [
            "due": isoFormatter.string(from: card.due),
            "stability": card.stability,
            "difficulty": card.difficulty,
            "elapsed_days": card.elapsedDays,
            "scheduled_days": card.scheduledDays,
            "reps": card.reps,
            "lapses": card.lapses,
            "state": card.state.rawValue,
        ]
        if let lastReview = card.lastReview {
            dict["last_review"] = isoFormatter.string(from: lastReview)
        }
        return dict
    }

    static func relativeLabel(from now: Date, to due: Date) -> String {
        let seconds = abs(due.timeIntervalSince(now))

        if seconds < 60 {
            return "<1m"
        }
        if seconds < 3600 {
            return "\(max(1, Int(seconds / 60)))m"
        }
        if seconds < 86_400 {
            return "\(max(1, Int(seconds / 3600)))h"
        }
        return "\(max(1, Int(seconds / 86_400)))d"
    }
}
