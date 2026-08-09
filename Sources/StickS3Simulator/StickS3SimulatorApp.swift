import AppKit
import Darwin
import SwiftUI

@main
struct StickS3SimulatorApp: App {
    @NSApplicationDelegateAdaptor(SingleInstanceAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("StickS3 Firmware Lab", id: "main") {
            SimulatorRootView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

private final class SingleInstanceAppDelegate: NSObject, NSApplicationDelegate {
    private var lockFileDescriptor: Int32 = -1

    func applicationWillFinishLaunching(_ notification: Notification) {
        let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("Stick S3 Firmware Simulator", isDirectory: true)

        guard let supportRoot else { return }
        try? FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        let lockURL = supportRoot.appendingPathComponent("virtual-device.instance.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        guard descriptor >= 0 else { return }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            activateExistingInstance()
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return
        }
        lockFileDescriptor = descriptor
        ChildProcessRegistry.shared.configure(
            storageURL: supportRoot.appendingPathComponent("qemu-processes.json")
        )
        _ = ChildProcessRegistry.shared.recoverOrphans()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ChildProcessRegistry.shared.terminateAll()
        guard lockFileDescriptor >= 0 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        Darwin.close(lockFileDescriptor)
        lockFileDescriptor = -1
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID })?
            .activate(options: [.activateAllWindows])
    }
}

private struct SimulatorRootView: View {
    @State private var showsSplash = true

    var body: some View {
        ZStack {
            // 主界面在启动页背后完成初始化，避免 3 秒后窗口尺寸跳变。
            ContentView()
                .opacity(showsSplash ? 0 : 1)
                .allowsHitTesting(!showsSplash)

            if showsSplash {
                SplashScreenView()
                    .transition(.opacity.combined(with: .scale(scale: 1.025)))
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.42)) {
                showsSplash = false
            }
        }
    }
}
