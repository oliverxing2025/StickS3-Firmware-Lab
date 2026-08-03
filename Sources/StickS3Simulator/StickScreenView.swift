import CoreGraphics
import SwiftUI

/// 直接显示真机 GameRenderer.cpp 生成的 135×240 RGB565 帧缓冲。
/// 此处不再用 SwiftUI 重画游戏元素，以保证与固件像素一致。
struct StickScreenView: View {
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
        .aspectRatio(135.0 / 240.0, contentMode: .fit)
        .overlay(Rectangle().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }

    private func makeImage() -> CGImage? {
        let width = Int(SimulatorModel.screenWidth)
        let height = Int(SimulatorModel.screenHeight)
        let frame = model.currentPortraitFrameRGBA
        guard frame.count == width * height * 4,
              let provider = CGDataProvider(data: frame as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255)
    }
}
