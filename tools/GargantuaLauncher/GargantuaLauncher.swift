import SwiftUI

struct GargantuaLauncherView: View {
    @StateObject private var model = LauncherModel()
    @State private var commandExpanded = false

    var body: some View {
        NavigationSplitView {
            sourceSidebar
        } detail: {
            GeometryReader { geo in
                // Explicitly partition the detail width so the three columns
                // always sum to exactly what is on screen — no overflow / clip.
                let total = geo.size.width
                let leftW = min(372, max(264, total * 0.32))
                let rightW = min(320, max(232, total * 0.25))
                let centerW = max(220, total - leftW - rightW - 2)
                VStack(spacing: 0) {
                    WorkflowHeader(model: model)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Divider()
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                BlackHolePanel(model: model)
                                SourceSummaryPanel(model: model)
                                SourceDataPanel(model: model)
                                ObserverPanel(model: model)
                                if model.observerMode == .eye {
                                    EyeInterpreterPanel(model: model)
                                }
                                if model.isCameraMode {
                                    CameraInterpreterPanel(model: model)
                                }
                                RenderSetupPanel(model: model)
                                AdvancedPhysicsPanel(model: model)
                                PreviewControlsPanel(model: model)
                            }
                            .padding(14)
                            .frame(width: leftW - 28, alignment: .leading)
                        }
                        .frame(width: leftW)

                        Divider()

                        InteractivePreviewPanel(model: model)
                            .frame(width: centerW)

                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                CommandPanel(model: model, isExpanded: $commandExpanded)
                                ExecutionPanel(model: model)
                                ResultPanel(model: model)
                            }
                            .padding(14)
                            .frame(width: rightW - 28, alignment: .leading)
                        }
                        .frame(width: rightW)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: total, height: geo.size.height)
            }
            .navigationTitle("Observation Workflow")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1060, minHeight: 600)
        .onAppear { model.requestPreviewRender() }
        .onChange(of: previewTriggerKey) { model.requestPreviewRender() }
    }

    /// Every option that changes the rendered image, folded into one value so a
    /// single onChange schedules a preview re-render without a huge modifier chain.
    private var previewTriggerKey: String {
        [
            String(describing: model.blackHoleMetric),
            String(model.spin),
            model.selectedSourceID,
            String(describing: model.observerMode),
            model.renderIntentID,
            String(describing: model.previewQuality),
            String(describing: model.exposureProgram),
            String(model.exposureEV),
            String(model.fNumber),
            String(model.iso),
            model.shutter,
            String(model.enableColorGrade),
            String(model.enableCinematicEffects),
            String(model.enableDepthOfField),
            String(describing: model.eyePhotometric),
            String(model.useEyeND),
            String(model.eyeND),
            model.diskHDF5Path
        ].joined(separator: "|")
    }

    private var sourceSidebar: some View {
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
        .navigationTitle("Matter")
        .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
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
}

private struct WorkflowHeader: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Black Hole -> Matter -> Observer -> Interpreter -> Render")
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                WorkflowStep(title: "Black Hole", detail: model.blackHoleMetric.title, isActive: true)
                WorkflowStep(title: "Matter", detail: model.selectedSource.title, isActive: true)
                WorkflowStep(title: "Observer", detail: model.observerMode.title, isActive: true)
                WorkflowStep(
                    title: "Interpreter",
                    detail: model.isCameraMode ? model.selectedIntent.title : "Human vision",
                    isActive: true
                )
                WorkflowStep(title: "Render", detail: "\(model.outputSize.width)x\(model.outputSize.height)", isActive: model.isRunning)
            }
        }
    }
}

private struct WorkflowStep: View {
    let title: String
    let detail: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BlackHolePanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("1. Black Hole") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Metric", selection: $model.blackHoleMetric) {
                    ForEach(BlackHoleMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                if model.blackHoleMetric == .kerr {
                    LabeledInputSlider(label: "Spin", value: $model.spin, range: -0.999...0.999, format: "%.3f")
                } else {
                    Text("Schwarzschild fixes spin to zero and removes frame dragging from the generated command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }
}

private struct SourceSummaryPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("2. Accretion Source") {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedSource.title)
                    .font(.headline)
                Text(model.selectedSource.summary)
                    .foregroundStyle(.secondary)
                HStack {
                    Label(model.selectedSource.layer, systemImage: "scope")
                    Spacer()
                    Text(model.selectedSource.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.selectedSource.status == "legacy" ? Color.orange : Color.secondary)
                }
                .font(.caption)
            }
            .padding(4)
        }
    }
}

