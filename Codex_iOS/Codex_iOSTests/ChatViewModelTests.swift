import XCTest
@testable import Codex_iOS

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testLoadThreadSetsActiveThreadBeforeFetchCompletes() async {
        let mock = RelayClientMock()
        mock.getThreadDelayNanos = 150_000_000

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
        mock.getThreadDelayNanos = 150_000_000

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
        viewModel.workingDirectory = "  ~/Code/Projects/Codex_iOS  "
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
        viewModel.workingDirectory = "   "
        viewModel.inputText = "hello"

        await viewModel.sendMessage()

        XCTAssertEqual(mock.chatPayloads.count, 1)
        XCTAssertNil(mock.chatPayloads.first?.workingDirectory)
    }
}

@MainActor
private final class RelayClientMock: RelayClientProtocol {
    var getThreadDelayNanos: UInt64 = 0
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
        if getThreadDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: getThreadDelayNanos)
        }

        return RelayThreadResponse(
            id: threadID,
            createdAt: messageDate,
            updatedAt: messageDate,
            messages: [
                RelayMessage(role: .user, content: "previous", timestamp: messageDate),
                RelayMessage(role: .assistant, content: "reply", timestamp: messageDate)
            ]
        )
    }

    func chat(baseURL: URL, token: String?, payload: RelayChatRequest) async throws -> RelayChatResponse {
        chatPayloads.append(payload)

        return RelayChatResponse(
            threadId: payload.threadId ?? "new-thread",
            model: "codex-default",
            reply: "ok"
        )
    }
}
