import Foundation

public struct CLIOptions: Equatable, Sendable {
    public var watch: Bool = false
    public var json: Bool = false
    public var interval: TimeInterval = 7
    public var noColor: Bool = false
    public var help: Bool = false
    public var version: Bool = false
    public init() {}
}

public enum CLIError: Error, Equatable {
    case unknownFlag(String)
    case missingValue(String)
    case invalidInterval(String)
}

public extension CLIOptions {
    static let usageText = """
    tama-cli — recently-active AI agent sessions, grouped by project.

    USAGE:
      tama-cli [options]

    OPTIONS:
      -w, --watch            live in-place refresh
      -n, --interval <sec>   watch refresh interval in seconds (default 7, min 1)
          --json             machine-readable output (NDJSON stream with --watch)
          --no-color         disable ANSI color
      -h, --help             show this help
          --version          print version
    """

    static func describe(_ error: CLIError) -> String {
        switch error {
        case .unknownFlag(let f):     return "unknown option '\(f)'"
        case .missingValue(let f):    return "option '\(f)' requires a value"
        case .invalidInterval(let v): return "invalid interval '\(v)' (expected a number)"
        }
    }

    /// Parse argv with the program name already dropped.
    static func parse(_ args: [String]) -> Result<CLIOptions, CLIError> {
        var opts = CLIOptions()
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "-w", "--watch":    opts.watch = true
            case "--json":           opts.json = true
            case "--no-color":       opts.noColor = true
            case "-h", "--help":     opts.help = true
            case "--version":        opts.version = true
            case "-n", "--interval":
                guard i + 1 < args.count else { return .failure(.missingValue(a)) }
                i += 1
                guard let v = Double(args[i]) else { return .failure(.invalidInterval(args[i])) }
                opts.interval = max(1, v)
            default:
                return .failure(.unknownFlag(a))
            }
            i += 1
        }
        return .success(opts)
    }
}
