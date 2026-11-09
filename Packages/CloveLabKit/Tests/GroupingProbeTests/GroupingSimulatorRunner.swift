// A tiny, unsigned simulator measurement app, compiled only with
// -D GROUPING_SIMULATOR_RUNNER. See the Grouping report for the reproducible commands.
#if GROUPING_SIMULATOR_RUNNER && targetEnvironment(simulator)
    import Foundation
    import GroupingProbe
    import SwiftUI

    @main
    struct GroupingSimulatorRunner: App {
        var body: some Scene {
            WindowGroup {
                Text("Grouping simulator measurement")
                    .task {
                        let documents = FileManager.default.urls(
                            for: .documentDirectory, in: .userDomainMask)[0]
                        try? Data("starting".utf8).write(
                            to: documents.appendingPathComponent("progress.txt"))
                        let worker = Task.detached(priority: .utility) {
                            let folder = URL(
                                fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                            return try await GroupingSuite.run(
                                folder: folder, includeSyntheticFixtures: true
                            ) { done, total in
                                try? Data("\(done)/\(total)".utf8).write(
                                    to: documents.appendingPathComponent("progress.txt"))
                            }
                        }
                        do {
                            let run = try await worker.value
                            try run.labeledReport().write(
                                to: documents.appendingPathComponent("simulator.json"))
                            print("Grouping simulator: report saved")
                        } catch {
                            try? Data(String(describing: error).utf8).write(
                                to: documents.appendingPathComponent("failure.txt"))
                            print("Grouping simulator failed: \(error)")
                        }
                    }
            }
        }
    }
#endif
