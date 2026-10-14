import Foundation
import simd

/// One line of `frames.jsonl`: where the camera was for one video frame.
/// See docs/capture-format.md for the meaning of every field.
public struct FrameRow: Codable, Equatable {
    /// Frame number in video.mov, from 0. Every frame in the video has exactly one row.
    public var index: Int
    /// Seconds since the first frame (the frame's presentation time in the video).
    public var time: Double
    /// Camera-to-world 4x4 matrix, row-major, in ARKit's axes (camera: x right, y up, z towards
    /// the viewer, for the sensor's landscape image; world: y up, metres).
    public var pose: [Float]
    /// fx, fy, cx, cy in pixels of the recorded image.
    public var intrinsics: [Float]
    /// "normal", "limited-<reason>" or "notAvailable".
    public var tracking: String

    enum CodingKeys: String, CodingKey {
        case index = "i", time = "t", pose, intrinsics = "K", tracking
    }

    public init(index: Int, time: Double, pose: [Float], intrinsics: [Float], tracking: String) {
        self.index = index
        self.time = time
        self.pose = pose
        self.intrinsics = intrinsics
        self.tracking = tracking
    }

    /// simd matrices are column-major (`m[c][r]`); the file is row-major.
    public static func rowMajor(_ m: simd_float4x4) -> [Float] {
        var out = [Float]()
        out.reserveCapacity(16)
        for r in 0..<4 {
            for c in 0..<4 {
                out.append(m[c][r])
            }
        }
        return out
    }

    /// ARKit's intrinsics matrix is column-major: fx = K[0][0], fy = K[1][1], cx = K[2][0], cy = K[2][1].
    public static func flatIntrinsics(_ k: simd_float3x3) -> [Float] {
        [k[0][0], k[1][1], k[2][0], k[2][1]]
    }

    /// One JSON line (with the trailing newline).
    public func jsonLine(_ encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

/// `meta.json`: what recorded the capture and how.
public struct CaptureMeta: Codable, Equatable {
    public var format = "splat-capture"
    public var version = 1
    public var app: String
    public var device: String
    public var system: String
    public var started: String
    public var width: Int
    public var height: Int
    public var fps: Double
    public var frames: Int
    public var duration: Double
    public var points: Int
    public var lidar: Bool
    /// What the person called the recording (may be empty).
    public var name: String?
    /// Whether focus, exposure and white balance were locked for the whole recording.
    public var cameraLocked: Bool?
    /// The phone's own check of the recording (see QualityReport).
    public var quality: QualityReport?

    public init(app: String, device: String, system: String, started: Date, width: Int, height: Int,
                fps: Double, frames: Int, duration: Double, points: Int, lidar: Bool,
                name: String? = nil, cameraLocked: Bool? = nil, quality: QualityReport? = nil) {
        self.name = name
        self.cameraLocked = cameraLocked
        self.quality = quality
        self.app = app
        self.device = device
        self.system = system
        self.started = ISO8601DateFormatter().string(from: started)
        self.width = width
        self.height = height
        self.fps = fps
        self.frames = frames
        self.duration = duration
        self.points = points
        self.lidar = lidar
    }
}

/// A tracked 3D point from ARKit, with the colour it had in the video.
public struct FeaturePoint: Codable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    /// In how many sampled frames ARKit reported this point.
    public var seen: Int
}

/// `points.json`.
public struct PointsFile: Codable, Equatable {
    public var points: [FeaturePoint]
    public init(points: [FeaturePoint]) { self.points = points }
}
