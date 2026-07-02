using System.Security.Cryptography;
using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class SafetyNoWriteTests
{
    private sealed record Snapshot(string Path, long Length, DateTime LastWriteUtc, string Sha256);

    private static List<Snapshot> Snap(string root) =>
        Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .OrderBy(p => p, StringComparer.Ordinal)
            .Select(p =>
            {
                var info = new FileInfo(p);
                using var stream = File.OpenRead(p);
                return new Snapshot(p, info.Length, info.LastWriteTimeUtc,
                    Convert.ToHexString(SHA256.HashData(stream)));
            })
            .ToList();

    [TestMethod]
    public void Readers_never_modify_the_fixture_tree()
    {
        var fixtures = FixtureLocator.FixturesDir();
        var before = Snap(fixtures);

        // Exercise every read path that exists so far (extend per new reader — same rule as mac).
        foreach (var file in Directory.EnumerateFiles(fixtures, "*", SearchOption.AllDirectories))
        {
            SafeFileReader.ReadData(file);
            SafeFileReader.Tail(file, maxBytes: 64);
        }
        ClaudeSessionReader.ParseFile(
            Path.Combine(fixtures, "claude", "-Example-Code-myapp", "aabbccdd.jsonl"));

        CollectionAssert.AreEqual(before, Snap(fixtures));
    }
}
