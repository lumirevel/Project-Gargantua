import Foundation

do {
    try AppMain.run(arguments: CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(3)
}
