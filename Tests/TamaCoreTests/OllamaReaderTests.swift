import XCTest
import TamaCore

final class OllamaReaderTests: XCTestCase {
    private let fm = FileManager.default
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func fixture(_ lines: [String]) throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("ollama-\(UUID().uuidString)/logs")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("server.log")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // Real-format line builders.
    private func start(_ tag: String, port: Int = 100) -> String {
        #"time=2026-06-22T18:36:56.556+07:00 level=INFO source=client.go:367 msg="starting mlx runner subprocess" model=\#(tag) port=\#(port)"#
    }
    private func stop(pid: Int = 999) -> String {
        #"time=2026-06-22T19:29:32.938+07:00 level=INFO source=client.go:126 msg="stopping mlx runner subprocess" pid=\#(pid)"#
    }
    private func prompt(_ win: Int, _ tok: Int) -> String {
        "slot update_slots: id  0 | task 5 | new prompt, n_ctx_slot = \(win), n_keep = 4, task.n_tokens = \(tok)"
    }
    private let processing = "slot launch_slot_: id  0 | task 5 | processing task, is_child = 0"
    private let idle = "srv  update_slots: all slots are idle"
    private func timing(_ tps: Double) -> String {
        "slot print_timing: id  0 | task 5 | n_decoded =    100, tg =  \(tps) t/s"
    }
    private func gin(_ time: String, _ dur: String, _ endpoint: String, status: Int = 200) -> String {
        "[GIN] 2026/06/22 - \(time) | \(status) |   \(dur) |       127.0.0.1 | POST     \"\(endpoint)\""
    }

    func test_lists_models_most_recent_first_with_attribution() throws {
        let url = try fixture([
            start("qwen3.6:27b-mlx"), prompt(32768, 2000), processing, timing(50.0),
            gin("19:00:00", "5.0s", "/api/generate"), idle, stop(),
            start("gemma4:12b-mlx"), prompt(8192, 500), processing, timing(80.0),
            gin("19:30:00", "2.0s", "/api/chat"), gin("19:30:05", "200ms", "/api/chat"),
        ])
        let models = OllamaReader(logURL: url, calendar: utc).read()?.models
        XCTAssertEqual(models?.count, 2)

        let g = models?.first
        XCTAssertEqual(g?.model, "gemma4:12b-mlx")
        XCTAssertEqual(g?.current, true)
        XCTAssertEqual(g?.busy, true)                       // processing, no idle after
        XCTAssertEqual(g?.contextWindow, 8192)
        XCTAssertEqual(g?.contextTokens, 500)
        XCTAssertEqual(g?.tokensPerSecond, 80.0)
        XCTAssertEqual(g?.lastLatency ?? 0, 0.2, accuracy: 0.001)   // 200ms
        XCTAssertEqual(g?.kind, .chat)
        XCTAssertEqual(g?.requestCount, 2)

        let q = models?.last
        XCTAssertEqual(q?.model, "qwen3.6:27b-mlx")
        XCTAssertEqual(q?.current, false)
        XCTAssertEqual(q?.busy, false)                      // idle after
        XCTAssertEqual(q?.contextWindow, 32768)
        XCTAssertEqual(q?.tokensPerSecond, 50.0)
        XCTAssertEqual(q?.lastLatency ?? 0, 5.0, accuracy: 0.001)
        XCTAssertEqual(q?.requestCount, 1)
    }

    func test_embedding_endpoint_is_embed_kind() throws {
        let url = try fixture([start("bge-m3"), gin("19:00:00", "120ms", "/api/embeddings")])
        XCTAssertEqual(OllamaReader(logURL: url, calendar: utc).read()?.models.first?.kind, .embed)
    }

    func test_same_model_loaded_twice_merges() throws {
        let url = try fixture([
            start("gemma4:12b-mlx"), gin("19:00:00", "1.0s", "/api/chat"), idle, stop(),
            start("gemma4:12b-mlx"), gin("19:10:00", "1.0s", "/api/chat"),
        ])
        let models = OllamaReader(logURL: url, calendar: utc).read()?.models
        XCTAssertEqual(models?.count, 1)
        XCTAssertEqual(models?.first?.requestCount, 2)
    }

    func test_non_inference_endpoints_do_not_count() throws {
        let url = try fixture([start("gemma4:12b-mlx"), gin("19:00:00", "10ms", "/api/tags"),
                               gin("19:00:01", "5ms", "/api/show")])
        let m = OllamaReader(logURL: url, calendar: utc).read()?.models.first
        XCTAssertEqual(m?.requestCount, 0)
        XCTAssertEqual(m?.kind, .unknown)
    }

    func test_last_activity_is_log_mtime() throws {
        let url = try fixture([start("gemma4:12b-mlx"), idle])
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        let last = try XCTUnwrap(OllamaReader(logURL: url, calendar: utc).read()?.lastActivity)
        XCTAssertEqual(last.timeIntervalSince1970, stamp.timeIntervalSince1970, accuracy: 1)
    }

    func test_running_with_no_model_loads_yields_empty_models() throws {
        let url = try fixture(["srv  update_slots: all slots are idle", "some unrelated line"])
        let status = OllamaReader(logURL: url, calendar: utc).read()
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.models.isEmpty, true)
    }

    func test_missing_log_is_nil() {
        let missing = fm.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)/server.log")
        XCTAssertNil(OllamaReader(logURL: missing, calendar: utc).read())
    }

    func test_empty_log_is_nil() throws {
        XCTAssertNil(OllamaReader(logURL: try fixture([]), calendar: utc).read())
    }
}
