using System.Text;
using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class SafeFileReaderTests
{
    private string _root = null!;

    [TestInitialize]
    public void SetUp()
    {
        _root = Path.Combine(Path.GetTempPath(), "sfr-" + Guid.NewGuid());
        Directory.CreateDirectory(_root);
    }

    [TestCleanup]
    public void TearDown() => Directory.Delete(_root, recursive: true);

    private string WriteFile(string name, string content)
    {
        var p = Path.Combine(_root, name);
        File.WriteAllText(p, content);
        return p;
    }

    [TestMethod]
    public void ReadData_returns_contents_of_a_regular_file()
    {
        var p = WriteFile("a.txt", "hello");
        CollectionAssert.AreEqual(Encoding.UTF8.GetBytes("hello"), SafeFileReader.ReadData(p));
    }

    [TestMethod]
    public void ReadData_rejects_files_over_the_cap()
    {
        var p = WriteFile("big.txt", new string('x', 100));
        Assert.IsNull(SafeFileReader.ReadData(p, maxBytes: 99));
        Assert.IsNotNull(SafeFileReader.ReadData(p, maxBytes: 100));
    }

    [TestMethod]
    public void ReadData_returns_null_for_missing_file()
    {
        Assert.IsNull(SafeFileReader.ReadData(Path.Combine(_root, "nope.txt")));
    }

    [TestMethod]
    public void ReadData_rejects_symlinks()
    {
        var target = WriteFile("target.txt", "secret");
        var link = Path.Combine(_root, "link.txt");
        File.CreateSymbolicLink(link, target);
        Assert.IsNull(SafeFileReader.ReadData(link));
    }

    [TestMethod]
    public void IsSafeDirectory_accepts_real_dir_rejects_symlinked_dir_and_files()
    {
        var real = Path.Combine(_root, "real");
        Directory.CreateDirectory(real);
        var link = Path.Combine(_root, "dirlink");
        Directory.CreateSymbolicLink(link, real);
        var file = WriteFile("f.txt", "x");
        Assert.IsTrue(SafeFileReader.IsSafeDirectory(real));
        Assert.IsFalse(SafeFileReader.IsSafeDirectory(link));
        Assert.IsFalse(SafeFileReader.IsSafeDirectory(file));
        Assert.IsFalse(SafeFileReader.IsSafeDirectory(Path.Combine(_root, "missing")));
    }

    [TestMethod]
    public void Tail_returns_last_maxBytes()
    {
        var p = WriteFile("t.txt", "hello world");
        CollectionAssert.AreEqual(Encoding.UTF8.GetBytes("world"), SafeFileReader.Tail(p, maxBytes: 5));
        CollectionAssert.AreEqual(Encoding.UTF8.GetBytes("hello world"), SafeFileReader.Tail(p, maxBytes: 999));
    }

    [TestMethod]
    public void ForEachLine_skips_empty_lines_and_handles_missing_trailing_newline()
    {
        var lines = new List<string>();
        SafeFileReader.ForEachLine(Encoding.UTF8.GetBytes("a\n\nbb\nccc"),
            m => lines.Add(Encoding.UTF8.GetString(m.Span)));
        CollectionAssert.AreEqual(new[] { "a", "bb", "ccc" }, lines);
    }

    [TestMethod]
    public void ReadData_does_not_block_a_concurrent_writer()
    {
        var p = WriteFile("live.log", "line1\n");
        using var writer = new FileStream(p, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
        Assert.IsNotNull(SafeFileReader.ReadData(p)); // must not throw a sharing violation
    }

    [TestMethod]
    public void Malformed_paths_return_false_or_null_never_throw()
    {
        Assert.IsFalse(SafeFileReader.IsSafeDirectory("\0"));
        Assert.IsNull(SafeFileReader.ReadData("\0"));
        Assert.IsNull(SafeFileReader.Tail("\0"));
    }
}
