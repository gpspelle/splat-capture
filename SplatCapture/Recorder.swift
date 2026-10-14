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
    /// Set when a capture has been saved (the zip in Documents).
    @Published private(set) var lastSaved: URL?

    let session = ARSession()
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private let queue = DispatchQueue(label: "splat-capture.recorder", qos: .userInitiated)
    // only touched on `queue`
    private var writer: CaptureWriter?
    private var limitedFrames = 0
    private var started = Date()

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

    func toggle() {
        switch phase {
        case .idle: record()
        case .recording: stop()
        case .saving: break
        }
    }

    private func record() {
        let format = session.configuration?.videoFormat ?? Self.bestFormat()
        let size = format?.imageResolution ?? CGSize(width: 1920, height: 1440)
        let fps = Double(format?.framesPerSecond ?? 30)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(CaptureLibrary.newName())
        do {
            let w = try CaptureWriter(folder: folder, width: Int(size.width), height: Int(size.height), fps: fps)
            let now = Date()
            queue.async {
                self.limitedFrames = 0
                self.started = now
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
        queue.async {
            guard let w = self.writer else { return }
            self.writer = nil
            let started = self.started
            w.finish(meta: { w in
                CaptureMeta(app: Bundle.main.appVersion, device: Self.deviceModel(),
                            system: UIDevice.current.systemVersion, started: started,
                            width: w.width, height: w.height, fps: w.fps, frames: w.count,
                            duration: w.duration, points: w.points.export().count, lidar: Self.hasLiDAR)
            }) { result in
                let stored = result.flatMap { folder in Result { try CaptureLibrary.store(folder) } }
                DispatchQueue.main.async {
                    switch stored {
                    case .success(let zip): self.lastSaved = zip
                    case .failure(let error): self.lastError = error.localizedDescription
                    }
                    self.phase = .idle
                }
            }
        }
    }

    // MARK: ARSessionDelegate (called on `queue`)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let kind = Self.kind(frame.camera.trackingState)
        var stats: (Int, Double, Int, Double)?
        if let w = writer {
            w.append(frame, tracking: kind)
            if !kind.isGood { limitedFrames += 1 }
            if w.count % 10 == 0 {
                stats = (w.count, w.duration, w.points.count, w.count > 0 ? Double(limitedFrames) / Double(w.count) : 0)
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

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}
