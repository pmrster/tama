import Foundation

enum SafeFileReader {
    static let maxLogBytes = 128 * 1024 * 1024
    static let maxMetadataBytes = 8 * 1024
    static let maxHistoryBytes = 16 * 1024 * 1024

    static func isSafeDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    static func data(at url: URL, maxBytes: Int = maxLogBytes) -> Data? {
        guard maxBytes >= 0,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= maxBytes else {
            return nil
        }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func text(at url: URL, maxBytes: Int = maxLogBytes) -> String? {
        guard let data = data(at: url, maxBytes: maxBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func forEachLineData(at url: URL, maxBytes: Int = maxLogBytes, _ body: (Data) -> Void) {
        guard let data = data(at: url, maxBytes: maxBytes), !data.isEmpty else { return }
        forEachLineData(in: data, body)
    }

    static func forEachLineData(in data: Data, _ body: (Data) -> Void) {
        var start = data.startIndex
        while start < data.endIndex {
            let newline = data[start..<data.endIndex].firstIndex(of: 10) ?? data.endIndex
            if newline > start {
                body(data[start..<newline])
            }
            start = newline == data.endIndex ? data.endIndex : data.index(after: newline)
        }
    }
}
