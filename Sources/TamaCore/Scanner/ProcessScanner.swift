import Foundation
import Darwin

public protocol ProcessScanning: Sendable {
    func scan() -> [ProcInfo]
}

/// A cheap, targeted presence query: returns full info only for processes named `ollama`.
/// Separate from `scan()` so callers needing only Ollama presence avoid the ~600ms cost of
/// reading argv for every process on the system on each poll.
public protocol OllamaPresenceScanning: Sendable {
    func ollamaProcesses() -> [ProcInfo]
}

/// Enumerates same-user processes via sysctl (read-only kernel query). Never spawns or writes.
public struct SysctlProcessScanner: ProcessScanning, OllamaPresenceScanning {
    public init() {}
    private static let argMax = readArgMax()

    public func scan() -> [ProcInfo] {
        kinfoProcs().compactMap { procInfo($0) }
    }

    /// Only the `ollama` processes, with argv read for those few alone (the comm filter comes from
    /// the single bulk sysctl, so the expensive per-process argv read runs ~1-3 times, not ~900).
    public func ollamaProcesses() -> [ProcInfo] {
        kinfoProcs().compactMap { info in
            commName(info) == "ollama" ? procInfo(info) : nil
        }
    }

    private func procInfo(_ info: kinfo_proc) -> ProcInfo? {
        let pid = info.kp_proc.p_pid
        guard pid > 0 else { return nil }
        let hasTTY = info.kp_eproc.e_tdev != -1   // -1 == NODEV, no controlling terminal
        return ProcInfo(pid: pid, ppid: info.kp_eproc.e_ppid,
                        execPath: processPath(pid: pid),
                        argv: processArgs(pid: pid),
                        cwd: nil, hasTTY: hasTTY, commName: commName(info))
    }

    private func commName(_ info: kinfo_proc) -> String {
        var comm = info.kp_proc.p_comm
        return withUnsafePointer(to: &comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
    }

    private func kinfoProcs() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        if sysctl(&mib, 4, nil, &size, nil, 0) != 0 || size == 0 { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        var newSize = size
        let r = procs.withUnsafeMutableBytes { ptr in
            sysctl(&mib, 4, ptr.baseAddress, &newSize, nil, 0)
        }
        if r != 0 { return [] }
        return Array(procs.prefix(newSize / MemoryLayout<kinfo_proc>.stride))
    }

    private func processPath(pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return buf.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return String(validatingCString: base)
        }
    }

    private func processArgs(pid: Int32) -> [String] {
        var buffer = [CChar](repeating: 0, count: Self.argMax)
        var size = Self.argMax
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        let r = buffer.withUnsafeMutableBytes { ptr in
            sysctl(&mib, 3, ptr.baseAddress, &size, nil, 0)
        }
        if r != 0 { return [] }
        return parseProcArgs(buffer, size: size)
    }

    private static func readArgMax() -> Int {
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        if sysctl(&mib, 2, &argMax, &size, nil, 0) != 0 || argMax <= 0 {
            return 1 << 18
        }
        return Int(argMax)
    }

    /// KERN_PROCARGS2 layout: [Int32 argc][exec path\0][padding\0...][arg0\0][arg1\0]...
    private func parseProcArgs(_ buffer: [CChar], size: Int) -> [String] {
        guard size > MemoryLayout<Int32>.size else { return [] }
        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        guard argc > 0 else { return [] }

        var args: [String] = []
        var index = MemoryLayout<Int32>.size

        while index < size && buffer[index] != 0 { index += 1 }       // skip exec path
        while index < size && buffer[index] == 0 { index += 1 }       // skip padding nulls

        var collected: Int32 = 0
        while collected < argc && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            if index > start {
                let bytes = buffer[start..<index].map { UInt8(bitPattern: $0) }
                if let s = String(bytes: bytes, encoding: .utf8) { args.append(s) }
            }
            while index < size && buffer[index] == 0 { index += 1 }
            collected += 1
        }
        return args
    }
}
