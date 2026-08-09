import Foundation
import SimulatorSupport

struct QEMUFrameGate {
    private(set) var lastSequence: UInt32?
    private var lastPixels: Data?

    mutating func accept(_ frame: StickS3VirtualBoardFrame) -> Bool {
        guard frame.sequence != lastSequence else { return false }
        lastSequence = frame.sequence
        guard frame.rgb565 != lastPixels else { return false }
        lastPixels = frame.rgb565
        return true
    }

    mutating func reset() {
        lastSequence = nil
        lastPixels = nil
    }
}
