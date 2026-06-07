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

    init(question: String, answer: String, referencedLog: String, refCount: Int) {
        self.id = UUID()
        self.createdAt = Date()
        self.question = question
        self.answer = answer
        self.referencedLog = referencedLog
        self.refCount = refCount
    }
}
