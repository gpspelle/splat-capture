import XCTest
import simd
@testable import CaptureKit

final class FormatTests: XCTestCase {
    func testPoseIsWrittenRowMajor() {
        // translation lives in the last column of a camera-to-world matrix
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(1, 2, 3, 1)
        m.columns.0 = SIMD4<Float>(0, 1, 0, 0)      // first column: x axis points along world y
        let p = FrameRow.rowMajor(m)
        XCTAssertEqual(p.count, 16)
        XCTAssertEqual([p[3], p[7], p[11], p[15]], [1, 2, 3, 1])
        XCTAssertEqual([p[0], p[4], p[8]], [0, 1, 0])
    }

    func testIntrinsicsOrder() {
        let k = simd_float3x3(columns: (SIMD3(1500, 0, 0), SIMD3(0, 1490, 0), SIMD3(960, 720, 1)))
        XCTAssertEqual(FrameRow.flatIntrinsics(k), [1500, 1490, 960, 720])
    }

    func testJsonLineUsesShortKeys() throws {
        let row = FrameRow(index: 3, time: 0.1, pose: Array(repeating: 0, count: 16),
                           intrinsics: [1, 2, 3, 4], tracking: "normal")
        let line = try row.jsonLine()
        XCTAssertEqual(line.last, 0x0A)
        let obj = try JSONSerialization.jsonObject(with: line.dropLast()) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), ["i", "t", "pose", "K", "tracking"])
        XCTAssertEqual(try JSONDecoder().decode(FrameRow.self, from: line.dropLast()), row)
    }

    func testMetaNamesTheFormat() throws {
        let meta = CaptureMeta(app: "0.1.0", device: "iPhone15,2", system: "17.0", started: Date(timeIntervalSince1970: 0),
                               width: 1920, height: 1440, fps: 30, frames: 10, duration: 0.3, points: 5, lidar: false)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(meta)) as! [String: Any]
        XCTAssertEqual(obj["format"] as? String, "splat-capture")
        XCTAssertEqual(obj["version"] as? Int, 1)
        XCTAssertEqual(obj["started"] as? String, "1970-01-01T00:00:00Z")
    }
}

final class PointTests: XCTestCase {
    func testKeepsLatestPositionAndAveragesColour() {
        let acc = PointAccumulator()
        acc.add(id: 7, position: SIMD3(0, 0, 0), color: SIMD3(100, 0, 0))
        acc.add(id: 7, position: SIMD3(1, 1, 1), color: SIMD3(200, 50, 0))
        acc.add(id: 9, position: SIMD3(5, 5, 5), color: nil)          // seen once: dropped
        let pts = acc.export()
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0], FeaturePoint(x: 1, y: 1, z: 1, r: 150, g: 25, b: 0, seen: 2))
        XCTAssertEqual(acc.export(minSeen: 1).count, 2)
        XCTAssertEqual(acc.export(minSeen: 1)[1].r, 128)               // no colour: grey
    }

    func testYCbCrGreyAndClamping() {
        XCTAssertEqual(ycbcrToRGB(y: 128, cb: 128, cr: 128), SIMD3(128, 128, 128))
        XCTAssertEqual(ycbcrToRGB(y: 255, cb: 128, cr: 255), SIMD3(255, 164, 255))
        XCTAssertEqual(ycbcrToRGB(y: 0, cb: 0, cr: 0).z, 0)
    }

    func testTrackingCodes() {
        XCTAssertEqual(TrackingKind.excessiveMotion.code, "limited-excessiveMotion")
        XCTAssertTrue(TrackingKind.normal.isGood)
        XCTAssertFalse(TrackingKind.initializing.isGood)
    }
}
