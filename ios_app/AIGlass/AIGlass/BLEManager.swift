//
//  BLEManager.swift
//  AIGlass
//
//  Central-side BLE driver for the AI_glass eyewear. Scans for the service in
//  GlassUUID, auto-connects, subscribes to Photo Data notifications, and
//  reassembles JPEG frames from the counter-prefixed chunk stream. Also writes
//  the Photo Control characteristic to drive auto-capture interval (Phase 1
//  step 8).
//
//  CoreBluetooth does not work in the iOS Simulator — run on a physical device
//  to actually receive photos.
//

import Foundation
import Combine
import CoreBluetooth
import SwiftData
import UIKit

@MainActor
final class BLEManager: NSObject, ObservableObject {

    enum ConnectionState: String {
        case poweredOff   = "Bluetoothオフ"
        case unauthorized = "Bluetooth未許可"
        case idle         = "待機中"
        case scanning     = "スキャン中…"
        case connecting   = "接続中…"
        case connected    = "接続済み"
        case disconnected = "切断"
    }

    // MARK: Published state (transient UI; photos live in SwiftData)
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var chunksInProgress = 0
    @Published private(set) var bytesInProgress = 0
    @Published private(set) var negotiatedMTU = 0
    @Published private(set) var lastLog = ""

    /// SwiftData context for persisting received photos. Injected by the view.
    var modelContext: ModelContext?

    // MARK: CoreBluetooth
    private var central: CBCentralManager!
    private var glass: CBPeripheral?
    private var photoControlChar: CBCharacteristic?

    // MARK: Frame reassembly state
    private var frameBuffer = Data()
    private var lastCounter = -1
    private var chunkCount = 0
    private var hadGap = false

    // MARK: Captioning
    struct CaptionSettings {
        var auto = false
        var useHub = true
        var hubURL = ""
        var hubToken = ""
        var apiKey = ""
        var canCaption: Bool { useHub ? !hubURL.isEmpty : !apiKey.isEmpty }
    }

    /// Supplies the current captioning preferences. Set by the view from
    /// AppSettings so the manager doesn't own settings state.
    var captionConfig: () -> CaptionSettings = { CaptionSettings() }