private struct SourceDataPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        if model.selectedSourceRequiresDiskHDF5 {
            GroupBox("Source Data") {
                HStack(spacing: 10) {
                    TextField("GRMHD HDF5 snapshot", text: $model.diskHDF5Path)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        model.chooseDiskHDF5()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                }
                .padding(4)
            }
        }
    }
}

private struct ObserverPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("3. Observer") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Mode", selection: $model.observerMode) {
                    ForEach(ObserverMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if model.isCameraMode {
                    Picker("Camera output", selection: $model.renderIntentID) {
                        ForEach(model.renderIntents) { intent in
                            Text(intent.title).tag(intent.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(model.selectedIntent.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Human-eye output applies safe-viewing, adaptation, and display interpretation after source radiance is formed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }
}

private struct EyeInterpreterPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("4. Human Eye Interpreter") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Photometric model", selection: $model.eyePhotometric) {
                    ForEach(EyePhotometricMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Use neutral-density safe-viewing filter", isOn: $model.useEyeND)
                if model.useEyeND {
                    LabeledInputSlider(label: "ND density", value: $model.eyeND, range: 0...8, format: "%.1f")
                }

                Toggle("Override adaptation luminance", isOn: $model.useEyeAdaptation)
                if model.useEyeAdaptation {
                    HStack {
                        Text("Adaptation")
                        Slider(value: $model.eyeAdaptation, in: 0.1...12000)
                        Text("\(Int(model.eyeAdaptation)) cd/m2")
                            .monospacedDigit()
                            .frame(width: 92, alignment: .trailing)
                    }
                }
            }
            .padding(4)
        }
    }
}

private struct CameraInterpreterPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("4. Camera Interpreter") {
            VStack(alignment: .leading, spacing: 14) {
                if model.isRawLikeCamera {
                    Label("RAW audit disables camera look, flare, DOF, PSF, and display noise. It writes linear32 and RGGB sidecars.", systemImage: "checkmark.seal")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    cameraExposure
                    Divider()
                    cameraOptics
                    Divider()
                    cinematicControls
                }
            }
            .padding(4)
        }
    }

    private var cameraExposure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Exposure mode", selection: $model.exposureProgram) {
                ForEach(CameraExposureProgram.allCases) { program in
                    Text(program.title).tag(program)
                }
            }
            .pickerStyle(.segmented)
            Text(model.exposureProgram.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Control precision", selection: $model.exposureGranularity) {
                ForEach(ExposureControlGranularity.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if model.exposureProgram != .fixedEV && model.exposureProgram != .shutterPriority {
                ApertureControl(model: model)
            }
            if model.exposureProgram == .manual || model.exposureProgram == .shutterPriority {
                ShutterControl(model: model)
            }
            if model.exposureProgram != .fixedEV {
                ISOControl(model: model)
            }
            if model.exposureProgram == .aperturePriority || model.exposureProgram == .shutterPriority || model.exposureProgram == .fixedEV {
                LabeledInputSlider(label: "EV", value: $model.exposureEV, range: -8...8, format: "%.1f")
            }
        }
    }

    private var cameraOptics: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledInputSlider(label: "Diffraction", value: $model.diffractionStrength, range: 0...0.25, format: "%.3f")
            LabeledInputSlider(label: "PSF blur", value: $model.psfSigma, range: 0...3, format: "%.2f")

            Picker("Photon noise", selection: $model.cameraPhotonNoise) {
                ForEach(CameraPhotonNoiseMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            LabeledInputSlider(label: "Photon scale", value: $model.cameraPhotonScale, range: 0.1...5.0, format: "%.2f")

            DisclosureGroup("Expert display-domain noise") {
                LabeledInputSlider(label: "Read noise", value: $model.readNoise, range: 0...0.1, format: "%.3f")
                LabeledInputSlider(label: "Shot noise", value: $model.shotNoise, range: 0...0.1, format: "%.3f")
            }
        }
    }

    private var cinematicControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Color grading / tone curve", isOn: $model.enableColorGrade)
            Toggle("Show experimental cinematic controls", isOn: $model.allowExperimentalCinematicControls)
            if model.allowExperimentalCinematicControls {
                Toggle("Cinematic flare / glare", isOn: $model.enableCinematicEffects)
                LabeledInputSlider(label: "Flare", value: $model.flareStrength, range: 0...1, format: "%.2f")
                    .disabled(!model.enableCinematicEffects)

                Toggle("Depth of field", isOn: $model.enableDepthOfField)
                if model.enableDepthOfField {
                    LabeledInputSlider(label: "Focus depth", value: $model.focusDepth, range: 1...80, format: "%.1f")
                }

                LabeledInputSlider(label: "Motion samples", value: $model.motionBlurSamples, range: 1...64, format: "%.0f")
                if model.motionBlurSamples > 1.5 {
                    LabeledInputSlider(label: "Time lapse", value: $model.motionBlurTimeLapse, range: 0.05...20, format: "%.2f")
                }
            }
        }
    }
}

