import AppKit
import Combine
import SwiftUI

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

    var commandPlan: RenderCommandPlan {
        RenderCommandPlanner.plan(for: commandInputs)
    }

    var commandPreview: String {
        commandPlan.commandPreview
    }

    func runRender() {
        guard !isRunning else { return }
        isRunning = true
        let plan = commandPlan
        logText = "Running...\n\n\(plan.commandPreview)"

        let process = Process()
        let pipe = Pipe()
        let readHandle = pipe.fileHandleForReading
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [plan.executablePath] + plan.arguments
        process.currentDirectoryURL = plan.repositoryRoot
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
        environment["BH_PROJECT_ROOT"] = plan.repositoryRoot.path
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
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: plan.outputPath)])
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

    private var commandInputs: RenderCommandInputs {
        RenderCommandInputs(
            source: selectedSource,
            observerMode: observerMode,
            renderIntentID: renderIntentID,
            quality: quality,
            aspect: aspect,
            noBuild: noBuild,
            showAdvancedPhysics: showAdvancedPhysics,
            metricKerr: metricKerr,
            spin: spin,
            enableColorGrade: enableColorGrade,
            allowExperimentalCinematicControls: allowExperimentalCinematicControls,
            enableCinematicEffects: enableCinematicEffects,
            enableDepthOfField: enableDepthOfField,
            flareStrength: flareStrength,
            fNumber: fNumber,
            iso: iso,
            shutter: shutter,
            diskHDF5Path: diskHDF5Path,
            outputPath: outputPath
        )
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