    override init() {
        super.init()
        // queue: nil delivers delegate callbacks on the main queue, matching
        // this @MainActor class so published state mutates safely.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: Intent

    func startScan() {
        guard central.state == .poweredOn else { return }
        state = .scanning
        log("scanning for AI_glass…")
        central.scanForPeripherals(withServices: [GlassUUID.service])
    }

    func disconnect() {
        if let glass { central.cancelPeripheralConnection(glass) }
    }

    /// Write a Photo Control command (see PhotoControlCommand).
    func sendControl(_ command: Int8) {
        guard let glass, let char = photoControlChar else {
            log("control write skipped: not connected")
            return
        }
        var value = command
        let data = Data(bytes: &value, count: 1)
        glass.writeValue(data, for: char, type: .withResponse)
        log("Photo Control <- \(command)")
    }

    // MARK: Reassembly

    private func resetFrame() {
        frameBuffer.removeAll(keepingCapacity: true)
        lastCounter = -1
        chunkCount = 0
        hadGap = false
        chunksInProgress = 0
        bytesInProgress = 0
    }

    private func ingest(_ packet: Data) {
        guard packet.count >= PhotoProtocol.headerSize else { return }
        let counter = UInt16(packet[0]) | (UInt16(packet[1]) << 8)

        if counter == PhotoProtocol.endOfFrameMarker {
            finalizeFrame()
            return
        }

        if Int(counter) != lastCounter + 1 {
            hadGap = true
            log("⚠️ chunk gap: expected \(lastCounter + 1), got \(counter)")
        }
        lastCounter = Int(counter)

        let payload = packet.suffix(from: PhotoProtocol.headerSize)
        frameBuffer.append(payload)
        chunkCount += 1
        chunksInProgress = chunkCount
        bytesInProgress = frameBuffer.count
    }

    private func finalizeFrame() {
        let data = frameBuffer
        let chunks = chunkCount
        let gap = hadGap
        defer { resetFrame() }

        guard !data.isEmpty else {
            log("empty frame ignored")
            return
        }
        guard UIImage(data: data) != nil else {
            log("⚠️ JPEG decode failed: \(data.count) bytes, \(chunks) chunks, gap=\(gap)")
            return
        }
        guard let context = modelContext else {
            log("no modelContext yet; photo dropped")
            return
        }

        let record = PhotoRecord(receivedAt: Date(), jpeg: data, chunkCount: chunks, hadGap: gap)
        context.insert(record)
        try? context.save()
        log("✅ photo \(data.count) bytes / \(chunks) chunks\(gap ? " (gap!)" : "")")

        let cfg = captionConfig()
        if cfg.useHub && !cfg.hubURL.isEmpty {
            // Hub is the canonical store: upload every photo. Caption now only
            // if auto is on; otherwise just store (caption on demand later).
            uploadToHub(recordID: record.id, jpeg: data, wantCaption: cfg.auto, cfg: cfg)
        } else if cfg.auto && cfg.canCaption {
            // Cloud (Claude) mode auto-caption — image stays local.
            requestCaption(for: record.id)
        }

        pruneOldImages()
    }

    /// Upload a freshly received photo to the hub (for storage, and optionally
    /// captioning). Records the hub job id so the local copy can be pruned later.
    private func uploadToHub(recordID: UUID, jpeg: Data, wantCaption: Bool, cfg: CaptionSettings) {
        guard let context = modelContext else { return }
        let hub = HubCaptionService.Config(baseURL: cfg.hubURL, token: cfg.hubToken)
        if wantCaption, let r = fetchRecord(recordID, context) {
            r.isCaptioning = true
            r.captionError = nil
            try? context.save()
        }
        Task {
            do {
                let jid = try await HubCaptionService.upload(
                    jpeg: jpeg, kind: wantCaption ? "caption" : "store", config: hub)
                if let r = fetchRecord(recordID, context) {
                    r.hubJobID = jid
                    try? context.save()
                }
                if wantCaption {
                    let text = try await HubCaptionService.result(jobID: jid, config: hub)
                    if let r = fetchRecord(recordID, context) {
                        r.caption = text
                        r.isCaptioning = false
                        try? context.save()
                    }
                    log("📝 caption ok (hub)")
                } else {
                    log("🗄 stored on hub")
                }
            } catch {
                let m = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let r = fetchRecord(recordID, context) {
                    if wantCaption { r.captionError = m }
                    r.isCaptioning = false
                    try? context.save()
                }
                log("hub upload failed: \(m)")
            }
        }
    }

    /// Drop the local JPEG for photos older than `keepDays` that are safely
    /// stored on the hub. Captions/metadata stay; the image is re-fetched from
    /// the hub on demand. Keeps iPhone storage roughly flat.
    private func pruneOldImages(keepDays: Int = 3) {
        guard let context = modelContext else { return }
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86_400)
        let descriptor = FetchDescriptor<PhotoRecord>(
            predicate: #Predicate { $0.receivedAt < cutoff && $0.jpeg != nil && $0.hubJobID != nil }
        )
        if let old = try? context.fetch(descriptor), !old.isEmpty {
            for r in old { r.jpeg = nil }
            try? context.save()
            log("🧹 pruned \(old.count) local image(s) (older than \(keepDays)d)")
        }
    }

    // MARK: Caption requests

