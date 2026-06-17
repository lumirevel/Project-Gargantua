import SwiftUI

struct GargantuaLauncherView: View {
    @StateObject private var model = LauncherModel()
    @State private var commandExpanded = false

    var body: some View {
        // No NavigationSplitView: a collapsing sidebar can overlay (cover) the
        // settings on narrow widths. Instead lay out three columns explicitly
        // across the full window so nothing is ever obscured, and the source
        // selector lives inside the settings dashboard.
        GeometryReader { geo in
            let total = geo.size.width
            let leftW = min(376, max(290, total * 0.31))
            let rightW = min(324, max(248, total * 0.25))
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
                            MatterSourcePanel(model: model)
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
        .frame(minWidth: 1000, minHeight: 600)
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

private struct MatterSourcePanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("2. Accretion Source") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Model", selection: $model.selectedSourceID) {
                    Section("Recommended") {
                        sourceItems(statuses: ["recommended", "production-candidate"])
                    }
                    Section("Diagnostics") {
                        sourceItems(statuses: ["diagnostic", "surrogate"])
                    }
                    Section("Legacy") {
                        sourceItems(statuses: ["legacy"])
                    }
                }
                Text(model.selectedSource.summary)
                    .font(.caption)
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

    @ViewBuilder
    private func sourceItems(statuses: Set<String>) -> some View {
        ForEach(model.sourceModels.filter { statuses.contains($0.status) }) { source in
            Text(source.title).tag(source.id)
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
            HStack {
                Text("ISO")
                Slider(value: $model.iso, in: 50...12800, step: 1)
                TextField("ISO", value: $model.iso, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
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
            HStack {
                Text("Shutter")
                TextField("1/60", text: $model.shutter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text("seconds or fraction")
                    .foregroundStyle(.secondary)
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
        HStack {
            Text(label)
            Slider(value: $index, in: 0...maxIndex, step: 1)
            Text(valueText)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
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
                .pickerStyle(.segmented)

                if model.aspect == .custom {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Width")
                            TextField("Width", value: $model.customWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Stepper("", value: $model.customWidth, in: 64...8192, step: 64)
                                .labelsHidden()
                        }
                        GridRow {
                            Text("Height")
                            TextField("Height", value: $model.customHeight, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Stepper("", value: $model.customHeight, in: 64...8192, step: 64)
                                .labelsHidden()
                        }
                    }
                }

                Picker("SSAA", selection: $model.ssaa) {
                    ForEach(RenderSampling.allCases) { sampling in
                        Text("\(sampling.title) \(sampling.detail)").tag(sampling)
                    }
                }
                .pickerStyle(.segmented)

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
                HStack {
                    ProgressView(value: model.progressFraction)
                        .frame(maxWidth: .infinity)
                    Text(model.progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .trailing)
                }
                HStack {
                    Button {
                        model.copyCommandToPasteboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
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
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!model.isRunning)
                    Button {
                        model.refreshResult()
                    } label: {
                        Label("Reload Result", systemImage: "arrow.clockwise")
                    }
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
    @ObservedObject private var stats: PreviewStats

    init(model: LauncherModel) {
        self.model = model
        self.stats = model.previewStats
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            InteractivePreviewViewport(model: model)

            if let failure = stats.failureMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Preview unavailable")
                        .font(.headline)
                    Text(failure)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            previewHUD
                .padding(12)

            VStack {
                Spacer()
                Text("Drag to orbit · Scroll or pinch to zoom")
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
        VStack(alignment: .leading, spacing: 5) {
            Text(statusLine)
                .font(.caption.weight(.semibold))
            Text("Samples \(stats.sampleCount) / \(stats.maxSamples)")
                .font(.caption2)
            ProgressView(value: progressValue)
                .frame(width: 150)
                .tint(.white)
            Text("\(stats.width)x\(stats.height) · \(Int(stats.fps.rounded())) fps")
                .font(.caption2)
        }
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.92))
        .padding(10)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }

    private var progressValue: Double {
        guard stats.maxSamples > 0 else { return 0 }
        return min(1.0, Double(stats.sampleCount) / Double(stats.maxSamples))
    }

    private var statusLine: String {
        if stats.interacting { return "Interacting · fast preview" }
        if stats.converged { return "Converged" }
        return "Accumulating…"
    }
}

private struct PreviewControlsPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("Interactive Preview Viewport") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Quality", selection: $model.previewQuality) {
                    ForEach(PreviewQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                Divider()
                cameraControls
                Toggle("Apply preview camera to final render", isOn: $model.linkPreviewCameraToRender)

                Text("The preview mirrors every setting — metric, spin, accretion source, and the observer/camera exposure, tone and grade. Quality is the only knob that trades fidelity for speed; everything else matches Final Render.")
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
    let format: String

    var body: some View {
        HStack {
            Text(label)
            Slider(value: $value, in: range)
            TextField(label, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
            NumericText(value: value, width: 64, format: format)
        }
    }
}

private struct NumericText: View {
    let value: Double
    let width: CGFloat
    let format: String

    var body: some View {
        Text(String(format: format, value))
            .monospacedDigit()
            .frame(width: width, alignment: .trailing)
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
