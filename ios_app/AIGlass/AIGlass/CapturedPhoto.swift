//
//  CapturedPhoto.swift
//  AIGlass
//
//  One JPEG frame reassembled from BLE Photo Data chunks.
//

import Foundation
import UIKit

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpegData: Data
    let receivedAt: Date
    let chunkCount: Int
    /// True if the frame was reassembled despite a gap in the chunk counter
    /// (i.e. one or more BLE packets were dropped). The image may be corrupt.
    let hadGap: Bool

    // AI caption (Claude). Populated lazily — see CaptionService / BLEManager.
    var caption: String?
    var captionError: String?
    var isCaptioning = false

    var byteCount: Int { jpegData.count }
}
