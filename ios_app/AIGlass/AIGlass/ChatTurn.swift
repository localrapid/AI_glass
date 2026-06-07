//
//  ChatTurn.swift
//  AIGlass
//
//  One persisted question/answer exchange with the companion, including the
//  lifelog snippets it was grounded on (so the Q&A history is reviewable and
//  the answer's basis is inspectable).
//

import Foundation
import SwiftData

@Model
final class ChatTurn {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var question: String
    var answer: String
    /// The retrieved, time-stamped lifelog lines used as grounding.
    var referencedLog: String
    var refCount: Int
    /// Which brain answered: "オンデバイス" or "4090".
    var source: String?

    init(question: String, answer: String, referencedLog: String, refCount: Int, source: String? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.question = question
        self.answer = answer
        self.referencedLog = referencedLog
        self.refCount = refCount
        self.source = source
    }
}
