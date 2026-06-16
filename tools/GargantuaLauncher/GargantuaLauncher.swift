import AppKit
import Combine
import SwiftUI

struct SourceModelOption: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let layer: String
    let status: String
    let summary: String
    let requiresDiskHDF5: Bool?
    let defaultDiskHDF5: String?
    let args: [String]
}

struct RenderIntentOption: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let summary: String
}

struct LauncherOptionsManifest: Codable {
    let schemaVersion: Int
    let sourceModels: [SourceModelOption]
    let renderIntents: [RenderIntentOption]

    static func load() -> LauncherOptionsManifest {
        let decoder = JSONDecoder()
        for path in manifestSearchPaths() {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(LauncherOptionsManifest.self, from: data),
                  manifest.schemaVersion == 1,
                  !manifest.sourceModels.isEmpty,
                  !manifest.renderIntents.isEmpty else {
                continue
            }
            return manifest
        }
        return fallback
    }

    private static func manifestSearchPaths() -> [String] {
        ProjectPaths.manifestSearchPaths()
    }

    private static let fallback = LauncherOptionsManifest(
        schemaVersion: 1,
        sourceModels: [
            SourceModelOption(
                id: "canonical-visible-disk-v1",
                title: "Canonical Visible Disk",
                layer: "SourceModels / ThinDisk",
                status: "recommended",
                summary: "Recommended scientific visible-disk baseline.",
                requiresDiskHDF5: nil,
                defaultDiskHDF5: nil,
                args: ["--source-model", "canonical-visible-disk-v1"]
            ),
            SourceModelOption(
                id: "legacy-perlin",
                title: "Legacy Perlin",
                layer: "Legacy",
                status: "legacy",
                summary: "Historic soft Perlin disk reproduction path.",
                requiresDiskHDF5: nil,
                defaultDiskHDF5: nil,
                args: ["--disk-mode", "thin", "--disk-model", "perlin"]
            ),
            SourceModelOption(
                id: "legacy-perlin-classic",
                title: "Legacy Perlin F552 Classic",
                layer: "Legacy",
                status: "legacy",
                summary: "Historic F552/classic stripe-like disk reproduction path.",
                requiresDiskHDF5: nil,
                defaultDiskHDF5: nil,
                args: ["--disk-mode", "thin", "--disk-model", "perlin-classic"]
            ),
            SourceModelOption(
                id: "legacy-perlin-ec7",
                title: "Legacy Perlin EC7 Crisp",
                layer: "Legacy",
                status: "legacy",
                summary: "Historic crisp EC7 Perlin reproduction path.",
                requiresDiskHDF5: nil,
                defaultDiskHDF5: nil,
                args: ["--disk-mode", "thin", "--disk-model", "perlin-ec7"]
            ),
            SourceModelOption(
                id: "legacy-bh-finish-grmhd",
                title: "Legacy bh_finish GRMHD",
                layer: "Legacy / GRMHD",
                status: "legacy",
                summary: "Recovered bh_finish_cinema_1536.png family.",
                requiresDiskHDF5: true,
                defaultDiskHDF5: "/private/tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05010.h5",
                args: ["--science-regime", "legacy-bh-finish-grmhd"]
            ),
            SourceModelOption(
                id: "legacy-thin-disk-preset-default",
                title: "Legacy Thin Disk Preset Default",
                layer: "Legacy / DNGR Volume",
                status: "legacy",
                summary: "Recovered thin_disk_preset_default.png family.",
                requiresDiskHDF5: nil,
                defaultDiskHDF5: nil,
                args: ["--science-regime", "legacy-thin-disk-preset-default"]
            )
        ],
        renderIntents: [
            RenderIntentOption(
                id: "raw-like",
                title: "Scientific RAW / Linear Audit",
                summary: "Identity linear preview plus ideal RGGB float32 CFA RAW sidecar."
            ),
            RenderIntentOption(
                id: "rendered",
                title: "Camera Rendered",
                summary: "Full-frame photographic exposure with restrained tone mapping."
            ),
            RenderIntentOption(
                id: "cinematic",
                title: "Cinematic Grade",
                summary: "Cinema profile, filmic look, flare, and optional depth of field."
            )
        ]
    )
}

