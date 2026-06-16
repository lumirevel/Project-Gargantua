import SwiftUI

struct GargantuaLauncherView: View {
    @StateObject private var model = LauncherModel()
    @State private var commandExpanded = false

    var body: some View {
        NavigationSplitView {
            sourceSidebar
        } detail: {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        WorkflowHeader(model: model)
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
                        CommandPanel(model: model, isExpanded: $commandExpanded)
                        ExecutionPanel(model: model)
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                }
                Divider()
                PreviewPanel(model: model)
                    .frame(width: 390)
            }
            .navigationTitle("Observation Workflow")
        }
        .frame(minWidth: 1180, minHeight: 760)
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
            Text("Matter -> Observer -> Interpreter -> Render")
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
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

private struct SourceSummaryPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("1. Physical Source") {
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
        GroupBox("2. Observer") {
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
        GroupBox("3. Human Eye Interpreter") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Photometric model", selection: $model.eyePhotometric) {
                    ForEach(EyePhotometricMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Use neutral-density safe-viewing filter", isOn: $model.useEyeND)
                if model.useEyeND {
                    LabeledSlider(label: "ND density", value: $model.eyeND, range: 0...8, format: "%.1f")
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
        GroupBox("3. Camera Interpreter") {
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

            if model.exposureProgram != .fixedEV && model.exposureProgram != .shutterPriority {
                LabeledSlider(label: "f-number", value: $model.fNumber, range: 0.7...22, format: "%.1f")
            }
            if model.exposureProgram == .manual || model.exposureProgram == .shutterPriority {
                HStack {
                    Text("Shutter")
                    TextField("1/60", text: $model.shutter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("seconds or fraction")
                        .foregroundStyle(.secondary)
                }
            }
            if model.exposureProgram != .fixedEV {
                LabeledSlider(label: "ISO", value: $model.iso, range: 50...12800, format: "%.0f")
            }
            if model.exposureProgram == .aperturePriority || model.exposureProgram == .shutterPriority || model.exposureProgram == .fixedEV {
                LabeledSlider(label: "EV", value: $model.exposureEV, range: -8...8, format: "%.1f")
            }
        }
    }

    private var cameraOptics: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledSlider(label: "Diffraction", value: $model.diffractionStrength, range: 0...0.25, format: "%.3f")
            LabeledSlider(label: "PSF blur", value: $model.psfSigma, range: 0...3, format: "%.2f")

            Picker("Photon noise", selection: $model.cameraPhotonNoise) {
                ForEach(CameraPhotonNoiseMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            LabeledSlider(label: "Photon scale", value: $model.cameraPhotonScale, range: 0.1...5.0, format: "%.2f")

            DisclosureGroup("Expert display-domain noise") {
                LabeledSlider(label: "Read noise", value: $model.readNoise, range: 0...0.1, format: "%.3f")
                LabeledSlider(label: "Shot noise", value: $model.shotNoise, range: 0...0.1, format: "%.3f")
            }
        }
    }

    private var cinematicControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Color grading / tone curve", isOn: $model.enableColorGrade)
            Toggle("Show experimental cinematic controls", isOn: $model.allowExperimentalCinematicControls)
            if model.allowExperimentalCinematicControls {
                Toggle("Cinematic flare / glare", isOn: $model.enableCinematicEffects)
                LabeledSlider(label: "Flare", value: $model.flareStrength, range: 0...1, format: "%.2f")
                    .disabled(!model.enableCinematicEffects)

                Toggle("Depth of field", isOn: $model.enableDepthOfField)
                if model.enableDepthOfField {
                    LabeledSlider(label: "Focus depth", value: $model.focusDepth, range: 1...80, format: "%.1f")
                }

                LabeledSlider(label: "Motion samples", value: $model.motionBlurSamples, range: 1...64, format: "%.0f")
                if model.motionBlurSamples > 1.5 {
                    LabeledSlider(label: "Time lapse", value: $model.motionBlurTimeLapse, range: 0.05...20, format: "%.2f")
                }
            }
        }
    }
}

private struct RenderSetupPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GroupBox("4. Render Setup") {
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
                    HStack {
                        Stepper("Width \(model.customWidth)", value: $model.customWidth, in: 64...8192, step: 64)
                        Stepper("Height \(model.customHeight)", value: $model.customHeight, in: 64...8192, step: 64)
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
                    Toggle("Kerr metric", isOn: $model.metricKerr)
                    LabeledSlider(label: "Spin", value: $model.spin, range: -0.999...0.999, format: "%.2f")
                        .disabled(!model.metricKerr)

                    Picker("Ray bundle", selection: $model.rayBundleMode) {
                        ForEach(RayBundleMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if model.rayBundleMode == .jacobian {
                        LabeledSlider(label: "Jacobian strength", value: $model.rayBundleJacobianStrength, range: 0...4, format: "%.2f")
                        LabeledSlider(label: "Footprint clamp", value: $model.rayBundleFootprintClamp, range: 0...20, format: "%.1f")
                    }
                }
                .padding(.top, 8)
            }

            Divider().padding(.vertical, 8)

            Toggle("Use custom camera/framing", isOn: $model.useCustomCamera)
            if model.useCustomCamera {
                CameraFramingControls(model: model)
            }
        }
    }
}