private struct ApertureControl: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        if model.exposureGranularity == .stops {
            StopSlider(
                label: "Aperture",
                valueText: "f/\(String(format: "%.1f", model.fNumber))",
                index: Binding(
                    get: { CameraStopTables.nearestIndex(model.fNumber, in: CameraStopTables.fNumbers) },
                    set: { model.setFNumberStop(index: $0) }
                ),
                maxIndex: Double(CameraStopTables.fNumbers.count - 1)
            )
        } else {
            LabeledInputSlider(label: "f-number", value: $model.fNumber, range: 0.7...22, format: "%.2f")
        }
    }
}

private struct ISOControl: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        if model.exposureGranularity == .stops {
            StopSlider(
                label: "ISO",
                valueText: String(format: "%.0f", model.iso),
                index: Binding(
                    get: { CameraStopTables.nearestIndex(model.iso, in: CameraStopTables.isoValues) },
                    set: { model.setISOStop(index: $0) }
                ),
                maxIndex: Double(CameraStopTables.isoValues.count - 1)
            )
        } else {
            HStack(spacing: 8) {
                Text("ISO").frame(width: 80, alignment: .leading)
                Slider(value: $model.iso, in: 50...12800, step: 1)
                TextField("ISO", value: $model.iso, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
            }
        }
    }
}