enum ProjectPaths {
    static let sourceFilePath = String(#filePath)

    static var repositoryRoot: URL {
        if let envRoot = ProcessInfo.processInfo.environment["BH_PROJECT_ROOT"],
           let root = validateRepositoryRoot(URL(fileURLWithPath: envRoot)) {
            return root
        }

        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent(),
            Bundle.main.resourceURL
        ].compactMap { $0 }

        for candidate in candidates {
            if let root = findRepositoryRoot(startingAt: candidate) {
                return root
            }
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static var runPipelineURL: URL {
        repositoryRoot.appendingPathComponent("Blackhole/run_pipeline.sh")
    }

    static func manifestSearchPaths() -> [String] {
        var paths = [
            repositoryRoot.appendingPathComponent("docs/realism/gui_option_manifest_v1.json").path
        ]
        if let bundleResource = Bundle.main.resourceURL {
            paths.append(bundleResource.appendingPathComponent("gui_option_manifest_v1.json").path)
        }
        return paths
    }

    private static func findRepositoryRoot(startingAt start: URL) -> URL? {
        var current = start.hasDirectoryPath ? start : start.deletingLastPathComponent()
        for _ in 0..<12 {
            if let root = validateRepositoryRoot(current) {
                return root
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }

    private static func validateRepositoryRoot(_ url: URL) -> URL? {
        let script = url.appendingPathComponent("Blackhole/run_pipeline.sh").path
        let manifest = url.appendingPathComponent("docs/realism/gui_option_manifest_v1.json").path
        guard FileManager.default.isExecutableFile(atPath: script),
              FileManager.default.fileExists(atPath: manifest) else {
            return nil
        }
        return url
    }
}

enum ObserverMode: String, CaseIterable, Identifiable {
    case eye
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eye: return "Human Eye"
        case .camera: return "Camera"
        }
    }
}

enum RenderQuality: String, CaseIterable, Identifiable {
    case preview
    case hq

    var id: String { rawValue }
}

enum OutputAspect: String, CaseIterable, Identifiable {
    case hd
    case square
    case small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hd: return "1536 x 864"
        case .square: return "1024 x 1024"
        case .small: return "768 x 432"
        }
    }

    var size: (width: Int, height: Int) {
        switch self {
        case .hd: return (1536, 864)
        case .square: return (1024, 1024)
        case .small: return (768, 432)
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    let sourceModels: [SourceModelOption]
    let renderIntents: [RenderIntentOption]

    @Published var selectedSourceID = "canonical-visible-disk-v1"
    @Published var observerMode: ObserverMode = .eye
    @Published var renderIntentID = "rendered"
    @Published var quality: RenderQuality = .preview
    @Published var aspect: OutputAspect = .hd
    @Published var noBuild = true
    @Published var metricKerr = true
    @Published var showAdvancedPhysics = false
    @Published var spin = 0.6
    @Published var enableColorGrade = false
    @Published var allowExperimentalCinematicControls = false
    @Published var enableCinematicEffects = false
    @Published var enableDepthOfField = false
    @Published var flareStrength = 0.2
    @Published var fNumber = 4.0
    @Published var iso = 100.0
    @Published var shutter = "1/60"
    @Published var diskHDF5Path = "/private/tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05010.h5"
    @Published var outputPath = "/private/tmp/gargantua_gui_render.png"
    @Published var logText = "Ready."
    @Published var isRunning = false
    private var runningProcess: Process?
    private var runningReadHandle: FileHandle?

    init() {
        let manifest = LauncherOptionsManifest.load()
        self.sourceModels = manifest.sourceModels
        self.renderIntents = manifest.renderIntents
    }

    var selectedSource: SourceModelOption {
        sourceModels.first { $0.id == selectedSourceID } ?? sourceModels[0]
    }

    var selectedIntent: RenderIntentOption {
        renderIntents.first { $0.id == renderIntentID } ?? renderIntents[1]
    }

    var isCameraMode: Bool {
        observerMode == .camera
    }

    var isCameraAdjustmentEnabled: Bool {
        isCameraMode && renderIntentID != "raw-like"
    }

    var selectedSourceRequiresDiskHDF5: Bool {
        selectedSource.requiresDiskHDF5 ?? false
    }

    var effectiveDiskHDF5Path: String {
        let explicit = diskHDF5Path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }
        return selectedSource.defaultDiskHDF5 ?? ""
    }

    var rawBufferPath: String {
        outputPath + ".raw.linear32f32"
    }

    var sensorRawBufferPath: String {
        outputPath + ".bayer-rggb-f32.raw"
    }

    var builtArguments: [String] {
        var args: [String] = []
        args.append(contentsOf: selectedSource.args)
        if selectedSourceRequiresDiskHDF5 {
            args.append(contentsOf: ["--disk-hdf5", effectiveDiskHDF5Path])
        }
        args.append(contentsOf: ["--quality", quality.rawValue])

        let size = aspect.size
        args.append(contentsOf: ["--width", "\(size.width)", "--height", "\(size.height)"])

        if showAdvancedPhysics && metricKerr {
            args.append(contentsOf: ["--metric", "kerr", "--spin", formatted(spin)])
        }

        switch observerMode {
        case .eye:
            args.append(contentsOf: [
                "--presentation", "eye",
                "--camera-model", "eye",
                "--realism-profile", "physical",
                "--look", "realistic"
            ])
        case .camera:
            args.append(contentsOf: cameraArguments())
        }

        if noBuild {
            args.append("--no-build")
        }
        args.append(contentsOf: ["--output", outputPath])
        return args
    }

    var commandPreview: String {
        ([ProjectPaths.runPipelineURL.path] + builtArguments).map(shellQuoted).joined(separator: " ")
    }

    func runRender() {
        guard !isRunning else { return }
        isRunning = true
        logText = "Running...\n\n\(commandPreview)"

        let args = builtArguments
        let output = outputPath
        let process = Process()
        let pipe = Pipe()
        let readHandle = pipe.fileHandleForReading
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [ProjectPaths.runPipelineURL.path] + args
        process.currentDirectoryURL = ProjectPaths.repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        let guiPath = [
            environment["PATH"],
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Applications/Xcode.app/Contents/Developer/usr/bin"
        ].compactMap { $0 }.joined(separator: ":")
        environment["PATH"] = guiPath
        environment["BH_PROJECT_ROOT"] = ProjectPaths.repositoryRoot.path
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        runningProcess = process
        runningReadHandle = readHandle

        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.logText += "\n" + text
            }
        }

