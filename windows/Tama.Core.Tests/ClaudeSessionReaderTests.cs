using System.Text.Json;
using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class ClaudeSessionReaderTests
{
    private string _root = null!;

    [TestInitialize]
    public void SetUp()
    {
        _root = Path.Combine(Path.GetTempPath(), "claude-" + Guid.NewGuid());
        Directory.CreateDirectory(_root);
    }

    [TestCleanup]
    public void TearDown() => Directory.Delete(_root, recursive: true);

    private string WriteLog(string name, params string[] lines)
    {
        var p = Path.Combine(_root, name);
        File.WriteAllText(p, string.Join("\n", lines));
        return p;
    }

    private const string Usage100 =
        "\"usage\":{\"input_tokens\":100,\"output_tokens\":10,\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":2}";

    [TestMethod]
    public void Split_assistant_lines_with_the_same_message_id_count_once()
    {
        var p = WriteLog("s.jsonl",
            $"{{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{{\"id\":\"m1\",\"model\":\"claude-opus-4-8\",{Usage100}}}}}",
            $"{{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:01.000Z\",\"cwd\":\"/p\",\"message\":{{\"id\":\"m1\",\"model\":\"claude-opus-4-8\",{Usage100}}}}}");
        var parsed = ClaudeSessionReader.ParseFile(p)!;
        Assert.AreEqual(117, parsed.Cumulative.Total); // not 234
        Assert.AreEqual(1, parsed.Messages);
    }

    [TestMethod]
    public void Sidechain_counts_tokens_but_not_context()
    {
        var p = WriteLog("s.jsonl",
            $"{{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{{\"id\":\"m1\",{Usage100}}}}}",
            "{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:05:00.000Z\",\"cwd\":\"/p\",\"isSidechain\":true,\"message\":{\"id\":\"m2\",\"usage\":{\"input_tokens\":50,\"output_tokens\":5}}}");
        var parsed = ClaudeSessionReader.ParseFile(p)!;
        Assert.AreEqual(117 + 55, parsed.Cumulative.Total);
        Assert.AreEqual(100 + 5 + 2 + 10, parsed.ContextTokens); // m1's, not the later sidechain's
    }

    [TestMethod]
    public void IsMeta_user_lines_are_not_messages_and_not_titles()
    {
        var p = WriteLog("s.jsonl",
            "{\"type\":\"user\",\"isMeta\":true,\"timestamp\":\"2026-06-19T08:59:00.000Z\",\"cwd\":\"/p\",\"message\":{\"role\":\"user\",\"content\":\"meta stuff\"}}",
            "{\"type\":\"user\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{\"role\":\"user\",\"content\":\"real prompt\"}}",
            $"{{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:10.000Z\",\"cwd\":\"/p\",\"message\":{{\"id\":\"m1\",{Usage100}}}}}");
        var parsed = ClaudeSessionReader.ParseFile(p)!;
        Assert.AreEqual(2, parsed.Messages);          // real user + assistant
        Assert.AreEqual("real prompt", parsed.Title); // firstPrompt fallback skips isMeta
    }

    [TestMethod]
    public void Summary_line_beats_first_prompt_as_title()
    {
        var p = WriteLog("s.jsonl",
            "{\"type\":\"user\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{\"role\":\"user\",\"content\":\"first prompt\"}}",
            $"{{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:10.000Z\",\"cwd\":\"/p\",\"message\":{{\"id\":\"m1\",{Usage100}}}}}",
            "{\"type\":\"summary\",\"summary\":\"The Title\"}");
        Assert.AreEqual("The Title", ClaudeSessionReader.ParseFile(p)!.Title);
    }

    [TestMethod]
    public void File_without_any_usage_line_yields_no_session()
    {
        var p = WriteLog("s.jsonl",
            "{\"type\":\"user\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{\"role\":\"user\",\"content\":\"hi\"}}");
        Assert.IsNull(ClaudeSessionReader.ParseFile(p));
    }

    [TestMethod]
    public void Malformed_lines_are_skipped_not_fatal()
    {
        var p = WriteLog("s.jsonl",
            "{not json at all",
            "[1,2,3]",
            $"{{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{{\"id\":\"m1\",{Usage100}}}}}");
        Assert.AreEqual(117, ClaudeSessionReader.ParseFile(p)!.Cumulative.Total);
    }

    [TestMethod]
    public void SessionId_falls_back_to_filename_prefix()
    {
        var p = WriteLog("0123456789abcdef.jsonl",
            $"{{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/p\",\"message\":{{\"id\":\"m1\",{Usage100}}}}}");
        Assert.AreEqual("01234567", ClaudeSessionReader.ParseFile(p)!.SessionId);
    }

    [TestMethod]
    public void ContextWindow_defaults_200k_promotes_on_1m_marker_or_overflow()
    {
        Assert.AreEqual(200_000, ClaudeSessionReader.ContextWindowFor("claude-opus-4-8", 10_000));
        Assert.AreEqual(1_000_000, ClaudeSessionReader.ContextWindowFor("claude-sonnet-5[1m]", 10_000));
        Assert.AreEqual(1_000_000, ClaudeSessionReader.ContextWindowFor("claude-sonnet-5-1m", 10_000));
        Assert.AreEqual(1_000_000, ClaudeSessionReader.ContextWindowFor("claude-opus-4-8", 250_000));
        Assert.AreEqual(200_000, ClaudeSessionReader.ContextWindowFor(null, 0));
    }

    private static JsonElement Msg(string json) => JsonDocument.Parse(json).RootElement;

    [TestMethod]
    public void UserPrompt_extracts_string_and_text_blocks_rejects_tool_results()
    {
        Assert.AreEqual("hi there", ClaudeSessionReader.UserPrompt(Msg("{\"content\":\"  hi   there \"}")));
        Assert.AreEqual("a b", ClaudeSessionReader.UserPrompt(
            Msg("{\"content\":[{\"type\":\"text\",\"text\":\"a\"},{\"type\":\"text\",\"text\":\"b\"}]}")));
        Assert.IsNull(ClaudeSessionReader.UserPrompt(
            Msg("{\"content\":[{\"type\":\"tool_result\",\"content\":\"x\"},{\"type\":\"text\",\"text\":\"a\"}]}")));
        Assert.IsNull(ClaudeSessionReader.UserPrompt(Msg("{\"content\":\"<system-tag>hidden\"}")));
        Assert.IsNull(ClaudeSessionReader.UserPrompt(Msg("{\"content\":\"[Request interrupted by user\"}")));
        Assert.IsNull(ClaudeSessionReader.UserPrompt(Msg("{\"content\":\"   \"}")));
    }

    [TestMethod]
    public void CleanPrompt_caps_at_80_chars_with_ellipsis()
    {
        var longPrompt = new string('a', 80) + " tail-word-beyond";
        var cleaned = ClaudeSessionReader.CleanPrompt(longPrompt)!;
        Assert.AreEqual(new string('a', 80) + "…", cleaned); // 80 kept + ellipsis = 81 chars
    }
}
