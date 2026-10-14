import ARKit
import CaptureKit
import SwiftUI

struct ContentView: View {
    @StateObject private var recorder = Recorder()
    @StateObject private var library = CaptureLibrary()
    @State private var showLibrary = false
    @AppStorage("captureName") private var name = ""
    @FocusState private var naming: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if Recorder.isSupported {
                camera
            } else {
                unsupported
            }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(library: library)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { recorder.lastError != nil },
            set: { if !$0 { recorder.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.lastError ?? "")
        }
        .onReceive(recorder.$saved) { _ in
            library.refresh()
        }
    }

    private var camera: some View {
        ZStack {
            ARPreview(session: recorder.session)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    trackingBadge
                    Spacer()
                    Button {
                        showLibrary = true
                    } label: {
                        Label("\(library.items.count)", systemImage: "square.stack.3d.up")
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(recorder.phase != .idle)
                    .accessibilityLabel("Captures")
                }
                Spacer()
                if recorder.phase == .recording {
                    stats
                } else if recorder.phase == .idle {
                    VStack(spacing: 10) {
                        TextField("What are you filming? (optional)", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .focused($naming)
                            .accessibilityLabel("Recording name")
                        Text("Point at the object, then record: focus and exposure stay as they are when you start. Walk slowly round it, once low, once at chest height and once from above.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                recordButton
            }
            .padding()
        }
        .sheet(item: $recorder.saved) { saved in
            QualityView(saved: saved) {
                try? FileManager.default.removeItem(at: saved.url)
                library.refresh()
            }
        }
        .onAppear { recorder.start() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { recorder.start() } else if phase == .background { recorder.pause() }
        }
    }

    private var trackingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(recorder.tracking.isGood ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            Text(recorder.tracking.message)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var stats: some View {
        HStack(spacing: 18) {
            stat(Self.clock(recorder.seconds), "time")
            stat("\(recorder.frames)", "frames")
            stat("\(recorder.points)", "points")
            stat("\(Int((recorder.limitedShare * 100).rounded()))%", "unsteady")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recordButton: some View {
        Button {
            naming = false
            recorder.toggle(name: name)
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                if recorder.phase == .recording {
                    RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                } else if recorder.phase == .saving {
                    ProgressView().tint(.white)
                } else {
                    Circle().fill(.red).frame(width: 64, height: 64)
                }
            }
        }
        .disabled(recorder.phase == .saving)
        .accessibilityLabel(recorder.phase == .recording ? "Stop recording" : "Start recording")
    }

    private var unsupported: some View {
        VStack(spacing: 12) {
            Image(systemName: "arkit").font(.largeTitle)
            Text("This device can't track its position (ARKit world tracking). Splat Capture needs an iPhone or iPad from the last few years.")
                .multilineTextAlignment(.center)
            Button("Captures") { showLibrary = true }
        }
        .padding()
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ARPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.debugOptions = [.showFeaturePoints]       // the yellow dots: what ARKit is tracking
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}

struct LibraryView: View {
    @ObservedObject var library: CaptureLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if library.items.isEmpty {
                    Text("No captures yet. Record one, then send it to your Mac with AirDrop and open it in Splat Studio.")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.monospacedDigit())
                            Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: item.url) {
                            Label("Send", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { library.delete(library.items[i]) }
                }
            }
            .navigationTitle("Captures")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { library.refresh() }
        }
    }
}

/// Shown right after a recording stops: is it worth sending, or better filmed again?
struct QualityView: View {
    let saved: SavedCapture
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if saved.quality.looksGood {
                        Label("Looks good to train", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(saved.quality.warnings, id: \.self) { w in
                            Label(w, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Section("This recording") {
                    row("Length", ContentView.clock(saved.seconds))
                    row("Frames", "\(saved.frames)")
                    row("Filmed around", saved.quality.gap.map { "\(Int((360 - $0).rounded()))°" } ?? "?")
                    row("Height range", saved.quality.heights.map { "\(Int($0.rounded()))°" } ?? "?")
                    row("Unsteady tracking", Self.percent(saved.quality.unsteady))
                    row("Blurry frames", Self.percent(saved.quality.blurry))
                    row("Focus and exposure", saved.cameraLocked ? "locked" : "automatic")
                }
                Section {
                    ShareLink(item: saved.url) {
                        Label("Send to the Mac", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete and film again", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(saved.name.isEmpty ? "Recording saved" : saved.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete this recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    delete()
                    dismiss()
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}
