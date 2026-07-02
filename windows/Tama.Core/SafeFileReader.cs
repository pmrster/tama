namespace Tama.Core;

/// <summary>
/// All log access goes through here. Logs are untrusted, agent-owned input: open strictly
/// read-only with a share mode that never blocks the writing agent; reject non-regular
/// files and reparse points (symlinks/junctions) on files AND directories; cap sizes;
/// return null instead of throwing. Mirrors the Swift SafeFileReader (spec/log-formats.md).
/// </summary>
public static class SafeFileReader
{
    public const long MaxLogBytes = 128L * 1024 * 1024;
    public const long MaxMetadataBytes = 8 * 1024;
    public const long MaxHistoryBytes = 16L * 1024 * 1024;

    public static bool IsSafeDirectory(string path)
    {
        var info = new DirectoryInfo(path);
        return info.Exists && !info.Attributes.HasFlag(FileAttributes.ReparsePoint);
    }

    public static byte[]? ReadData(string path, long maxBytes = MaxLogBytes)
    {
        try
        {
            var size = SafeRegularFileSize(path);
            if (size is null || size > maxBytes || maxBytes < 0) return null;
            using var stream = OpenShared(path);
            return ReadUpTo(stream, (int)size.Value);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>Last maxBytes of the file (whole file if smaller) — tail of a big append-only log.</summary>
    public static byte[]? Tail(string path, long maxBytes = MaxLogBytes)
    {
        try
        {
            var size = SafeRegularFileSize(path);
            if (size is null || maxBytes < 0) return null;
            using var stream = OpenShared(path);
            var readLength = (int)Math.Min(size.Value, maxBytes);
            stream.Seek(size.Value - readLength, SeekOrigin.Begin);
            return ReadUpTo(stream, readLength);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    public static void ForEachLine(string path, Action<ReadOnlyMemory<byte>> body, long maxBytes = MaxLogBytes)
    {
        var data = ReadData(path, maxBytes);
        if (data is { Length: > 0 }) ForEachLine(data, body);
    }

    public static void ForEachLine(byte[] data, Action<ReadOnlyMemory<byte>> body)
    {
        var memory = data.AsMemory();
        var start = 0;
        while (start < memory.Length)
        {
            var nl = data.AsSpan(start).IndexOf((byte)'\n');
            var end = nl < 0 ? memory.Length : start + nl;
            if (end > start) body(memory[start..end]);
            start = end + 1;
        }
    }

    private static long? SafeRegularFileSize(string path)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Attributes.HasFlag(FileAttributes.ReparsePoint)) return null;
        return info.Length;
    }

    private static FileStream OpenShared(string path) =>
        new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);

    private static byte[] ReadUpTo(FileStream stream, int length)
    {
        var buffer = new byte[length];
        var read = stream.ReadAtLeast(buffer, length, throwOnEndOfStream: false);
        return read == length ? buffer : buffer[..read];
    }
}
