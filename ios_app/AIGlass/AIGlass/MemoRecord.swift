//
//  MemoRecord.swift
//  AIGlass
//
//  Something the user told the companion directly (e.g. a reply to a proactive
//  check-in: "本読んでるよ"). These self-reported notes join the lifelog corpus
//  so the companion can recall and "learn" from them in later conversations.
//

import Foundation
import SwiftData

@Model
final class MemoRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var text: String
    /// Origin, e.g. "reply" (from a notification reply).
    var kind: String

    init(text: String, kind: String = "reply") {
        self.id = UUID()
        self.createdAt = Date()
        self.text = text
        self.kind = kind
    }
}
