import Foundation

struct RegressionRunner {
    static func parseValue(after flag: String, in args: [String], default defaultValue: String = "") -> String {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return defaultValue }
        return args[idx + 1]
    }

    static func has(_ flag: String, in args: [String]) -> Bool {
        args.contains(flag)
    }

    static func shouldRun(in args: [String]) -> Bool {
        has("--regression-run", in: args)
    }

    static func run(arguments args: [String]) throws {
        let manifest = parseValue(after: "--regression-run", in: args, default: "tests/baseline/manifest.json")
        let outDir = parseValue(after: "--regression-out", in: args, default: "/tmp/bh_regression")
        let oneCase = parseValue(after: "--regression-case", in: args, default: "all")

        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let verifyScript = repoRoot.appendingPathComponent("scripts/baseline_verify.py").path
        let jsonOut = URL(fileURLWithPath: outDir).appendingPathComponent("verify_report.json").path
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        var procArgs = [
            verifyScript,
            "--manifest", manifest,
            "--json-out", jsonOut,
        ]
        if oneCase != "all" {
            procArgs += ["--case", oneCase]
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = procArgs
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(
                domain: "Blackhole.Regression",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "regression verify failed (status=\(proc.terminationStatus))"]
            )
        }
        print("regression verify passed -> \(jsonOut)")
    }
}
