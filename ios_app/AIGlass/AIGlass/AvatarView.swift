//
//  AvatarView.swift
//  AIGlass
//
//  The companion's face: a VRoid/VRM 3D avatar rendered on-device with
//  RealityKit (via VRMKit / VRMRealityKit). It idles gently, blinks, and
//  lip-syncs to the companion's speech (Speaker.isSpeaking).
//
//  Setup (one-time, in Xcode — see AVATAR_SETUP.md):
//    1. File ▸ Add Package Dependencies… ▸ https://github.com/tattn/VRMKit
//       Add the products: VRMKit and VRMRealityKit to the AIGlass target.
//    2. Export a model from VRoid Studio as VRM, rename it to `model.vrm`,
//       and drag it into the AIGlass target (Copy if needed, target checked).
//
//  Until the package is added, `canImport(VRMRealityKit)` is false and this
//  file compiles to a lightweight placeholder so the app still builds.
//

import SwiftUI

/// Shown when the VRM package or model file isn't available yet.
private struct AvatarSetupCard: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.dashed")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.callout.bold())
            Text(message)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
    }
}

#if canImport(VRMRealityKit)
import RealityKit
import Combine
import VRMKit
import VRMRealityKit

struct AvatarView: View {
    @ObservedObject private var speaker = Speaker.shared
    @State private var model = AvatarModel()
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemIndigo).opacity(0.18), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
            RealityView { content in
                model.build(into: content)
            }
            if let err = model.errorMessage {
                AvatarSetupCard(
                    title: "アバター未設定",
                    message: "VRoid Studio で作った model.vrm を\nアプリに追加してください。\n\(err)")
            }
        }
        .onReceive(tick) { _ in
            model.update(isSpeaking: speaker.isSpeaking)
        }
    }
}

@MainActor
@Observable
final class AvatarModel {
    var errorMessage: String?
    private var vrm: VRMEntity?
    private var time: TimeInterval = 0
    /// Yaw so the avatar faces the camera. VRM 0.x faces away (needs 180°),
    /// VRM 1.0 already faces the camera (0). Set from the loaded model.
    private var facing: Float = .pi

    func build(into content: RealityViewContent) {
        // Soft key light so the toon materials read well off-AR.
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: .zero, from: SIMD3(0.4, 1.0, 1.4), relativeTo: nil)
        content.add(light)

        // Frame the head and shoulders (a "bust" shot) so it feels like a face.
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 33
        cam.look(at: SIMD3(0, 1.32, 0), from: SIMD3(0, 1.34, 1.05), relativeTo: nil)
        content.add(cam)

        do {
            let loader = try VRMEntityLoader(named: "model.vrm")
            let entity = try loader.loadEntity()
            switch entity.vrm {
            case .v0: facing = .pi   // VRM 0.x faces away — spin to face the camera
            case .v1: facing = 0     // VRM 1.0 already faces the camera
            }
            entity.entity.transform.rotation = simd_quatf(angle: facing, axis: SIMD3(0, 1, 0))
            content.add(entity.entity)
            vrm = entity
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(isSpeaking: Bool) {
        guard let vrm else { return }
        let dt = 1.0 / 60.0
        time += dt

        // Gentle idle sway around the facing direction.
        let sway = Float(sin(time * 0.8)) * 0.03
        vrm.entity.transform.rotation = simd_quatf(angle: facing + sway, axis: SIMD3(0, 1, 0))

        // Lip-sync: open/close the mouth while speaking.
        let mouth: CGFloat = isSpeaking ? CGFloat(max(0, sin(time * 11)) * 0.8) : 0
        vrm.setBlendShape(value: mouth, for: .preset(.a))

        // Blink: a brief close roughly every 4 seconds.
        let blinkPhase = time.truncatingRemainder(dividingBy: 4.0)
        vrm.setBlendShape(value: blinkPhase < 0.12 ? 1 : 0, for: .preset(.blink))

        // Advance skinning / spring bones.
        vrm.update(at: dt)
    }
}

#else

struct AvatarView: View {
    var body: some View {
        AvatarSetupCard(
            title: "3Dアバターを表示するには",
            message: "Xcode で VRMKit パッケージ\n(github.com/tattn/VRMKit) を追加すると\nここにアバターが表示されます。")
    }
}

#endif
