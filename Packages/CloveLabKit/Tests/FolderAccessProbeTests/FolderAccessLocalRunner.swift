#if CLOVE_S1_LOCAL_RUNNER
    import Foundation
    import SpikeS1Access
    import SpikeSupport

    /// Compile separately with -D CLOVE_S1_LOCAL_RUNNER for macOS or iOS Simulator.
    /// No document picker / sandbox entitlement claim can be made from this CLI process.
    @main
    struct S1LocalRunner {
        static func main() async throws {
            let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "clove-s1-local-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let folder = root.appendingPathComponent("picked")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("sentinel".utf8).write(to: folder.appendingPathComponent("keep.txt"))
            let store = root.appendingPathComponent("application-support/recents.json")
            let experiment = AccessExperiment(storeURL: store)
            _ = await experiment.load()
            let picked = await experiment.pick(folder, media: .local)
            let record = picked.recents[0]
            _ = await experiment.probe(
                write: true, scenario: "local CLI baseline; no picker/sandbox; shared loaded host")
            _ = await experiment.reopen(record.id)
            // A new actor reads the actual persisted store; this is not a force-quit/reboot test.
            let second = AccessExperiment(storeURL: store)
            let reloaded = await second.load()
            _ = await experiment.record(
                AccessEvent(.storage, "Independent store reload: \(reloaded.recents.count) records")
            )
            let moved = root.appendingPathComponent("renamed")
            try FileManager.default.moveItem(at: folder, to: moved)
            _ = await experiment.reopen(record.id)
            _ = await experiment.probe(write: false, scenario: "renamed/moved folder")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: moved.path)
            _ = await experiment.probe(
                write: true, scenario: "chmod 000 simulation; not iOS picker permission revocation")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: moved.path)
            _ = await experiment.startWatch()
            _ = await experiment.markDisconnect()
            try FileManager.default.removeItem(at: moved)
            try await Task.sleep(for: .milliseconds(500))
            _ = await experiment.poll()
            await experiment.stopWatch()
            _ = await experiment.reopen(record.id)
            // Recreate exactly the old path: detect whether the bookmark falls back to a new directory.
            try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
            _ = await experiment.reopen(record.id)
            _ = await experiment.probe(
                write: false, scenario: "deleted original; recreated old path (identity experiment)"
            )
            do {
                _ = try AccessBookmark.resolve(Data("invalid".utf8))
            } catch {
                _ = await experiment.record(
                    AccessEvent(.bookmarkResolve, "Intentionally corrupt bookmark", error: error))
            }
            var report = await experiment.snapshot().report
            report.context["harness"] = "local CLI; no document picker grant; no physical media"
            report.context["hostLoad"] = "shared loaded host; other spike workers running"
            let timestamp = ISO8601DateFormatter()
            timestamp.timeZone = TimeZone(secondsFromGMT: 0)
            timestamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
            let output = outputDirectory.appendingPathComponent(
                "clove-lab-S1-\(timestamp.string(from: report.createdAt)).json")
            try report.write(to: output)
            print("S1 local report: \(output.path)")
        }
    }
#endif
