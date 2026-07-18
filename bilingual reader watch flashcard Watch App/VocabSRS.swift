//
//  VocabSRS.swift
//  bilingual reader watch flashcard Watch App
//
//  Mirrors web vocab config in srs-algo.ts:
//  request_retention: 0.98, maximum_interval: 1000
//

import Foundation
import FSRS

enum VocabSRS {
    static let requestRetention = 0.98
    static let maximumInterval = 1000.0

    private static let scheduler = FSRS(
        parameters: FSRSParameters(
            requestRetention: requestRetention,
            maximumInterval: maximumInterval
        )
    )

    /// Next due dates for Again / Hard / Good / Easy, same as web `getNextScheduledOptions` for vocab.
    static func nextReviewOptions(card: Card, now: Date = Date()) throws -> [Rating: Date] {
        let preview = try scheduler.repeat(card: card, now: now)
        var options: [Rating: Date] = [:]
        for rating: Rating in [.again, .hard, .good, .easy] {
            if let due = preview[rating]?.card.due {
                options[rating] = due
            }
        }
        return options
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
