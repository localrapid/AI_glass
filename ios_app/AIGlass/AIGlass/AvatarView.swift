//
//  AvatarView.swift
//  AIGlass
//
//  The companion's face: a VRoid/VRM 3D avatar rendered on-device with
//  RealityKit (via VRMKit / VRMRealityKit). It relaxes out of the T-pose,
//  idles naturally (breathing, sway, small head motion, blinks), lip-syncs to
//  the companion's speech, and reacts when tapped.
//
//  Setup (one-time, in Xcode — see AVATAR_SETUP.md):
//    1. File ▸ Add Package Dependencies… ▸ https://github.com/tattn/VRMKit
//       Dependency Rule = Branch: `main`. Add products VRMKit + VRMRealityKit.
//    2. Drop a `model.vrm` into the AIGlass folder (auto-bundled). VRoid VRM 1.0
//       exports may need `tools/fix_vrm.py` first (missing-field patch).
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
    @State private var model = AvatarModel()
    /// Mount the RealityView only after the view is on screen. RealityKit can
    /// render black if its view is created during a programmatic tab switch /
    /// cold launch (e.g. opening 相棒 from a tapped notification); deferring a
    /// frame avoids that.
    @State private var mounted = false
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemIndigo).opacity(0.18), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)

            if mounted {
            RealityView { content in
                // Soft key light so the toon materials read well off-AR.
                let light = DirectionalLight()
                light.light.intensity = 3000
                light.look(at: .zero, from: SIMD3(0.4, 1.0, 1.4), relativeTo: nil)
                content.add(light)

                // Frame the head and shoulders (a "bust" shot) so it reads as a face.
                let cam = PerspectiveCamera()
                cam.camera.fieldOfViewInDegrees = 33
                cam.look(at: SIMD3(0, 1.32, 0), from: SIMD3(0, 1.34, 1.05), relativeTo: nil)
                content.add(cam)

                do {
                    let loader = try VRMEntityLoader(named: "model.vrm")
                    let entity = try loader.loadEntity()
                    let facing: Float
                    switch entity.vrm {
                    case .v0: facing = .pi   // VRM 0.x faces away — spin to face the camera
                    case .v1: facing = 0     // VRM 1.0 already faces the camera
                    }
                    entity.entity.transform.rotation = simd_quatf(angle: facing, axis: SIMD3(0, 1, 0))
                    content.add(entity.entity)
                    model.attach(entity, facing: facing)
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.react() }
            }

            if let err = model.errorMessage {
                AvatarSetupCard(
                    title: "アバター未設定",
                    message: "VRoid の model.vrm を読み込めません。\n\(err)")
            }
        }
        .task { mounted = true }
        .onReceive(tick) { _ in
            if mounted { model.update() }
        }
    }
}

@MainActor
@Observable
final class AvatarModel {
    var errorMessage: String?
    private var vrm: VRMEntity?
    /// Yaw so the avatar faces the camera (set from the loaded model's version).
    private var facing: Float = 0
    private var time: TimeInterval = 0
    private var rootY: Float = 0

    // Animated bones and their rest rotations (after the A-pose is applied).
    private var spine: Entity?
    private var neck: Entity?
    private var head: Entity?
    private var spineRest = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var neckRest = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var headRest = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    /// Start time of a tap reaction, or -1 when idle.
    private var reactStart: TimeInterval = -1

    /// How far to drop the arms out of the T-pose (radians). If the arms swing
    /// up instead of down, flip the sign; if they look wrong, try axis (1,0,0).
    private let armDrop: Float = 1.0

    func attach(_ entity: VRMEntity, facing: Float) {
        vrm = entity
        self.facing = facing
        errorMessage = nil
        rootY = entity.entity.transform.translation.y

        // Relax the T-pose: lower both upper arms to a natural A-pose. This
        // model's arm bones are NOT mirror-symmetric, so the two sides need
        // opposite signs around local-Z to both swing down.
        if let la = entity.humanoid.node(for: .leftUpperArm) {
            la.transform.rotation = la.transform.rotation * simd_quatf(angle: -armDrop, axis: SIMD3<Float>(0, 0, 1))
        }
        if let ra = entity.humanoid.node(for: .rightUpperArm) {
            ra.transform.rotation = ra.transform.rotation * simd_quatf(angle: armDrop, axis: SIMD3<Float>(0, 0, 1))
        }

        spine = entity.humanoid.node(for: .spine)
        neck = entity.humanoid.node(for: .neck)
        head = entity.humanoid.node(for: .head)
        spineRest = spine?.transform.rotation ?? spineRest
        neckRest = neck?.transform.rotation ?? neckRest
        headRest = head?.transform.rotation ?? headRest
    }

    /// Trigger a one-shot "happy" reaction (tap).
    func react() {
        reactStart = time
    }

    func update() {
        guard let vrm else { return }
        let dt = 1.0 / 60.0
        time += dt
        let t = Float(time)

        // Whole-body gentle sway (two detuned sines so it doesn't look periodic).
        let sway = sin(t * 0.5) * 0.04 + sin(t * 0.23) * 0.02
        vrm.entity.transform.rotation = simd_quatf(angle: facing + sway, axis: SIMD3(0, 1, 0))

        // Breathing: drives a small vertical bob and a tiny spine pitch.
        let breath = sin(t * 1.6)
        var bob = breath * 0.004

        if let spine {
            spine.transform.rotation = spineRest * simd_quatf(angle: breath * 0.025, axis: SIMD3(1, 0, 0))
        }

        // Idle head motion: slow, semi-random look-around + tilt.
        var headPitch = sin(t * 0.7) * 0.05
        let headYaw = sin(t * 0.37 + 1.3) * 0.10
        let headRoll = sin(t * 0.29 + 0.6) * 0.06

        // Tap reaction: a happy expression + quick nod + little hop.
        if reactStart >= 0 {
            let e = Float(time - reactStart)
            let dur: Float = 0.8                         // snappy
            if e > dur {
                reactStart = -1
                vrm.setBlendShape(value: 0, for: .preset(.joy))
            } else {
                let env = sin(.pi * (e / dur))           // 0 → 1 → 0
                vrm.setBlendShape(value: CGFloat(env), for: .preset(.joy))
                headPitch += env * 0.22 * sin(e * 26)    // quick nod
                bob += env * 0.04                        // hop
            }
        }

        if let neck {
            neck.transform.rotation = neckRest * simd_quatf(angle: headYaw * 0.4, axis: SIMD3(0, 1, 0))
        }
        if let head {
            let q = simd_quatf(angle: headPitch, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: headYaw, axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: headRoll, axis: SIMD3(0, 0, 1))
            head.transform.rotation = headRest * q
        }

        vrm.entity.transform.translation.y = rootY + bob

        // Lip-sync: prefer the real voice envelope (VOICEVOX from the 4090);
        // fall back to a wiggle while the on-device voice is speaking.
        let voiceLevel = VoicePlayer.shared.level
        let sine: CGFloat = Speaker.shared.isSpeaking ? CGFloat(max(0, sin(t * 20)) * 0.85) : 0
        vrm.setBlendShape(value: max(voiceLevel, sine), for: .preset(.a))

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
