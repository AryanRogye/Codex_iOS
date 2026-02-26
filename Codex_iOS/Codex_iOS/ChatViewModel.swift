import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var relayURLText: String
    @Published var relayToken: String
    @Published var model: String
    @Published var newSessionWorkingDirectory: String
    @Published var inputText: String = ""

    @Published private(set) var threads: [RelayThreadSummary] = []
    @Published private(set) var messages: [RelayMessage] = []
    @Published private(set) var activeThreadID: String?
    @Published private(set) var isSending: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isTestingConnection: Bool = false
    @Published private(set) var isSyncingSessions: Bool = false
    @Published var statusText: String = "Configure relay, then test connection"
    @Published var errorText: String?
    @Published private(set) var currentWorkingDirectory: String = ""
    @Published private(set) var recentWorkingDirectories: [String] = []

    private let client: RelayClientProtocol
    private let defaults: UserDefaults
    private var threadWorkingDirectories: [String: String]
    private var threadLoadGeneration: Int = 0
    private var loadedThreadUpdatedAt: [String: Date] = [:]

    private enum Keys {
        static let relayURL = "relay.url"
        static let relayToken = "relay.token"
        static let model = "relay.model"
        static let newSessionWorkingDirectory = "relay.newSessionWorkingDirectory"
        static let threadWorkingDirectories = "relay.threadWorkingDirectories"
        static let recentWorkingDirectories = "relay.recentWorkingDirectories"
        static let activeThreadID = "relay.activeThreadID"
    }

    init(client: RelayClientProtocol = RelayClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        relayURLText = defaults.string(forKey: Keys.relayURL) ?? "https://127.0.0.1:8787"
        relayToken = defaults.string(forKey: Keys.relayToken) ?? ""
        model = defaults.string(forKey: Keys.model) ?? ""
        newSessionWorkingDirectory = defaults.string(forKey: Keys.newSessionWorkingDirectory) ?? ""
        threadWorkingDirectories = Self.decodeThreadWorkingDirectories(from: defaults)
        recentWorkingDirectories = defaults.array(forKey: Keys.recentWorkingDirectories) as? [String] ?? []
        activeThreadID = defaults.string(forKey: Keys.activeThreadID)
        currentWorkingDirectory = ""
    }

    func bootstrap() async {
        await testConnection()
        await refreshThreads()
        activeThreadID = nil
        messages = []
        defaults.removeObject(forKey: Keys.activeThreadID)
        currentWorkingDirectory = newSessionWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

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
        guard isTestingConnection == false else { return }
        isTestingConnection = true
        statusText = "Testing connection..."
        errorText = nil
        defer { isTestingConnection = false }

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

    func listDirectories(path: String?) async throws -> RelayDirectoryListing {
        let config = try makeConfig()
        return try await client.listDirectories(baseURL: config.baseURL, token: config.token, path: path)
    }

    func refreshThreads() async {
        guard isSyncingSessions == false else { return }
        isSyncingSessions = true
        statusText = "Syncing sessions..."
        errorText = nil
        defer { isSyncingSessions = false }

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

            if let activeThreadID,
               let activeSummary = sortedRows.first(where: { $0.id == activeThreadID }),
               let loadedAt = loadedThreadUpdatedAt[activeThreadID],
               activeSummary.updatedAt > loadedAt {
                await loadThread(id: activeThreadID)
            }
        } catch {
            errorText = error.localizedDescription
            statusText = "Unable to sync sessions"
        }
    }

    func loadThread(id: String) async {
        threadLoadGeneration += 1
        let generation = threadLoadGeneration
        isLoading = true
        defer { isLoading = false }
        activeThreadID = id
        defaults.set(id, forKey: Keys.activeThreadID)

        do {
            let config = try makeConfig()
            let thread = try await client.getThread(baseURL: config.baseURL, token: config.token, threadID: id)
            guard generation == threadLoadGeneration else { return }
            messages = thread.messages
            activeThreadID = thread.id
            defaults.set(thread.id, forKey: Keys.activeThreadID)
            loadedThreadUpdatedAt[thread.id] = thread.updatedAt
            currentWorkingDirectory = threadWorkingDirectories[thread.id] ?? ""
            errorText = nil
            statusText = "Loaded session \(shortID(thread.id))"
        } catch {
            guard generation == threadLoadGeneration else { return }
            errorText = error.localizedDescription
            statusText = "Unable to load session"
        }
    }

    func startNewSession() {
        threadLoadGeneration += 1
        activeThreadID = nil
        messages = []
        defaults.removeObject(forKey: Keys.activeThreadID)
        currentWorkingDirectory = newSessionWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        statusText = "Started new session"
        errorText = nil
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        guard isSending == false else { return }
        guard isLoading == false else { return }

        let previousMessages = messages
        let previousThreadID = activeThreadID
        let previousInput = inputText

        inputText = ""
        messages.append(RelayMessage(role: .user, content: text, timestamp: Date()))

        isSending = true
        defer { isSending = false }

        do {
            let config = try makeConfig()
            let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanWorkingDirectory = effectiveWorkingDirectory()
            let payload = RelayChatRequest(
                threadId: activeThreadID,
                message: text,
                model: cleanModel.isEmpty ? nil : cleanModel,
                workingDirectory: cleanWorkingDirectory.isEmpty ? nil : cleanWorkingDirectory
            )

            let reply = try await client.chat(baseURL: config.baseURL, token: config.token, payload: payload)
            messages.append(RelayMessage(role: .assistant, content: reply.reply, timestamp: Date()))
            activeThreadID = reply.threadId
            defaults.set(reply.threadId, forKey: Keys.activeThreadID)
            if cleanWorkingDirectory.isEmpty == false {
                currentWorkingDirectory = cleanWorkingDirectory
                threadWorkingDirectories[reply.threadId] = cleanWorkingDirectory
                persistThreadWorkingDirectories()
                addRecentWorkingDirectory(cleanWorkingDirectory)
            } else {
                currentWorkingDirectory = ""
            }
            statusText = "Reply received"
            errorText = nil

            await refreshThreads()
            Task { [weak self] in
                await self?.loadThread(id: reply.threadId)
            }
        } catch {
            inputText = previousInput
            messages = previousMessages
            activeThreadID = previousThreadID
            if let previousThreadID {
                defaults.set(previousThreadID, forKey: Keys.activeThreadID)
            } else {
                defaults.removeObject(forKey: Keys.activeThreadID)
            }
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
            "https://\(trimmed)"
        }

        guard let baseURL = URL(string: normalized) else {
            throw RelayClientError.invalidURL
        }

        return RelayConfig(
            baseURL: baseURL,
            token: relayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var canPickDirectoryForNewSession: Bool {
        activeThreadID == nil && messages.isEmpty
    }

    var displayWorkingDirectory: String? {
        let trimmed = currentWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func updateNewSessionWorkingDirectory(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        newSessionWorkingDirectory = trimmed
        defaults.set(trimmed, forKey: Keys.newSessionWorkingDirectory)
        if canPickDirectoryForNewSession {
            currentWorkingDirectory = trimmed
        }
    }

    private func effectiveWorkingDirectory() -> String {
        if canPickDirectoryForNewSession {
            let trimmed = newSessionWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            currentWorkingDirectory = trimmed
            return trimmed
        }
        return currentWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addRecentWorkingDirectory(_ value: String) {
        var updated = recentWorkingDirectories.filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        updated.insert(value, at: 0)
        if updated.count > 8 {
            updated = Array(updated.prefix(8))
        }
        recentWorkingDirectories = updated
        defaults.set(updated, forKey: Keys.recentWorkingDirectories)
    }

    private func persistThreadWorkingDirectories() {
        if let data = try? JSONEncoder().encode(threadWorkingDirectories) {
            defaults.set(data, forKey: Keys.threadWorkingDirectories)
        }
    }

    private static func decodeThreadWorkingDirectories(from defaults: UserDefaults) -> [String: String] {
        guard let data = defaults.data(forKey: Keys.threadWorkingDirectories) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
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