        process.terminationHandler = { [weak self] proc in
            readHandle.readabilityHandler = nil
            let data = readHandle.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.runningProcess = nil
                self?.runningReadHandle = nil
                if !text.isEmpty {
                    self?.logText += "\n" + text
                }
                self?.logText += "\nRender finished with status \(proc.terminationStatus)."
                if proc.terminationStatus == 0 {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: output)])
                }
            }
        }

        do {
            try process.run()
        } catch {
            isRunning = false
            runningProcess = nil
            runningReadHandle = nil
            logText = "Failed to start render: \(error.localizedDescription)"
        }
    }

    func stopRender() {
        guard isRunning else { return }
        logText += "\nStopping render..."
        runningProcess?.terminate()
    }

    func copyCommandToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandPreview, forType: .string)
    }

    func chooseDiskHDF5() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            diskHDF5Path = url.path
        }
    }

    private func cameraArguments() -> [String] {
        if renderIntentID == "raw-like" {
            return [
                "--presentation", "camera-raw",
                "--camera-model", "legacy",
                "--camera-profile", "ideal",
                "--look", "linear",
                "--exposure-mode", "fixed",
                "--exposure-ev", "0",
                "--camera-psf-sigma", "0",
                "--camera-read-noise", "0",
                "--camera-shot-noise", "0",
                "--camera-flare", "0",
                "--camera-dof-strength", "0",
                "--background", "off",
                "--hdr-intermediate",
                "--hdr-out", rawBufferPath,
                "--camera-raw-out", sensorRawBufferPath
            ]
        }

        var args: [String] = [
            "--presentation", renderIntentID == "cinematic" ? "cinema" : "camera-rendered",
            "--camera-model", "cinematic",
            "--exposure-mode", "photographic",
            "--camera-f-number", formatted(fNumber),
            "--camera-iso", formatted(iso),
            "--camera-shutter", shutter
        ]

        if renderIntentID == "cinematic" {
            args.append(contentsOf: [
                "--camera-profile", "cinema-digital",
                "--look", enableColorGrade ? "sensor-filmic" : "linear",
                "--realism-profile", "cinematic",
                "--camera-flare", formatted((allowExperimentalCinematicControls && enableCinematicEffects) ? flareStrength : 0.0),
                "--camera-dof-strength", formatted((allowExperimentalCinematicControls && enableDepthOfField) ? 1.0 : 0.0),
                "--camera-aperture-blades", "7"
            ])
        } else {
            args.append(contentsOf: [
                "--camera-profile", "full-frame",
                "--look", enableColorGrade ? "agx" : "linear",
                "--realism-profile", "observational",
                "--camera-flare", formatted((allowExperimentalCinematicControls && enableCinematicEffects) ? flareStrength : 0.0),
                "--camera-dof-strength", formatted((allowExperimentalCinematicControls && enableDepthOfField) ? 0.6 : 0.0)
            ])
        }
        return args
    }

    private func shellQuoted(_ value: String) -> String {
        if value.range(of: #"[^A-Za-z0-9_@%+=:,./-]"#, options: .regularExpression) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}

struct GargantuaLauncherView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSourceID) {
                Section("Recommended") {
                    sourceRows(statuses: ["recommended", "production-candidate"])
                }
                Section("Diagnostics") {
                    sourceRows(statuses: ["diagnostic", "surrogate"])
                }
                Section("Legacy") {
                    sourceRows(statuses: ["legacy"])
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Gargantua")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sourceDataSection
                    observerSection
                    cameraSection
                    renderSection
                    commandSection
                    logSection
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .navigationTitle("Render Setup")
        }
        .frame(minWidth: 980, minHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.selectedSource.title)
                .font(.title2.weight(.semibold))
            Text(model.selectedSource.summary)
                .foregroundStyle(.secondary)
            Text(model.selectedSource.layer)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(model.selectedSource.status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.selectedSource.status == "legacy" ? Color.orange : Color.secondary)
        }
    }

    private var observerSection: some View {
        GroupBox("Observer") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Mode", selection: $model.observerMode) {
                    ForEach(ObserverMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if model.isCameraMode {
                    Picker("Camera intent", selection: $model.renderIntentID) {
                        ForEach(model.renderIntents) { intent in
                            Text(intent.title).tag(intent.id)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(model.selectedIntent.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Eye mode consumes the same source radiance and applies human-vision presentation only.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var sourceDataSection: some View {
        if model.selectedSourceRequiresDiskHDF5 {
            GroupBox("Source Data") {
                HStack(spacing: 10) {
                    TextField("GRMHD HDF5 snapshot", text: $model.diskHDF5Path)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose HDF5") {
                        model.chooseDiskHDF5()
                    }
                }
                .padding(4)
            }
        }
    }

    private var cameraSection: some View {
        GroupBox("Camera And Cinematic Controls") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Color grading / tone curve", isOn: $model.enableColorGrade)
                Toggle("Show experimental cinematic controls", isOn: $model.allowExperimentalCinematicControls)
                Toggle("Cinematic flare / glare", isOn: $model.enableCinematicEffects)
                HStack {
                    Text("Flare")
                    Slider(value: $model.flareStrength, in: 0...1)
                    Text(model.flareStrength, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(!model.allowExperimentalCinematicControls || !model.enableCinematicEffects)

                Toggle("Depth of field", isOn: $model.enableDepthOfField)
                    .disabled(!model.allowExperimentalCinematicControls)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("f-number")
                        Slider(value: $model.fNumber, in: 0.7...16)
                        Text(model.fNumber, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    GridRow {
                        Text("ISO")
                        Slider(value: $model.iso, in: 50...3200)
                        Text(model.iso, format: .number.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    GridRow {
                        Text("Shutter")
                        TextField("1/60", text: $model.shutter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Text("seconds or fraction")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(4)
            .disabled(!model.isCameraAdjustmentEnabled)
        }
    }

    @ViewBuilder
    private func sourceRows(statuses: Set<String>) -> some View {
        ForEach(model.sourceModels.filter { statuses.contains($0.status) }) { source in
            VStack(alignment: .leading, spacing: 3) {
                Text(source.title)
                    .font(.headline)
                Text("\(source.status) - \(source.layer)")
                    .font(.caption)
                    .foregroundStyle(source.status == "legacy" ? Color.orange : Color.secondary)
            }
            .tag(source.id)
        }
    }

    private var renderSection: some View {
        GroupBox("Render") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Quality", selection: $model.quality) {
                    ForEach(RenderQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Size", selection: $model.aspect) {
                    ForEach(OutputAspect.allCases) { aspect in
                        Text(aspect.title).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)

                DisclosureGroup("Advanced physics / validation required", isExpanded: $model.showAdvancedPhysics) {
                    Toggle("Kerr metric", isOn: $model.metricKerr)
                    HStack {
                        Text("Spin")
                        Slider(value: $model.spin, in: -0.999...0.999)
                        Text(model.spin, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .disabled(!model.metricKerr)
                    Text("These controls are visible for validation work. Phase 2 geodesic gates are not complete yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Skip build", isOn: $model.noBuild)

                TextField("Output path", text: $model.outputPath)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(4)
        }
    }

    private var commandSection: some View {
        GroupBox("Generated CLI") {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button("Copy Command") {
                        model.copyCommandToPasteboard()
                    }
                    Button(model.isRunning ? "Rendering..." : "Render") {
                        model.runRender()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isRunning)
                    Button("Stop") {
                        model.stopRender()
                    }
                    .disabled(!model.isRunning)
                }
            }
            .padding(4)
        }
    }

    private var logSection: some View {
        GroupBox("Log") {
            ScrollView {
                Text(model.logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 130)
        }
    }
}

@main
struct GargantuaLauncherApp: App {
    var body: some Scene {
        WindowGroup("Project-Gargantua Launcher") {
            GargantuaLauncherView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
