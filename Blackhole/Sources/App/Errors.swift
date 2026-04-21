import Foundation

func fail(_ message: String, code: Int32 = 3) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(code)
}
