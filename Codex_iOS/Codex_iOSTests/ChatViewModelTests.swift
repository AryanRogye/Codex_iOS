import XCTest
@testable import Codex_iOS

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testLoadThreadSetsActiveThreadBeforeFetchCompletes() async {
        let mock = RelayClientMock()
        mock.getThreadDelayNanosByThreadID["old-thread"] = 150_000_000

        let suiteName = "ChatViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = ChatViewModel(client: mock, defaults: defaults)
        viewModel.relayURLText = "https://example.com"

        let loadTask = Task { await viewModel.loadThread(id: "old-thread") }
        try? await Task.sleep(nanoseconds: 15_000_000)

        XCTAssertEqual(viewModel.activeThreadID, "old-thread")
        XCTAssertTrue(viewModel.isLoading)

        await loadTask.value
    }

    func testSendMessageDuringLoadIsBlockedAndThenContinuesSameThread() async {
        let mock = RelayClientMock()
        mock.getThreadDelayNanosByThreadID["old-thread"] = 150_000_000

        let suiteName = "ChatViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = ChatViewModel(client: mock, defaults: defaults)
        viewModel.relayURLText = "https://example.com"

        let loadTask = Task { await viewModel.loadThread(id: "old-thread") }
        try? await Task.sleep(nanoseconds: 15_000_000)

        viewModel.inputText = "hello while loading"
        await viewModel.sendMessage()

        XCTAssertEqual(mock.chatPayloads.count, 0, "send should be blocked while loading")

        await loadTask.value

        viewModel.inputText = "hello after loading"
        await viewModel.sendMessage()

        XCTAssertEqual(mock.chatPayloads.count, 1)
        XCTAssertEqual(mock.chatPayloads.first?.threadId, "old-thread")
    }

    func testSendMessageIncludesConfiguredWorkingDirectory() async {
        let mock = RelayClientMock()

        let suiteName = "ChatViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = ChatViewModel(client: mock, defaults: defaults)
        viewModel.relayURLText = "https://example.com"
        viewModel.updateNewSessionWorkingDirectory("  ~/Code/Projects/Codex_iOS  ")
        viewModel.inputText = "check status"

        await viewModel.sendMessage()

        XCTAssertEqual(mock.chatPayloads.count, 1)
        XCTAssertEqual(
            mock.chatPayloads.first?.workingDirectory,
            "~/Code/Projects/Codex_iOS"
        )
    }

    func testSendMessageOmitsWorkingDirectoryWhenBlank() async {
        let mock = RelayClientMock()

        let suiteName = "ChatViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = ChatViewModel(client: mock, defaults: defaults)
        viewModel.relayURLText = "https://example.com"
        viewModel.updateNewSessionWorkingDirectory("   ")
        viewModel.inputText = "hello"

        await viewModel.sendMessage()

        XCTAssertEqual(mock.chatPayloads.count, 1)
        XCTAssertNil(mock.chatPayloads.first?.workingDirectory)
    }

    func testListDirectoriesReturnsRelayListing() async throws {
        let mock = RelayClientMock()

        let suiteName = "ChatViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = ChatViewModel(client: mock, defaults: defaults)
        viewModel.relayURLText = "https://example.com"

        let listing = try await viewModel.listDirectories(path: "/Users/example")
        XCTAssertEqual(listing.path, "/Users/example")
        XCTAssertEqual(listing.entries.first?.name, "Code")
    }

    func testSendMessageAppendsUserImmediatelyBeforeReplyReturns() async {
        let mock = RelayClientMock()
        mock.chatDelayNanos = 150_000_000
        mock.getThreadDelayNanosByThreadID["new-thread"] = 300_000_000

        let suiteName = "ChatViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = ChatViewModel(client: mock, defaults: defaults)
        viewModel.relayURLText = "https://example.com"
        viewModel.inputText = "hello"

        let sendTask = Task { await viewModel.sendMessage() }
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.inputText, "")
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertEqual(viewModel.messages.first?.content, "hello")

        await sendTask.value

        XCTAssertGreaterThanOrEqual(viewModel.messages.count, 2)
    }

    func testLatestThreadSelectionWinsWhenResponsesReturnOutOfOrder() async {
        let mock = RelayClientMock()
        mock.getThreadDelayNanosByThreadID["old-thread"] = 180_000_000
        mock.getThreadDelayNanosByThreadID["new-thread"] = 20_000_000

        let suiteName = "ChatViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = ChatViewModel(client: mock, defaults: defaults)
        viewModel.relayURLText = "https://example.com"

        let firstTask = Task { await viewModel.loadThread(id: "old-thread") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let secondTask = Task { await viewModel.loadThread(id: "new-thread") }

        await firstTask.value
        await secondTask.value

        XCTAssertEqual(viewModel.activeThreadID, "new-thread")
        XCTAssertEqual(viewModel.messages.first?.content, "new-thread-user")
    }
}

@MainActor
private final class RelayClientMock: RelayClientProtocol {
    var getThreadDelayNanosByThreadID: [String: UInt64] = [:]
    var chatDelayNanos: UInt64 = 0
    var chatPayloads: [RelayChatRequest] = []

    private let messageDate = Date(timeIntervalSince1970: 1_731_513_600)

    func health(baseURL: URL, token: String?) async throws -> RelayHealthResponse {
        RelayHealthResponse(status: "ok")
    }

    func listThreads(baseURL: URL, token: String?) async throws -> [RelayThreadSummary] {
        [
            RelayThreadSummary(
                id: "old-thread",
                createdAt: messageDate,
                updatedAt: messageDate,
                messageCount: 2,
                lastMessage: "hello"
            )
        ]
    }

    func getThread(baseURL: URL, token: String?, threadID: String) async throws -> RelayThreadResponse {
        if let delay = getThreadDelayNanosByThreadID[threadID], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }

        return RelayThreadResponse(
            id: threadID,
            createdAt: messageDate,
            updatedAt: messageDate,
            messages: [
                RelayMessage(role: .user, content: "\(threadID)-user", timestamp: messageDate),
                RelayMessage(role: .assistant, content: "\(threadID)-assistant", timestamp: messageDate)
            ]
        )
    }

    func chat(baseURL: URL, token: String?, payload: RelayChatRequest) async throws -> RelayChatResponse {
        if chatDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: chatDelayNanos)
        }
        chatPayloads.append(payload)

        return RelayChatResponse(
            threadId: payload.threadId ?? "new-thread",
            model: "codex-default",
            reply: "ok"
        )
    }

    func listDirectories(baseURL: URL, token: String?, path: String?) async throws -> RelayDirectoryListing {
        RelayDirectoryListing(
            path: path ?? "/Users/example",
            parentPath: "/Users",
            entries: [
                RelayDirectoryEntry(name: "Code", path: "/Users/example/Code", isDirectory: true),
            ]
        )
    }
}
