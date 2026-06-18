import AppKit
import Foundation

/// A run_pipeline.sh invocation (built on the main actor) that the server runs
/// off-actor to obtain the translated binary argv. All value types -> Sendable.
struct PreviewPipelineInvocation: Sendable {
    let executable: String
    let arguments: [String]
    let currentDirectory: String
    let environment: [String: String]
}

/// Manages a persistent "warm" `Blackhole --serve` process so the interactive
/// preview reuses the same renderer as the final output without paying the
/// pipeline/atlas setup cost on every frame.
///
/// Lifecycle: `configure(token:…)` (re)launches the process whenever a setup
/// option (source, resolution, metric, exposure, …) changes; `render(camera:)`
/// streams a new camera to the running process. Camera updates coalesce — only
/// the most recent pose is rendered when the renderer frees up.
@MainActor
final class PreviewServer {
    /// Called on the main actor with each freshly rendered frame.
    var onFrame: ((NSImage) -> Void)?
    /// Called with short status strings for the HUD.
    var onStatus: ((Bool, String) -> Void)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var token = ""
    private var imageOut = ""
    private var ready = false
    private var launching = false
    private var launchGeneration = 0

    private var latestCamera: String?     // most recent requested pose
    private var sentCamera: String?       // pose currently being rendered
    private var seq = 0
    private var lineBuffer = ""
    private var firstFrameDeadline = Date.distantFuture

    /// PATH the launcher uses for child processes.
    private static let pathValue: String = {
        let base = ProcessInfo.processInfo.environment["PATH"]
        return [base, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                "/usr/sbin", "/sbin", "/Applications/Xcode.app/Contents/Developer/usr/bin"]
            .compactMap { $0 }.joined(separator: ":")
    }()

    /// (Re)launch the serve process for the given setup token. `commandProvider`
    /// runs off the main actor and returns the fully translated binary argv (via
    /// run_pipeline.sh BH_PRINT_CMD); `imageOut` is where each frame is written.
    func configure(token newToken: String,
                   imageOut: String,
                   commandProvider: @escaping @Sendable () -> [String]?) {
        // Same setup already running or being launched -> reuse it.
        if newToken == token && (process != nil || launching) { return }
        token = newToken
        self.imageOut = imageOut
        relaunch(commandProvider: commandProvider)
    }

    /// Request a render of this camera pose ("camX camY camZ fov roll").
    func render(camera: String) {
        latestCamera = camera
        pumpIfIdle()
    }

    func shutdown() {
        launchGeneration += 1
        launching = false
        if let stdinHandle {
            try? stdinHandle.write(contentsOf: Data("quit\n".utf8))
        }
        process?.terminate()
        process = nil
        stdinHandle = nil
        ready = false
    }

    // MARK: - Launch

    private func relaunch(commandProvider: @escaping @Sendable () -> [String]?) {
        shutdown()
        launching = true
        launchGeneration += 1
        let generation = launchGeneration
        onStatus?(true, "Starting renderer…")

        DispatchQueue.global(qos: .userInitiated).async {
            let command = commandProvider()
            DispatchQueue.main.async {
                guard generation == self.launchGeneration else { return }
                self.launching = false
                guard let command, command.count >= 2 else {
                    self.onStatus?(false, "Renderer not built — run a Final Render once.")
                    return
                }
                self.startProcess(command: command, generation: generation)
            }
        }
    }

    private func startProcess(command: [String], generation: Int) {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst()) + ["--serve"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.pathValue
        env["BH_COLLISIONS_OUT"] = "/private/tmp/gargantua_gui_serve_collisions.bin"
        env["BH_ETA_RELAY"] = "none"
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let readHandle = stdoutPipe.fileHandleForReading
        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard generation == self.launchGeneration else { return }
                self.ingest(text)
            }
        }
        process.terminationHandler = { _ in
            readHandle.readabilityHandler = nil
        }

        do {
            try process.run()
            self.process = process
            self.stdinHandle = stdinPipe.fileHandleForWriting
            self.ready = false
            self.lineBuffer = ""
            self.firstFrameDeadline = Date().addingTimeInterval(45)
            onStatus?(true, "Warming up…")
        } catch {
            onStatus?(false, "Failed to start renderer: \(error.localizedDescription)")
        }
    }

    // MARK: - Protocol

    private func ingest(_ text: String) {
        lineBuffer += text
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<nl])
            lineBuffer.removeSubrange(...nl)
            handleLine(line.trimmingCharacters(in: .whitespaces))
        }
    }

    private func handleLine(_ line: String) {
        if line == "SERVE_READY" {
            ready = true
            onStatus?(true, "Renderer ready")
            pumpIfIdle()
        } else if line.hasPrefix("SERVE_FRAME") {
            loadFrame()
            sentCamera = nil // free to render the next pose
            pumpIfIdle()
        } else if line.hasPrefix("SERVE_ERROR") {
            sentCamera = nil
            onStatus?(false, "Renderer error")
            pumpIfIdle()
        }
    }

    private func pumpIfIdle() {
        guard ready, process != nil, sentCamera == nil,
              let camera = latestCamera, camera != sentCamera else { return }
        // Render only the newest pose; intermediate ones are skipped.
        latestCamera = nil
        sentCamera = camera
        seq += 1
        stdinHandle?.write(Data("\(camera) \(seq)\n".utf8))
        onStatus?(true, "Rendering…")
    }

    private func loadFrame() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: imageOut)),
              let image = NSImage(data: data) else { return }
        onFrame?(image)
        onStatus?(false, "Live")
    }
}
