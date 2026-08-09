import Darwin
import Foundation

/// Owns every QEMU child started by the app. Records are persisted so a QEMU
/// orphaned by a crash or forced update can be identified on the next launch.
final class ChildProcessRegistry: @unchecked Sendable {
    struct Record: Codable, Equatable {
        let pid: pid_t
        let sessionID: String
        let executablePath: String
        let launchedAt: Date
    }

    static let shared = ChildProcessRegistry()
    private let lock = NSLock()
    private var records: [pid_t: Record] = [:]
    private var storageURL: URL?

    private init() {}

    /// Must be called only by the primary app instance, after it owns the app lock.
    func configure(storageURL: URL) {
        let decoded = (try? Data(contentsOf: storageURL))
            .flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        lock.lock()
        self.storageURL = storageURL
        records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.pid, $0) })
        lock.unlock()
    }

    @discardableResult
    func recoverOrphans() -> Int {
        let snapshot = removeRecords { _ in true }
        return snapshot.reduce(into: 0) { count, record in
            if terminate(record: record) { count += 1 }
        }
    }

    func register(_ process: Process, sessionID: String, executableURL: URL) {
        let pid = process.processIdentifier
        guard pid > 1 else { return }
        let record = Record(
            pid: pid,
            sessionID: sessionID,
            executablePath: executableURL.standardizedFileURL.path,
            launchedAt: Date()
        )
        lock.lock()
        records[pid] = record
        let snapshot = Array(records.values)
        let destination = storageURL
        lock.unlock()
        persist(snapshot, to: destination)
    }

    func unregister(_ process: Process) {
        remove(pid: process.processIdentifier)
    }

    func terminate(_ process: Process) {
        let pid = process.processIdentifier
        let record = remove(pid: pid)
        if let record {
            _ = terminate(record: record)
        } else if process.isRunning {
            process.terminate()
            waitForExit(pid: pid, timeout: 1.0)
            if Darwin.kill(pid, 0) == 0 { _ = Darwin.kill(pid, SIGKILL) }
            waitForExit(pid: pid, timeout: 0.5)
        }
    }

    /// Enforces one QEMU for one imported firmware project, including a process
    /// left behind by a previous host-app lifetime.
    func terminateSession(_ sessionID: String) {
        let snapshot = removeRecords { $0.sessionID == sessionID }
        for record in snapshot { _ = terminate(record: record) }
    }

    func terminateAll() {
        let snapshot = removeRecords { _ in true }
        for record in snapshot { _ = terminate(record: record) }
    }

    @discardableResult
    private func remove(pid: pid_t) -> Record? {
        lock.lock()
        let removed = records.removeValue(forKey: pid)
        let snapshot = Array(records.values)
        let destination = storageURL
        lock.unlock()
        persist(snapshot, to: destination)
        return removed
    }

    private func removeRecords(where predicate: (Record) -> Bool) -> [Record] {
        lock.lock()
        let removed = records.values.filter(predicate)
        for record in removed { records.removeValue(forKey: record.pid) }
        let snapshot = Array(records.values)
        let destination = storageURL
        lock.unlock()
        persist(snapshot, to: destination)
        return removed
    }

    private func persist(_ snapshot: [Record], to destination: URL?) {
        guard let destination else { return }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if snapshot.isEmpty {
                try? FileManager.default.removeItem(at: destination)
            } else {
                let data = try JSONEncoder().encode(snapshot.sorted { $0.pid < $1.pid })
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            // Lifecycle cleanup must remain best effort even if local app state is unavailable.
        }
    }

    @discardableResult
    private func terminate(record: Record) -> Bool {
        guard record.pid > 1, Darwin.kill(record.pid, 0) == 0 else { return false }
        // A PID may have been reused after a crash. Never signal it unless its
        // current command still matches the exact QEMU executable we recorded.
        guard Self.isOwnedQEMUCommand(
            currentCommand(for: record.pid), executablePath: record.executablePath
        ) else { return false }
        _ = Darwin.kill(record.pid, SIGTERM)
        waitForExit(pid: record.pid, timeout: 1.0)
        if Darwin.kill(record.pid, 0) == 0 {
            _ = Darwin.kill(record.pid, SIGKILL)
            waitForExit(pid: record.pid, timeout: 0.5)
        }
        return Darwin.kill(record.pid, 0) != 0
    }

    private func currentCommand(for pid: pid_t) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    static func isOwnedQEMUCommand(_ command: String?, executablePath: String) -> Bool {
        guard let command, !command.isEmpty else { return false }
        let executable = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        guard URL(fileURLWithPath: executable).lastPathComponent == "qemu-system-xtensa" else {
            return false
        }
        return command == executable || command.hasPrefix(executable + " ")
    }

    private func waitForExit(pid: pid_t, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, Darwin.kill(pid, 0) == 0 { usleep(10_000) }
    }
}
