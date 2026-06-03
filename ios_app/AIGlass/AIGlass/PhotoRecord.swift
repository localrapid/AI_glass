//
//  PhotoRecord.swift
//  AIGlass
//
//  Persistent record of one JPEG frame received from the glasses, plus its AI
//  caption. Stored with SwiftData so the lifelog accumulates across launches —
//  the foundation for later search / RAG.
//

import Foundation
import SwiftData
import UIKit

@Model
final class PhotoRecord {
    @Attribute(.unique) var id: UUID
    var receivedAt: Date
    /// JPEG bytes kept outside the database file (can be tens of KB each).
    @Attribute(.externalStorage) var jpeg: Data
    var chunkCount: Int
    var hadGap: Bool

    var caption: String?
    var captionError: String?
    var isCaptioning: Bool

    init(id: UUID = UUID(), receivedAt: Date, jpeg: Data, chunkCount: Int, hadGap: Bool) {
        self.id = id
        self.receivedAt = receivedAt
        self.jpeg = jpeg
        self.chunkCount = chunkCount
        self.hadGap = hadGap
        self.isCaptioning = false
    }

    var image: UIImage? { UIImage(data: jpeg) }
    var byteCount: Int { jpeg.count }
}