private struct ShutterControl: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        if model.exposureGranularity == .stops {
            StopSlider(
                label: "Shutter",
                valueText: model.shutter,
                index: Binding(
                    get: { CameraStopTables.shutterIndex(model.shutter) },
                    set: { model.setShutterStop(index: $0) }
                ),
                maxIndex: Double(CameraStopTables.shutters.count - 1)
            )
        } else {
            HStack(spacing: 8) {
                Text("Shutter").frame(width: 80, alignment: .leading)
                TextField("1/60 or seconds", text: $model.shutter)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct StopSlider: View {
    let label: String
    let valueText: String
    @Binding var index: Double
    let maxIndex: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 80, alignment: .leading)
            Slider(value: $index, in: 0...maxIndex, step: 1)
            Text(valueText)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

private struct RenderSetupPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("5. Final Render Setup") {
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
                .pickerStyle(.menu)

                if model.aspect == .custom {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("Width")
                            TextField("Width", value: $model.customWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 84)
                            Stepper("", value: $model.customWidth, in: 64...8192, step: 64)
                                .labelsHidden()
                        }
                        GridRow {
                            Text("Height")
                            TextField("Height", value: $model.customHeight, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 84)
                            Stepper("", value: $model.customHeight, in: 64...8192, step: 64)
                                .labelsHidden()
                        }
                    }
                }

                Picker("SSAA", selection: $model.ssaa) {
                    ForEach(RenderSampling.allCases) { sampling in
                        Text(sampling.title).tag(sampling)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Temporal AA (sub-pixel jitter)", selection: $model.taaSamples) {
                        Text("Off").tag(1)
                        Text("4×").tag(4)
                        Text("8×").tag(8)
                        Text("16×").tag(16)
                    }
                    .pickerStyle(.segmented)
                    Text("Final render only — averages N Halton-jittered passes in linear HDR for smoother edges. Camera-sampling only; physics unchanged. Ignored for the raw-like intent and the live preview.")
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
}

private struct AdvancedPhysicsPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("Advanced Geometry And Validation") {
            DisclosureGroup("Physics / ray validation controls", isExpanded: $model.showAdvancedPhysics) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Ray bundle", selection: $model.rayBundleMode) {
                        ForEach(RayBundleMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if model.rayBundleMode == .jacobian {
                        LabeledInputSlider(label: "Jacobian strength", value: $model.rayBundleJacobianStrength, range: 0...4, format: "%.2f")
                        LabeledInputSlider(label: "Footprint clamp", value: $model.rayBundleFootprintClamp, range: 0...20, format: "%.1f")
                    }
                    Text("Ray-bundle controls affect physical sampling cost and are kept out of the preset path until explicitly opened.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }
}

private struct CommandPanel: View {
    @ObservedObject var model: LauncherModel
    @Binding var isExpanded: Bool

    var body: some View {
        GroupBox("Generated CLI") {
            DisclosureGroup("Show command", isExpanded: $isExpanded) {
                Text(model.commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(4)
        }
    }
}

private struct ExecutionPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("Run") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView(value: model.progressFraction)
                        .frame(maxWidth: .infinity)
                    Text(model.progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 104, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Button {
                        model.runRender()
                    } label: {
                        Label(model.isRunning ? "Rendering" : "Render", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isRunning)
                    Button {
                        model.stopRender()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .help("Stop render")
                    .disabled(!model.isRunning)
                    Button {
                        model.copyCommandToPasteboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy generated command")
                    Button {
                        model.refreshResult()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload final result")
                    Spacer(minLength: 0)
                }
                if !model.progressWorkLabel.isEmpty {
                    Text(model.progressWorkLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(model.logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 130)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(4)
        }
    }
}

private struct InteractivePreviewPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            InteractivePreviewViewport(model: model)

            if model.previewImage == nil {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                    Text(model.previewStatus)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            previewHUD
                .padding(12)

            VStack {
                Spacer()
                Text(model.isPreviewInteracting ? "Release to render this view" : "Drag to orbit · Scroll or pinch to zoom")
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.42), in: Capsule())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var previewHUD: some View {
        HStack(spacing: 8) {
            if model.isPreviewRendering {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "viewfinder").font(.caption)
            }
            Text(model.previewStatus)
                .font(.caption.weight(.medium))
        }
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.42), in: Capsule())
    }
}

private struct PreviewControlsPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("Interactive Preview") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Quality", selection: $model.previewQuality) {
                    ForEach(PreviewQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Toggle("Auto", isOn: $model.autoPreview)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button {
                        model.renderPreviewNow()
                    } label: {
                        Label("Render preview", systemImage: "bolt.fill")
                    }
                    .controlSize(.small)
                    .disabled(model.isPreviewRendering)
                }

                Divider()
                cameraControls

                Text("The preview runs the SAME renderer as Final Render — identical physics, disk model and colour science — only at lower resolution. Each camera move renders a quick pass, then a sharper one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var cameraControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Orbit camera")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    model.resetPreviewCamera()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
            }
            PreviewSlider(
                label: "Distance",
                value: Binding(
                    get: { Double(model.camera.state.radius) },
                    set: { model.setPreviewRadius($0) }
                ),
                range: Double(model.camera.minRadius)...Double(model.camera.maxRadius),
                format: "%.1f"
            )
            PreviewSlider(
                label: "Azimuth",
                value: Binding(
                    get: {
                        let d = model.camera.state.azimuthDegrees
                        return d - 360.0 * (d / 360.0).rounded()
                    },
                    set: { model.setPreviewAzimuth($0) }
                ),
                range: -180...180,
                format: "%.0f"
            )
            PreviewSlider(
                label: "Elevation",
                value: Binding(
                    get: { model.camera.state.elevationDegrees },
                    set: { model.setPreviewElevation($0) }
                ),
                range: -86...86,
                format: "%.0f"
            )
            PreviewSlider(
                label: "FOV",
                value: Binding(
                    get: { Double(model.camera.state.fov) },
                    set: { model.setPreviewFov($0) }
                ),
                range: 14...110,
                format: "%.0f"
            )
        }
    }
}

private struct PreviewSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 72, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private struct ResultPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Final Result")
                    .font(.headline)
                Spacer()
                Button {
                    model.revealOutput()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Reveal final output in Finder")
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black)
                if let image = model.resultImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.largeTitle)
                        Text(model.resultStatus)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 210)

            Text(model.resultStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.outputPath)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct LabeledInputSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
            Slider(value: $value, in: range)
            TextField(label, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
        }
    }
}

@main
struct GargantuaLauncherApp: App {
    var body: some Scene {
        WindowGroup("Project-Gargantua Launcher") {
            GargantuaLauncherView()
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
