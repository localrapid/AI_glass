//
//  TranscriptRecord.swift
//  AIGlass
//
//  Persistent record of one audio clip's transcription (Phase 2). The audio
//  itself lives on the hub; only the (tiny) transcript text is kept on device.
//

import Foundation
import SwiftData

@Model
final class TranscriptRecord {
    @Attribute(.unique) var id: UUID
    var receivedAt: Date
    var seconds: Int
    var hubJobID: String?
    var transcript: String?
    var error: String?
    var isTranscribing: Bool

    init(id: UUID = UUID(), receivedAt: Date, seconds: Int) {
        self.id = id
        self.receivedAt = receivedAt
        self.seconds = seconds
        self.isTranscribing = true
    }
}
