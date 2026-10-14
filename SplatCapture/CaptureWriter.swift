import ARKit
import AVFoundation
import CaptureKit

enum CaptureError: LocalizedError {
    case writer(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .writer(let why): return "Couldn't write the video: \(why)"
        case .empty: return "Nothing was recorded."
        }
    }
}

/// Writes one capture folder: video.mov (the camera image exactly as ARKit saw it), frames.jsonl
/// (one pose per video frame), points.json and meta.json. Use it from one queue only.
final class CaptureWriter {
    let folder: URL
    let width: Int
    let height: Int
    let fps: Double
    private(set) var count = 0
    private(set) var duration: Double = 0
    let points = PointAccumulator()
    /// Frames recorded while tracking wasn't normal.
    private(set) var limited = 0
    // for the quality report: sampled every `checkEvery` frames
    private var positions: [SIMD3<Float>] = []
    private var forwards: [SIMD3<Float>] = []
    private var sharpness: [Double] = []
    private let checkEvery = 3

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let rows: FileHandle
    private let encoder = JSONEncoder()
    private var firstTimestamp: TimeInterval?

    /// Feature points (and their colours) are sampled every this many frames: enough for a
    /// starting point cloud without slowing the recording down.
    private let pointEvery = 5

    init(folder: URL, width: Int, height: Int, fps: Double) throws {
        self.folder = folder
        self.width = width
        self.height = height
        self.fps = fps
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            try fm.removeItem(at: folder)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        writer = try AVAssetWriter(outputURL: folder.appendingPathComponent("video.mov"), fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 30_000_000,          // high: these frames are measured, not watched
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int(fps),
            ] as [String: Any],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw CaptureError.writer("the video input was refused") }
        writer.add(input)

        let rowsURL = folder.appendingPathComponent("frames.jsonl")
        fm.createFile(atPath: rowsURL.path, contents: nil)
        rows = try FileHandle(forWritingTo: rowsURL)
    }

    /// Adds one camera frame. A frame the encoder isn't ready for is skipped entirely (no video
    /// frame, no row), so row N is always video frame N.
    func append(_ frame: ARFrame, tracking: TrackingKind) {
        if firstTimestamp == nil {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: .zero)
            firstTimestamp = frame.timestamp
        }
        guard let t0 = firstTimestamp, writer.status == .writing, input.isReadyForMoreMediaData else { return }
        let time = frame.timestamp - t0
        if count > 0 && time <= duration { return }          // timestamps must increase
        let pts = CMTime(seconds: time, preferredTimescale: 1_000_000)
        guard adaptor.append(frame.capturedImage, withPresentationTime: pts) else { return }

        let row = FrameRow(index: count, time: time,
                           pose: FrameRow.rowMajor(frame.camera.transform),
                           intrinsics: FrameRow.flatIntrinsics(frame.camera.intrinsics),
                           tracking: tracking.code)
        if let line = try? row.jsonLine(encoder) {
            rows.write(line)
        }
        if count % pointEvery == 0 {
            collectPoints(frame)
        }
        if !tracking.isGood {
            limited += 1
        }
        if count % checkEvery == 0 {
            sharpness.append(Self.sharpness(frame.capturedImage))
            if tracking.isGood {
                let m = frame.camera.transform                  // camera looks along its -z axis
                positions.append(SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z))
                forwards.append(-SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
            }
        }
        count += 1
        duration = time
    }

    private func collectPoints(_ frame: ARFrame) {
        guard let cloud = frame.rawFeaturePoints else { return }
        let buffer = frame.capturedImage
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let size = CGSize(width: width, height: height)
        for (p, id) in zip(cloud.points, cloud.identifiers) {
            // the recorded image is the sensor's landscape image, so project for .landscapeRight
            let uv = frame.camera.projectPoint(p, orientation: .landscapeRight, viewportSize: size)
            points.add(id: id, position: p, color: Self.color(in: buffer, x: Int(uv.x), y: Int(uv.y)))
        }
    }

    /// How good the recording looks so far (see QualityReport).
    func quality() -> QualityReport {
        QualityReport.make(frames: count, limited: limited, sharpness: sharpness,
                           positions: positions, forwards: forwards)
    }

    /// Sharpness of the camera image's brightness (luma) plane.
    static func sharpness(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)
        return laplacianVariance(width: w, height: h) { x, y in luma[y * row + x] }
    }

    /// The colour of one pixel of ARKit's bi-planar YCbCr image (nil outside the image).
    static func color(in buffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8>? {
        guard CVPixelBufferGetPlaneCount(buffer) >= 2 else { return nil }
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        guard x >= 0, y >= 0, x < w, y < h,
              let lumaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let luma = lumaBase.load(fromByteOffset: y * lumaRow + x, as: UInt8.self)
        let offset = (y / 2) * chromaRow + (x / 2) * 2
        let cb = chromaBase.load(fromByteOffset: offset, as: UInt8.self)
        let cr = chromaBase.load(fromByteOffset: offset + 1, as: UInt8.self)
        return ycbcrToRGB(y: luma, cb: cb, cr: cr)
    }

    /// Closes the video and writes points.json and meta.json. Calls back on an arbitrary queue.
    func finish(meta: @escaping (CaptureWriter) -> CaptureMeta, completion: @escaping (Result<URL, Error>) -> Void) {
        try? rows.close()
        guard firstTimestamp != nil, count > 0 else {
            writer.cancelWriting()
            completion(.failure(CaptureError.empty))
            return
        }
        let pointsData = try? encoder.encode(PointsFile(points: points.export()))
        input.markAsFinished()
        writer.finishWriting { [self] in
            guard writer.status == .completed else {
                completion(.failure(writer.error ?? CaptureError.writer("the video didn't finish")))
                return
            }
            do {
                try pointsData?.write(to: folder.appendingPathComponent("points.json"))
                let pretty = JSONEncoder()
                pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
                try pretty.encode(meta(self)).write(to: folder.appendingPathComponent("meta.json"))
                completion(.success(folder))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
