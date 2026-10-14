import Foundation
import simd

/// Collects ARKit's feature points over a recording. ARKit refines a point's position as it sees it
/// again, so the latest position is kept; the colour is averaged over the frames it was sampled in.
public final class PointAccumulator {
    private struct Entry {
        var position: SIMD3<Float>
        var color = SIMD3<Float>(0, 0, 0)
        var colored = 0
        var seen = 0
    }

    private var entries: [UInt64: Entry] = [:]

    public init() {}

    public var count: Int { entries.count }

    public func add(id: UInt64, position: SIMD3<Float>, color: SIMD3<UInt8>?) {
        var e = entries[id] ?? Entry(position: position)
        e.position = position
        e.seen += 1
        if let c = color {
            e.color += SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z))
            e.colored += 1
        }
        entries[id] = e
    }

    /// Points seen in at least `minSeen` sampled frames (one sighting is often noise), grey when
    /// no colour was sampled. Sorted by id so the file is the same for the same input.
    public func export(minSeen: Int = 2) -> [FeaturePoint] {
        entries.keys.sorted().compactMap { id in
            let e = entries[id]!
            guard e.seen >= minSeen else { return nil }
            let c = e.colored > 0 ? e.color / Float(e.colored) : SIMD3<Float>(128, 128, 128)
            return FeaturePoint(x: e.position.x, y: e.position.y, z: e.position.z,
                                r: UInt8(c.x.rounded()), g: UInt8(c.y.rounded()), b: UInt8(c.z.rounded()),
                                seen: e.seen)
        }
    }
}

/// Full-range BT.601 YCbCr (what ARKit's camera image uses) to RGB.
public func ycbcrToRGB(y: UInt8, cb: UInt8, cr: UInt8) -> SIMD3<UInt8> {
    let l = Float(y), b = Float(cb) - 128, r = Float(cr) - 128
    func clamp(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
    return SIMD3(clamp(l + 1.402 * r), clamp(l - 0.344136 * b - 0.714136 * r), clamp(l + 1.772 * b))
}

/// How the live screen describes ARKit's tracking state, and the code written to frames.jsonl.
public enum TrackingKind: Equatable {
    case normal
    case notAvailable
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing
    case limited

    public var code: String {
        switch self {
        case .normal: return "normal"
        case .notAvailable: return "notAvailable"
        case .initializing: return "limited-initializing"
        case .excessiveMotion: return "limited-excessiveMotion"
        case .insufficientFeatures: return "limited-insufficientFeatures"
        case .relocalizing: return "limited-relocalizing"
        case .limited: return "limited"
        }
    }

    public var message: String {
        switch self {
        case .normal: return "Tracking well"
        case .notAvailable: return "Tracking not available"
        case .initializing: return "Starting: move the phone slowly"
        case .excessiveMotion: return "Too fast: slow down"
        case .insufficientFeatures: return "Not enough detail in view"
        case .relocalizing: return "Finding its place again"
        case .limited: return "Tracking is limited"
        }
    }

    public var isGood: Bool { self == .normal }
}
