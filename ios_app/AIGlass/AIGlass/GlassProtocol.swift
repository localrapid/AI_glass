//
//  GlassProtocol.swift
//  AIGlass
//
//  BLE service / characteristic UUIDs and wire-format constants for the
//  AI_glass firmware. These MUST stay in sync with firmware/AIGlass/config.h.
//
//  Photo Data wire format (device -> phone, NOTIFY):
//    [counter_LSB][counter_MSB][JPEG bytes ...]
//  The counter increments per chunk starting at 0. A packet whose counter
//  equals 0xFFFF (carrying no payload) marks end-of-frame.
//
//  Photo Control (phone -> device, WRITE), one signed byte:
//    -1      capture a single frame
//     0      stop auto-capture
//     1..120 auto-capture interval in seconds
//

import CoreBluetooth

enum GlassUUID {
    static let service      = CBUUID(string: "a17ec1a5-0000-4000-8000-000000000001")
    static let photoData    = CBUUID(string: "a17ec1a5-0000-4000-8000-000000000002")
    static let photoControl = CBUUID(string: "a17ec1a5-0000-4000-8000-000000000003")
    static let touchEvent   = CBUUID(string: "a17ec1a5-0000-4000-8000-000000000004")
    static let status       = CBUUID(string: "a17ec1a5-0000-4000-8000-000000000005")
    static let audioData    = CBUUID(string: "a17ec1a5-0000-4000-8000-000000000006")
    static let audioControl = CBUUID(string: "a17ec1a5-0000-4000-8000-000000000008")
}

enum AudioProtocol {
    /// PCM format the device records (mono). Used to build the WAV header.
    nonisolated static let sampleRate: UInt32 = 16000
    nonisolated static let bitsPerSample: UInt16 = 16
    nonisolated static let defaultSeconds: UInt8 = 5
}

enum PhotoProtocol {
    /// Counter value (little-endian) that marks the final, empty end-of-frame packet.
    static let endOfFrameMarker: UInt16 = 0xFFFF
    /// Bytes of frame-counter prefix on every Photo Data packet.
    static let headerSize = 2
}

enum PhotoControlCommand {
    static let captureOnce: Int8 = -1
    static let stop: Int8 = 0
    /// Default auto-capture interval the firmware boots with.
    static let defaultInterval: Int8 = 15
}
