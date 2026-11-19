import Synchronization
import Testing
@testable import PTouchKit

/// Plays back scripted replies and records what was written.
final class FakeTransport: PrinterTransport {
    private struct State {
        var replies: [[UInt8]]
        var writes: [[UInt8]] = []
    }
    private let state: Mutex<State>

    init(replies: [[UInt8]]) { state = Mutex(State(replies: replies)) }

    var writes: [[UInt8]] { state.withLock { $0.writes } }

    func open() async throws {}
    func close() async {}
    func write(_ bytes: [UInt8]) async throws { state.withLock { $0.writes.append(bytes) } }
    func read(upTo count: Int, timeout: Duration) async throws -> [UInt8] {
        let chunk: [UInt8]? = state.withLock { s in
            guard !s.replies.isEmpty else { return nil }
            var next = s.replies.removeFirst()
            if next.count > count {
                s.replies.insert(Array(next[count...]), at: 0)
                next = Array(next[..<count])
            }
            return next
        }
        if let chunk { return chunk }
        try await Task.sleep(for: min(timeout, .milliseconds(5)))
        return []
    }
}

@Suite("Printer client")
struct PrinterClientTests {
    @Test("Status: resets, asks with ESC i S and parses the reply")
    func status() async throws {
        let fake = FakeTransport(replies: [reply()])
        let status = try await PrinterClient(transport: fake).status()
        #expect(status.loadedMedia() == .tze24mm)
        let sent = try #require(fake.writes.first)
        #expect(sent.prefix(100).allSatisfy { $0 == 0 })
        #expect(Array(sent.suffix(5)) == [0x1B, 0x40, 0x1B, 0x69, 0x53])
    }

    @Test("A reply split across reads is joined")
    func splitReply() async throws {
        let r = reply()
        let fake = FakeTransport(replies: [Array(r[..<10]), Array(r[10...])])
        #expect(try await PrinterClient(transport: fake).status().raw == r)
    }

    @Test("No reply times out")
    func noReply() async {
        let fake = FakeTransport(replies: [])
        await #expect(throws: PrinterClientError.noReply) {
            try await PrinterClient(transport: fake).status(timeout: .milliseconds(30))
        }
    }

    @Test("A cut-off reply is reported")
    func incomplete() async {
        let fake = FakeTransport(replies: [Array(reply()[..<12])])
        await #expect(throws: PrinterClientError.incompleteReply(Array(reply()[..<12]))) {
            try await PrinterClient(transport: fake).status(timeout: .milliseconds(30))
        }
    }

    @Test("Print waits through the phase change to printing completed")
    func printFlow() async throws {
        let fake = FakeTransport(replies: [
            reply(statusType: 0x06, phaseType: 0x01),
            reply(statusType: 0x01, phaseType: 0x01),
        ])
        let final = try await PrinterClient(transport: fake).print([0x1A])
        #expect(final.statusType == .printingCompleted)
        #expect(fake.writes == [[0x1A]])
    }

    @Test("Print waits for one completion per page")
    func multiPage() async throws {
        let fake = FakeTransport(replies: [
            reply(statusType: 0x01), reply(statusType: 0x06), reply(statusType: 0x01),
        ])
        let seen = Mutex(0)
        try await PrinterClient(transport: fake).print([0x0C, 0x1A], pages: 2) { _ in seen.withLock { $0 += 1 } }
        #expect(seen.withLock { $0 } == 3)
    }

    @Test("A printer error stops the job")
    func printerError() async throws {
        let wrongTape = reply(error2: 0x01, statusType: 0x02, phaseType: 0x01)
        let fake = FakeTransport(replies: [reply(statusType: 0x06, phaseType: 0x01), wrongTape])
        await #expect(throws: PrinterClientError.printerError(try PrinterStatus(bytes: wrongTape))) {
            try await PrinterClient(transport: fake).print([0x1A])
        }
    }
}
