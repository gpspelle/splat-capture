import Foundation
import simd

/// How good a recording looks for training, worked out on the phone right after it stops.
/// The thresholds are Splat Studio's: a gap over 60 degrees, heights within 15 degrees.
public struct QualityReport: Codable, Equatable {
    /// Share of frames where tracking wasn't normal (0...1).
    public var unsteady: Double
    /// Share of sampled frames much blurrier than the recording's typical frame (0...1).
    public var blurry: Double
    /// The largest part of the circle around the object with no camera, in degrees
    /// (nil when the object couldn't be located).
    public var gap: Double?
    /// Degrees between the low and the high views (10th to 90th percentile).
    public var heights: Double?

    public init(unsteady: Double, blurry: Double, gap: Double?, heights: Double?) {
        self.unsteady = unsteady
        self.blurry = blurry
        self.gap = gap
        self.heights = heights
    }

    public static let maxGap = 60.0
    public static let minHeights = 15.0
    public static let maxUnsteady = 0.2
    public static let maxBlurry = 0.2

    /// What to fix, in plain words; empty when the recording looks good.
    public var warnings: [String] {
        var out: [String] = []
        if let g = gap {
            if g > Self.maxGap {
                out.append("About \(Int(g.rounded()))° around the object wasn't filmed (fine if a wall or another object stands there).")
            }
        } else {
            out.append("Couldn't tell where the object is. Keep it in the middle of the view as you walk round.")
        }
        if let h = heights, h < Self.minHeights {
            out.append("Everything was filmed from about the same height. Add a low and a high loop.")
        }
        if unsteady > Self.maxUnsteady {
            out.append("Tracking was unsteady \(Self.percent(unsteady)) of the time. Move more slowly.")
        }
        if blurry > Self.maxBlurry {
            out.append("\(Self.percent(blurry)) of the frames are blurry. Move more slowly or add light.")
        }
        return out
    }

    public var looksGood: Bool { warnings.isEmpty }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// Builds the report from what the recorder collected: camera positions and viewing
    /// directions (world, y up; only frames with normal tracking), and sharpness samples.
    public static func make(frames: Int, limited: Int, sharpness: [Double],
                            positions: [SIMD3<Float>], forwards: [SIMD3<Float>]) -> QualityReport {
        let unsteady = frames > 0 ? Double(limited) / Double(frames) : 0
        let blurry = blurryShare(sharpness)
        guard let c = centre(positions: positions, forwards: forwards) else {
            return QualityReport(unsteady: unsteady, blurry: blurry, gap: nil, heights: nil)
        }
        var azimuths: [Double] = []
        var elevations: [Double] = []
        for p in positions {
            let d = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z)) - c
            let flat = (d.x * d.x + d.z * d.z).squareRoot()
            guard simd_length(d) > 1e-6 else { continue }
            azimuths.append(atan2(d.z, d.x) * 180 / .pi)
            elevations.append(atan2(d.y, flat) * 180 / .pi)
        }
        let heights = elevations.isEmpty ? nil : percentile(elevations, 0.9) - percentile(elevations, 0.1)
        return QualityReport(unsteady: unsteady, blurry: blurry, gap: largestGap(azimuths), heights: heights)
    }

    /// The point closest to every camera's line of sight (least squares): what the cameras were
    /// looking at. Nil when the views are nearly parallel or the point would be behind them.
    public static func centre(positions: [SIMD3<Float>], forwards: [SIMD3<Float>]) -> SIMD3<Double>? {
        guard positions.count >= 3, positions.count == forwards.count else { return nil }
        var a = simd_double3x3()
        var b = SIMD3<Double>(0, 0, 0)
        for (p, f) in zip(positions, forwards) {
            let d = simd_normalize(SIMD3<Double>(Double(f.x), Double(f.y), Double(f.z)))
            let m = matrix_identity_double3x3 - simd_double3x3(columns: (d * d.x, d * d.y, d * d.z))
            a += m
            b += m * SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
        }
        let n = Double(positions.count)
        guard abs(simd_determinant(a)) > 1e-4 * n * n * n else { return nil }
        let c = a.inverse * b
        var ahead = 0
        for (p, f) in zip(positions, forwards) {
            let toC = c - SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
            if simd_dot(toC, SIMD3<Double>(Double(f.x), Double(f.y), Double(f.z))) > 0 { ahead += 1 }
        }
        return Double(ahead) >= 0.8 * n ? c : nil
    }

    /// Largest empty arc between sorted angles (degrees), around the full circle.
    public static func largestGap(_ degrees: [Double]) -> Double {
        guard degrees.count >= 2 else { return 360 }
        let s = degrees.map { ($0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }.sorted()
        var gap = 360 - s[s.count - 1] + s[0]
        for (x, y) in zip(s, s.dropFirst()) {
            gap = max(gap, y - x)
        }
        return gap
    }

    /// Share of sharpness scores below half the median (Splat Studio's blur filter).
    public static func blurryShare(_ scores: [Double], ratio: Double = 0.5) -> Double {
        guard !scores.isEmpty else { return 0 }
        let median = scores.sorted()[scores.count / 2]
        return Double(scores.filter { $0 < median * ratio }.count) / Double(scores.count)
    }

    static func percentile(_ xs: [Double], _ q: Double) -> Double {
        let s = xs.sorted()
        return s[min(s.count - 1, max(0, Int((Double(s.count - 1) * q).rounded())))]
    }
}

/// Sharpness of a greyscale image: the variance of a Laplacian over the middle half of the image,
/// on a grid `step` pixels apart (fast enough to run during recording). Higher is sharper.
public func laplacianVariance(width: Int, height: Int, step: Int = 4, pixel: (Int, Int) -> UInt8) -> Double {
    var sum = 0.0, sumSq = 0.0, n = 0.0
    let x0 = max(step, width / 4), x1 = min(width - step - 1, 3 * width / 4)
    let y0 = max(step, height / 4), y1 = min(height - step - 1, 3 * height / 4)
    guard x0 < x1, y0 < y1 else { return 0 }
    for y in stride(from: y0, to: y1, by: step) {
        for x in stride(from: x0, to: x1, by: step) {
            let c = 4 * Double(pixel(x, y))
            let l = c - Double(pixel(x - step, y)) - Double(pixel(x + step, y))
                - Double(pixel(x, y - step)) - Double(pixel(x, y + step))
            sum += l
            sumSq += l * l
            n += 1
        }
    }
    guard n > 0 else { return 0 }
    let mean = sum / n
    return sumSq / n - mean * mean
}

/// A file-name-safe version of what the person typed: letters, digits and dashes.
public func captureSlug(_ name: String, maxLength: Int = 40) -> String {
    var out = ""
    var dash = false
    for ch in name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX")) {
        if ch.isASCII && (ch.isLetter || ch.isNumber) {
            out.append(ch)
            dash = false
        } else if !dash && !out.isEmpty {
            out.append("-")
            dash = true
        }
    }
    while out.hasSuffix("-") { out.removeLast() }
    return String(out.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}