private struct CameraFramingControls: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CameraOrbitPreview(model: model)
                .frame(height: 150)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("camX")
                    Slider(value: $model.camX, in: -40...40)
                    NumericText(value: model.camX, width: 58, format: "%.1f")
                }
                GridRow {
                    Text("camY")
                    Slider(value: $model.camY, in: -60...(-2))
                    NumericText(value: model.camY, width: 58, format: "%.1f")
                }
                GridRow {
                    Text("camZ")
                    Slider(value: $model.camZ, in: -20...20)
                    NumericText(value: model.camZ, width: 58, format: "%.1f")
                }
                GridRow {
                    Text("FOV")
                    Slider(value: $model.fov, in: 20...120)
                    NumericText(value: model.fov, width: 58, format: "%.0f")
                }
                GridRow {
                    Text("Roll")
                    Slider(value: $model.roll, in: -180...180)
                    NumericText(value: model.roll, width: 58, format: "%.0f")
                }
            }
        }
    }
}

private struct CameraOrbitPreview: View {
    @ObservedObject var model: LauncherModel
    @State private var lastTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width * 0.50, y: size.height * 0.52)
            let radius = min(size.width, size.height) * 0.32
            let angle = atan2(model.camY, model.camX)
            let camera = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.28))
                Circle()
                    .stroke(.secondary.opacity(0.45), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                Circle()
                    .fill(.black)
                    .frame(width: 28, height: 28)
                    .position(center)
                Path { path in
                    path.move(to: camera)
                    path.addLine(to: center)
                }
                .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .position(camera)
                Text("drag to orbit / height")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: size.width * 0.5, y: size.height - 16)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastTranslation.width,
                            height: value.translation.height - lastTranslation.height
                        )
                        model.orbitCamera(deltaX: delta.width, deltaY: delta.height)
                        lastTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastTranslation = .zero
                    }
            )
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
                        model.refreshPreview()
                    } label: {
                        Label("Reload Preview", systemImage: "arrow.clockwise")
                    }
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

private struct PreviewPanel: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Button {
                    model.revealOutput()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Reveal output in Finder")
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black)
                if let image = model.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text(model.previewStatus)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.previewStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.outputPath)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Scientific source options stay in the Matter sidebar.", systemImage: "checkmark.circle")
                Label("Camera and cinematic controls are hidden for RAW audit.", systemImage: "checkmark.circle")
                Label("Advanced ray and geometry controls are explicit validation controls.", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(18)
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        HStack {
            Text(label)
            Slider(value: $value, in: range)
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
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
