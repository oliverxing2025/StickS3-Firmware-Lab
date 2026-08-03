import CoreGraphics
import SwiftUI

struct QEMUFrameView: View {
    @ObservedObject var model: SimulatorModel

    var body: some View {
        Group {
            if let image = makeImage() {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            } else {
                Color.black
            }
        }
        .aspectRatio(CGFloat(model.qemuFrameWidth) / CGFloat(model.qemuFrameHeight), contentMode: .fit)
        .overlay(Rectangle().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }

    private func makeImage() -> CGImage? {
        let width = model.qemuFrameWidth
        let height = model.qemuFrameHeight
        let frame = model.qemuFrameRGBA
        guard width > 0, height > 0, frame.count == width * height * 4,
              let provider = CGDataProvider(data: frame as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
