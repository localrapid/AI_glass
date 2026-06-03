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
    /// Local JPEG copy, kept only for recent photos (last few days). Pruned to
    /// nil for older ones — the full image then lives on the M1 hub and is
    /// fetched on demand via `hubJobID`.
    @Attribute(.externalStorage) var jpeg: Data?
    /// The hub's job id, used both for captioning and to re-fetch the image
    /// after the local copy has been pruned.
    var hubJobID: String?
    var chunkCount: Int
    var hadGap: Bool

    var caption: String?
    var captionError: String?
    var isCaptioning: Bool

    init(id: UUID = UUID(), receivedAt: Date, jpeg: Data?, chunkCount: Int, hadGap: Bool) {
        self.id = id
        self.receivedAt = receivedAt
        self.jpeg = jpeg
        self.chunkCount = chunkCount
        self.hadGap = hadGap
        self.isCaptioning = false
    }

    /// Local image if still cached; nil once pruned (fetch from hub instead).
    var image: UIImage? { jpeg.flatMap(UIImage.init(data:)) }
    var byteCount: Int { jpeg?.count ?? 0 }
    var isLocal: Bool { jpeg != nil }
}
