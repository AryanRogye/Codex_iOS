import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var relayURLText: String
    @Published var relayToken: String
    @Published var model: String
    @Published var inputText: String = ""

    @Published private(set) var threads: [RelayThreadSummary] = []
    @Published private(set) var messages: [RelayMessage] = []
    @Published private(set) var activeThreadID: String?
    @Published private(set) var isSending: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published var statusText: String = "Configure relay, then test connection"
    @Published var errorText: String?

    private let client = RelayClient()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let relayURL = "relay.url"
        static let relayToken = "relay.token"
        static let model = "relay.model"
        static let activeThreadID = "relay.activeThreadID"
    }

    init() {
        relayURLText = defaults.string(forKey: Keys.relayURL) ?? "http://127.0.0.1:8787"
        relayToken = defaults.string(forKey: Keys.relayToken) ?? ""
        model = defaults.string(forKey: Keys.model) ?? ""
        activeThreadID = defaults.string(forKey: Keys.activeThreadID)
    }

    func bootstrap() async {
        await testConnection()
        await refreshThreads()
        activeThreadID = nil
        messages = []
        defaults.removeObject(forKey: Keys.activeThreadID)

        if errorText == nil {
            statusText = "Ready. Start a new chat or open an existing session."
        }
    }

    func saveSettings() {
        defaults.set(relayURLText.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.relayURL)
        defaults.set(relayToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.relayToken)
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.model)
        statusText = "Settings saved"
    }

    func testConnection() async {
        do {
            let config = try makeConfig()
            let health = try await client.health(baseURL: config.baseURL, token: config.token)
            statusText = "Relay status: \(health.status)"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            statusText = "Unable to connect"
        }
    }

    func refreshThreads() async {
        do {
            let config = try makeConfig()
            let rows = try await client.listThreads(baseURL: config.baseURL, token: config.token)
            let sortedRows = rows.sorted { $0.updatedAt > $1.updatedAt }
            threads = sortedRows
            errorText = nil

            if let activeThreadID,
               sortedRows.contains(where: { $0.id == activeThreadID }) == false {
                self.activeThreadID = nil
                defaults.removeObject(forKey: Keys.activeThreadID)
            }

            let count = sortedRows.count
            statusText = "Synced \(count) session\(count == 1 ? "" : "s")"
        } catch {
            errorText = error.localizedDescription
            statusText = "Unable to sync sessions"
        }
    }

    func loadThread(id: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let config = try makeConfig()
            let thread = try await client.getThread(baseURL: config.baseURL, token: config.token, threadID: id)
            messages = thread.messages
            activeThreadID = thread.id
            defaults.set(thread.id, forKey: Keys.activeThreadID)
            errorText = nil
            statusText = "Loaded session \(shortID(thread.id))"
        } catch {
            errorText = error.localizedDescription
            statusText = "Unable to load session"
        }
    }

    func startNewSession() {
        activeThreadID = nil
        messages = []
        defaults.removeObject(forKey: Keys.activeThreadID)
        statusText = "Started new session"
        errorText = nil
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        guard isSending == false else { return }

        isSending = true
        defer { isSending = false }

        do {
            let config = try makeConfig()
            let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = RelayChatRequest(
                threadId: activeThreadID,
                message: text,
                model: cleanModel.isEmpty ? nil : cleanModel
            )

            let reply = try await client.chat(baseURL: config.baseURL, token: config.token, payload: payload)
            inputText = ""
            activeThreadID = reply.threadId
            defaults.set(reply.threadId, forKey: Keys.activeThreadID)
            statusText = "Reply received"
            errorText = nil

            await loadThread(id: reply.threadId)
            await refreshThreads()
        } catch {
            errorText = error.localizedDescription
            statusText = "Message failed"
        }
    }

    private func makeConfig() throws -> RelayConfig {
        let trimmed = relayURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw RelayClientError.invalidURL
        }

        let normalized = if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            trimmed
        } else {
            "http://\(trimmed)"
        }

        guard let baseURL = URL(string: normalized) else {
            throw RelayClientError.invalidURL
        }

        return RelayConfig(
            baseURL: baseURL,
            token: relayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func shortID(_ value: String) -> String {
        if value.count <= 8 {
            return value
        }
        return String(value.prefix(8))
    }
}

private struct RelayConfig {
    let baseURL: URL
    let token: String
}