    /// Inject the SwiftData context and clear any captions left "in progress"
    /// by a previous run (so the UI doesn't show a stuck spinner).
    func attach(context: ModelContext) {
        modelContext = context
        let stuck = FetchDescriptor<PhotoRecord>(predicate: #Predicate { $0.isCaptioning == true })
        if let rows = try? context.fetch(stuck) {
            for r in rows { r.isCaptioning = false }
            try? context.save()
        }
        pruneOldImages()
    }

    private func fetchRecord(_ id: UUID, _ context: ModelContext) -> PhotoRecord? {
        let d = FetchDescriptor<PhotoRecord>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(d).first
    }

    /// Kick off (or retry) captioning for one stored photo, using the backend
    /// selected in settings (local hub by default, Claude as fallback).
    func requestCaption(for id: UUID) {
        let cfg = captionConfig()
        guard cfg.canCaption,
              let context = modelContext,
              let record = fetchRecord(id, context),
              !record.isCaptioning
        else { return }

        let localJPEG = record.jpeg
        let existingJobID = record.hubJobID
        record.isCaptioning = true
        record.captionError = nil
        try? context.save()

        Task {
            do {
                let text: String
                if cfg.useHub {
                    let hub = HubCaptionService.Config(baseURL: cfg.hubURL, token: cfg.hubToken)
                    let jid: String
                    if let existing = existingJobID {
                        // Already on the hub (possibly pruned locally) — re-queue it.
                        try await HubCaptionService.recaption(jobID: existing, config: hub)
                        jid = existing
                    } else if let data = localJPEG {
                        jid = try await HubCaptionService.upload(jpeg: data, kind: "caption", config: hub)
                        if let r = fetchRecord(id, context) {
                            r.hubJobID = jid
                            try? context.save()
                        }
                    } else {
                        throw HubCaptionService.HubError.jobFailed("画像がローカルにもハブにもありません")
                    }
                    text = try await HubCaptionService.result(jobID: jid, config: hub)
                } else {
                    guard let data = localJPEG else {
                        throw HubCaptionService.HubError.jobFailed("画像がローカルにありません")
                    }
                    text = try await CaptionService.caption(jpeg: data, apiKey: cfg.apiKey)
                }
                if let r = fetchRecord(id, context) {
                    r.caption = text
                    r.isCaptioning = false
                    try? context.save()
                }
                log("📝 caption ok (\(cfg.useHub ? "hub" : "claude"))")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let r = fetchRecord(id, context) {
                    r.captionError = message
                    r.isCaptioning = false
                    try? context.save()
                }
                log("📝 caption failed: \(message)")
            }
        }
    }

    private func log(_ message: String) {
        lastLog = message
        print("[BLE] \(message)")
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    // The central is created with `queue: nil`, so every delegate callback runs
    // on the main queue. `MainActor.assumeIsolated` lets us touch MainActor
    // state synchronously without hopping through a Task (which would require
    // sending non-Sendable CoreBluetooth objects across isolation).
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                log("Bluetooth on")
                startScan()
            case .poweredOff:
                state = .poweredOff
            case .unauthorized:
                state = .unauthorized
            default:
                state = .idle
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            log("found \(peripheral.name ?? "device") rssi=\(RSSI)")
            central.stopScan()
            state = .connecting
            glass = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            state = .connected
            negotiatedMTU = peripheral.maximumWriteValueLength(for: .withoutResponse) + 3
            log("connected, ~MTU \(negotiatedMTU)")
            peripheral.discoverServices([GlassUUID.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            state = .disconnected
            photoControlChar = nil
            resetFrame()
            log("disconnected\(error.map { ": \($0.localizedDescription)" } ?? ""), re-scanning")
            startScan()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == GlassUUID.service }) else {
                log("service not found")
                return
            }
            peripheral.discoverCharacteristics(
                [GlassUUID.photoData, GlassUUID.photoControl, GlassUUID.touchEvent, GlassUUID.status],
                for: service
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            for char in service.characteristics ?? [] {
                switch char.uuid {
                case GlassUUID.photoData:
                    peripheral.setNotifyValue(true, for: char)
                    log("subscribed to Photo Data")
                case GlassUUID.photoControl:
                    photoControlChar = char
                    // Kick off auto-capture at the default interval.
                    sendControl(PhotoControlCommand.defaultInterval)
                case GlassUUID.touchEvent, GlassUUID.status:
                    peripheral.setNotifyValue(true, for: char)
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let value = characteristic.value else { return }
            switch characteristic.uuid {
            case GlassUUID.photoData:
                ingest(value)
            case GlassUUID.touchEvent:
                log("touch event \(Array(value))")
            case GlassUUID.status:
                log("status \(Array(value))")
            default:
                break
            }
        }
    }
}
