import CoreGraphics
import SwiftUI

/// 直接显示 VibeStick-Codex 固件 main.c + LVGL 9.2 输出的自适应 RGB565 帧。
struct CodexFirmwareScreenView: View {
    @ObservedObject var model: SimulatorModel

    var body: some View {
        ZStack {
            Color.black
            if let image = makeImage() {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: CGFloat(model.adaptiveFrameWidth) * 2.5,
                           height: CGFloat(model.adaptiveFrameHeight) * 2.5)
                    .rotationEffect(.degrees(counterRotation))
            }
        }
        .frame(width: 337.5, height: 600)
        .clipped()
        .overlay(Rectangle().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }

    private var counterRotation: Double {
        switch model.devicePose {
        case .left90: return 90
        case .right90: return -90
        case .upright, .upsideDown: return 0
        }
    }

    private func makeImage() -> CGImage? {
        let width = model.adaptiveFrameWidth
        let height = model.adaptiveFrameHeight
        guard model.adaptiveFrameRGBA.count == width * height * 4,
              let provider = CGDataProvider(data: model.adaptiveFrameRGBA as CFData) else {
            return nil
        }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }
}
