import Foundation
import SimulatorSupport

/// Keeps high-volume serial framing off SwiftUI's main actor. A dedicated
/// serial queue preserves byte order while launch generations discard output
/// that belonged to a previous QEMU session.
final class QEMUOutputDecoder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cn.vibestick.firmware-lab.qemu-output",
                                      qos: .userInitiated)
    private var parser = StickS3VirtualBoardStreamParser()
    private var generation: UInt64 = 0

    func reset() -> UInt64 {
        queue.sync {
            generation &+= 1
            parser = StickS3VirtualBoardStreamParser()
            return generation
        }
    }

    func submit(
        _ data: Data,
        generation expectedGeneration: UInt64,
        deliver: @escaping @MainActor @Sendable ([StickS3VirtualBoardEvent], UInt64) -> Void
    ) {
        queue.async { [self] in
            guard generation == expectedGeneration else { return }
            let events = parser.append(data)
            guard !events.isEmpty else { return }
            Task { @MainActor in deliver(events, expectedGeneration) }
        }
    }
}
