import Foundation

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

enum RenderSampling: String, CaseIterable, Identifiable {
    case one = "1"
    case two = "2"
    case four = "4"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: return "1x"
        case .two: return "2x"
        case .four: return "4x"
        }
    }

    var detail: String {
        switch self {
        case .one: return "fast"
        case .two: return "balanced"
        case .four: return "clean"
        }
    }
}

enum RayBundleMode: String, CaseIterable, Identifiable {
    case off
    case on
    case jacobian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .on: return "Bundle"
        case .jacobian: return "Jacobian"
        }
    }
}

enum OutputAspect: String, CaseIterable, Identifiable {
    case hd
    case square
    case small
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hd: return "1536 x 864"
        case .square: return "1024 x 1024"
        case .small: return "768 x 432"
        case .custom: return "Custom"
        }
    }

    func size(customWidth: Int, customHeight: Int) -> (width: Int, height: Int) {
        switch self {
        case .hd: return (1536, 864)
        case .square: return (1024, 1024)
        case .small: return (768, 432)
        case .custom:
            return (max(64, customWidth), max(64, customHeight))
        }
    }
}

enum CameraExposureProgram: String, CaseIterable, Identifiable {
    case manual
    case auto
    case aperturePriority
    case shutterPriority
    case fixedEV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "M"
        case .auto: return "Auto"
        case .aperturePriority: return "Av"
        case .shutterPriority: return "Tv"
        case .fixedEV: return "EV"
        }
    }

    var summary: String {
        switch self {
        case .manual: return "Manual photographic exposure: aperture, shutter, and ISO are explicit."
        case .auto: return "Automatic exposure with camera optics still visible for focus and diffraction."
        case .aperturePriority: return "Aperture-led workflow: f-number stays explicit, exposure uses auto plus EV compensation."
        case .shutterPriority: return "Shutter-led workflow: shutter/ISO stay explicit, exposure uses auto plus EV compensation."
        case .fixedEV: return "Fixed exposure value audit path for repeatable brightness comparisons."
        }
    }
}

enum EyePhotometricMode: String, CaseIterable, Identifiable {
    case auto
    case on
    case off

    var id: String { rawValue }
}

enum CameraPhotonNoiseMode: String, CaseIterable, Identifiable {
    case auto
    case on
    case off

    var id: String { rawValue }
}
