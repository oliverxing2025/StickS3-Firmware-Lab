import AppKit
import SwiftUI

struct SplashScreenView: View {
    @AppStorage("simulator.lightBackground") private var lightBackground = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: lightBackground
                    ? [Color(rgb: 0xF3F4F6), Color(rgb: 0xD9DCE2)]
                    : [Color(rgb: 0x34363B), Color(rgb: 0x171B24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                avatar

                VStack(spacing: 6) {
                    Text("小奥科技")
                        .font(.system(size: 30, weight: .bold))
                    Text("XiaoAo Technology")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                }
                .frame(width: avatarSize, alignment: .center)
                .multilineTextAlignment(.center)
                .offset(x: 8, y: -10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -28)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("小奥科技正在启动")
    }

    private var avatar: some View {
        avatarImage
        .frame(width: avatarSize, height: avatarSize)
        .shadow(color: .black.opacity(lightBackground ? 0.12 : 0.38), radius: 22, y: 10)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let image = splashImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: avatarSize, height: avatarSize)
        } else {
            Image(systemName: "desktopcomputer")
                .resizable()
                .scaledToFit()
                .padding(88)
                .foregroundStyle(Color(rgb: 0x267BFF))
                .frame(width: avatarSize, height: avatarSize)
        }
    }

    private var avatarSize: CGFloat { 330 }

    private var splashImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "SplashAvatar", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
