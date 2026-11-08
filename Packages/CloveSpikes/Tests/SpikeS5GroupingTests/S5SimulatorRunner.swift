// A tiny, unsigned simulator measurement app, compiled only with
// -D S5_SIMULATOR_RUNNER. See the S5 report for the reproducible commands.
#if S5_SIMULATOR_RUNNER && targetEnvironment(simulator)
    import Foundation
    import SpikeS5Grouping
    import UIKit

    @main
    final class S5SimulatorRunner: UIResponder, UIApplicationDelegate {
        var window: UIWindow?

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? =
                nil
        ) -> Bool {
            let window = UIWindow(frame: UIScreen.main.bounds)
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            window.rootViewController = controller
            window.makeKeyAndVisible()
            self.window = window
            Task.detached(priority: .utility) {
                do {
                    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                    let run = try await GroupingSuite.run(
                        folder: folder, includeSyntheticFixtures: true)
                    let documents = try FileManager.default.url(
                        for: .documentDirectory, in: .userDomainMask,
                        appropriateFor: nil, create: true)
                    try run.labeledReport().write(
                        to: documents.appendingPathComponent("simulator.json"))
                    print("S5 simulator: report saved")
                } catch {
                    print("S5 simulator failed: \(error)")
                }
            }
            return true
        }
    }
#endif
