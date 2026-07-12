using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class CatStateStoreTests
{
    private string _dir = null!;

    [TestInitialize]
    public void SetUp() => _dir = Path.Combine(Path.GetTempPath(), "cat-" + Guid.NewGuid());

    [TestCleanup]
    public void TearDown() { if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true); }

    [TestMethod]
    public void Round_trips_state()
    {
        var store = new CatStateStore(_dir);
        var state = new CatState(DateTimeOffset.Parse("2026-06-19T09:00:00Z"));
        store.Save(state);
        Assert.AreEqual(state, store.Load());
    }

    [TestMethod]
    public void Missing_file_loads_initial()
    {
        Assert.AreEqual(CatState.Initial, new CatStateStore(_dir).Load());
    }

    [TestMethod]
    public void Malformed_file_loads_initial()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "cat-state.json"), "not json");
        Assert.AreEqual(CatState.Initial, new CatStateStore(_dir).Load());
    }

    [TestMethod]
    public void Save_writes_only_inside_the_injected_directory()
    {
        var outside = Path.Combine(Path.GetTempPath(), "cat-outside-" + Guid.NewGuid());
        Directory.CreateDirectory(outside);
        try
        {
            var before = Directory.GetFiles(outside);
            new CatStateStore(_dir).Save(new CatState(DateTimeOffset.UtcNow));
            CollectionAssert.AreEqual(before, Directory.GetFiles(outside));
            Assert.IsTrue(File.Exists(Path.Combine(_dir, "cat-state.json")));
        }
        finally { Directory.Delete(outside, recursive: true); }
    }
}
