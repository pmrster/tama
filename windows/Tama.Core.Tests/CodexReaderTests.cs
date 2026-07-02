using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class CodexReaderTests
{
    private string _root = null!;

    [TestInitialize]
    public void SetUp()
    {
        _root = Path.Combine(Path.GetTempPath(), "codex-" + Guid.NewGuid());
        Directory.CreateDirectory(_root);
    }

    [TestCleanup]
    public void TearDown() => Directory.Delete(_root, recursive: true);

    private string WriteLog(params string[] lines)
    {
        var p = Path.Combine(_root, "rollout-2026-06-19T08-00-00-019eddab-x.jsonl");
        File.WriteAllText(p, string.Join("\n", lines));
        return p;
    }

    private const string Meta =
        "{\"timestamp\":\"2026-06-19T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"019eddab-ffff-4000-8000-000000000000\",\"cwd\":\"/Example/Code/widget\"}}";

    private const string TokenCount =
        "{\"timestamp\":\"2026-06-19T08:05:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":15586,\"cached_input_tokens\":4992,\"output_tokens\":330},\"last_token_usage\":{\"input_tokens\":8000,\"output_tokens\":120},\"model_context_window\":272000}}}";

    [TestMethod]
    public void Last_token_count_wins_and_splits_cached_from_input()
    {
        var earlier =
            "{\"timestamp\":\"2026-06-19T08:02:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":10,\"cached_input_tokens\":1,\"output_tokens\":2},\"last_token_usage\":{\"input_tokens\":5,\"output_tokens\":1},\"model_context_window\":100000}}}";
        var p = WriteLog(Meta, earlier, TokenCount);
        var parsed = CodexReader.ParseFile(p)!;
        Assert.AreEqual(15586 - 4992, parsed.Cumulative.Input);   // cached split out of input
        Assert.AreEqual(330, parsed.Cumulative.Output);
        Assert.AreEqual(4992, parsed.Cumulative.CacheRead);
        Assert.AreEqual(0, parsed.Cumulative.CacheWrite);
        Assert.AreEqual(15916, parsed.Cumulative.Total);
        Assert.AreEqual(8120, parsed.ContextTokens);              // last_token_usage in+out
        Assert.AreEqual(272000, parsed.ContextWindow);
    }

    [TestMethod]
    public void Folder_and_session_from_session_meta_model_from_turn_context()
    {
        var turnCtx =
            "{\"timestamp\":\"2026-06-19T08:01:00.000Z\",\"type\":\"turn_context\",\"payload\":{\"cwd\":\"/Example/Code/widget\",\"model\":\"gpt-5-codex\"}}";
        var p = WriteLog(Meta, turnCtx, TokenCount);
        var parsed = CodexReader.ParseFile(p)!;
        Assert.AreEqual("/Example/Code/widget", parsed.Folder);
        Assert.AreEqual("019eddab", parsed.SessionId);
        Assert.AreEqual("gpt-5-codex", parsed.Model);
    }

    [TestMethod]
    public void Messages_count_user_and_assistant_message_items_only()
    {
        var userMsg =
            "{\"timestamp\":\"2026-06-19T08:02:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}}";
        var devMsg =
            "{\"timestamp\":\"2026-06-19T08:02:30.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"developer\",\"content\":[]}}";
        var asstMsg =
            "{\"timestamp\":\"2026-06-19T08:03:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"done\"}]}}";
        var p = WriteLog(Meta, userMsg, devMsg, asstMsg, TokenCount);
        Assert.AreEqual(2, CodexReader.ParseFile(p)!.Messages);   // developer role excluded
    }

    [TestMethod]
    public void Title_strips_request_wrapper_from_user_message_event()
    {
        var um =
            "{\"timestamp\":\"2026-06-19T08:00:30.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"<environment_context>x</environment_context>\\n## My request for Codex:\\nadd dark mode\"}}";
        var p = WriteLog(Meta, um, TokenCount);
        Assert.AreEqual("add dark mode", CodexReader.ParseFile(p)!.Title);
    }

    [TestMethod]
    public void Title_falls_back_to_user_message_item_input_text()
    {
        var item =
            "{\"timestamp\":\"2026-06-19T08:02:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"fix the tests\"}]}}";
        var p = WriteLog(Meta, item, TokenCount);
        Assert.AreEqual("fix the tests", CodexReader.ParseFile(p)!.Title);
    }

    [TestMethod]
    public void No_session_meta_cwd_yields_no_session()
    {
        var p = WriteLog(TokenCount);
        Assert.IsNull(CodexReader.ParseFile(p));
    }

    [TestMethod]
    public void Malformed_lines_are_skipped()
    {
        var p = WriteLog("{oops", Meta, "[]", TokenCount);
        Assert.IsNotNull(CodexReader.ParseFile(p));
    }
}
