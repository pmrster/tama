import Foundation
import TamaCore
#if canImport(Darwin)
import Darwin
#endif

let cliVersion = "0.1.0"

@main
struct TamaCLIMain {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        let options: CLIOptions
        switch CLIOptions.parse(args) {
        case .success(let o):
            options = o
        case .failure(let error):
            FileHandle.standardError.write(Data("tama-cli: \(CLIOptions.describe(error))\n\n".utf8))
            FileHandle.standardError.write(Data((CLIOptions.usageText + "\n").utf8))
            exit(2)
        }

        if options.help { print(CLIOptions.usageText); exit(0) }
        if options.version { print("tama-cli \(cliVersion)"); exit(0) }

        let monitor = AgentMonitor(reader: ActiveSessionsReader(now: { Date() }),
                                   runsInBackground: false,
                                   estimator: CostEstimator())

        let useColor = options.noColor ? false : (isatty(fileno(stdout)) != 0)

        func snapshot() -> CLIReport {
            monitor.refresh()   // runsInBackground:false → scans + prices inline, synchronously
            return CLIReportBuilder.build(state: monitor.state,
                                          cost: { monitor.cost($0) },
                                          isActive: { monitor.isActive($0) },
                                          now: monitor.state.lastUpdated)
        }

        if options.watch {
            while true {
                let report = snapshot()
                if options.json {
                    print(report.jsonLine())
                } else {
                    print("\u{1B}[2J\u{1B}[H", terminator: "")   // clear screen, cursor home
                    print(TableRenderer.render(report, color: useColor), terminator: "")
                }
                Thread.sleep(forTimeInterval: options.interval)
            }
        } else {
            let report = snapshot()
            print(options.json ? report.jsonString() : TableRenderer.render(report, color: useColor), terminator: "")
        }
    }
}
