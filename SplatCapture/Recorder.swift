import ARKit
import CaptureKit
import SwiftUI

/// Runs the AR session and, while recording, hands every camera frame to a CaptureWriter.
/// Published values are only changed on the main queue.
final class Recorder: NSObject, ObservableObject, ARSessionDelegate {
    enum Phase { case idle, recording, saving }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var tracking: TrackingKind = .initializing
    @Published private(set) var frames = 0
    @Published private(set) var seconds: Double = 0
    @Published private(set) var points = 0
    @Published private(set) var limitedShare: Double = 0
    @Published var lastError: String?
    /// Set when a capture has been saved: the zip in Documents and the phone's check of it.
    @Published var saved: SavedCapture?

    let session = ARSession()
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private let queue = DispatchQueue(label: "splat-capture.recorder", qos: .userInitiated)
    // only touched on `queue`
    private var writer: CaptureWriter?
    private var started = Date()
    private var name = ""
    private var cameraLocked = false

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = queue
    }

    func start() {
        guard Self.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        if let format = Self.bestFormat() {
            config.videoFormat = format
        }
        session.run(config)
    }

    func pause() {
        if phase == .recording { stop() }
        session.pause()
    }

    /// 30 frames a second at about 1920x1440: plenty for training, and small enough to record
    /// for minutes. Falls back to whatever the phone offers.
    static func bestFormat() -> ARConfiguration.VideoFormat? {
        let all = ARWorldTrackingConfiguration.supportedVideoFormats
        let thirty = all.filter { $0.framesPerSecond == 30 }
        let pool = thirty.isEmpty ? all : thirty
        let fitting = pool.filter { $0.imageResolution.width <= 1920 }
        return fitting.max { $0.imageResolution.width < $1.imageResolution.width } ?? pool.first
    }

    static var hasLiDAR: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    func toggle(name: String = "") {
        switch phase {
        case .idle: record(name: name)
        case .recording: stop()
        case .saving: break
        }
    }

    private func record(name: String) {
        let format = session.configuration?.videoFormat ?? Self.bestFormat()
        let size = format?.imageResolution ?? CGSize(width: 1920, height: 1440)
        let fps = Double(format?.framesPerSecond ?? 30)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(CaptureLibrary.newName(trimmed))
        do {
            let w = try CaptureWriter(folder: folder, width: Int(size.width), height: Int(size.height), fps: fps)
            let now = Date()
            // Same focus, exposure and colour for the whole take: steadier colours, and a lens
            // that doesn't change (ARKit's positions assume the lens it measured).
            let locked = Self.lockCamera(true)
            queue.async {
                self.started = now
                self.name = trimmed
                self.cameraLocked = locked
                self.writer = w
            }
            frames = 0
            seconds = 0
            points = 0
            limitedShare = 0
            phase = .recording
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stop() {
        phase = .saving
        UIApplication.shared.isIdleTimerDisabled = false
        _ = Self.lockCamera(false)
        queue.async {
            guard let w = self.writer else { return }
            self.writer = nil
            let started = self.started, name = self.name, locked = self.cameraLocked
            let quality = w.quality()
            w.finish(meta: { w in
                CaptureMeta(app: Bundle.main.appVersion, device: Self.deviceModel(),
                            system: UIDevice.current.systemVersion, started: started,
                            width: w.width, height: w.height, fps: w.fps, frames: w.count,
                            duration: w.duration, points: w.points.export().count, lidar: Self.hasLiDAR,
                            name: name, cameraLocked: locked, quality: quality)
            }) { result in
                let stored = result.flatMap { folder in Result { try CaptureLibrary.store(folder) } }
                let seconds = w.duration, frames = w.count
                DispatchQueue.main.async {
                    switch stored {
                    case .success(let zip):
                        self.saved = SavedCapture(url: zip, name: name, seconds: seconds, frames: frames,
                                                  quality: quality, cameraLocked: locked)
                    case .failure(let error): self.lastError = error.localizedDescription
                    }
                    self.phase = .idle
                }
            }
        }
    }

    /// Locks (or releases) focus, exposure and white balance of the camera ARKit uses.
    /// Returns whether all three could be locked.
    static func lockCamera(_ lock: Bool) -> Bool {
        guard let device = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else { return false }
        do {
            try device.lockForConfiguration()
        } catch {
            return false
        }
        defer { device.unlockForConfiguration() }
        var all = true
        if lock {
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked } else { all = false }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked } else { all = false }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked } else { all = false }
        } else {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
        return all
    }

    // MARK: ARSessionDelegate (called on `queue`)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let kind = Self.kind(frame.camera.trackingState)
        var stats: (Int, Double, Int, Double)?
        if let w = writer {
            w.append(frame, tracking: kind)
            if w.count % 10 == 0 {
                stats = (w.count, w.duration, w.points.count, w.count > 0 ? Double(w.limited) / Double(w.count) : 0)
            }
        }
        DispatchQueue.main.async {
            if self.tracking != kind { self.tracking = kind }
            if let (n, s, p, l) = stats, self.phase == .recording {
                self.frames = n
                self.seconds = s
                self.points = p
                self.limitedShare = l
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.lastError = error.localizedDescription }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            if self.phase == .recording { self.stop() }
        }
    }

    static func kind(_ state: ARCamera.TrackingState) -> TrackingKind {
        switch state {
        case .normal: return .normal
        case .notAvailable: return .notAvailable
        case .limited(let reason):
            switch reason {
            case .initializing: return .initializing
            case .excessiveMotion: return .excessiveMotion
            case .insufficientFeatures: return .insufficientFeatures
            case .relocalizing: return .relocalizing
            @unknown default: return .limited
            }
        }
    }

    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// A finished recording, as shown right after it stops.
struct SavedCapture: Identifiable {
    let url: URL
    let name: String
    let seconds: Double
    let frames: Int
    let quality: QualityReport
    let cameraLocked: Bool
    var id: URL { url }
}

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}
