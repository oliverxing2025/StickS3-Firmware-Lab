import Foundation
import SimulatorSupport

guard CommandLine.arguments.count == 3,
      let runtime = SimulatorRuntimeID(rawValue: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: FirmwareFingerprintTool <runtime> <firmware-root>\n".utf8))
    exit(64)
}

do {
    let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    print(try SimulatorSourceFingerprint.calculate(runtime: runtime, firmwareRoot: root))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(65)
}
