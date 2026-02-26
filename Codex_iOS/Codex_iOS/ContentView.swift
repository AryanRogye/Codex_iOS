import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var focusedField: FocusField?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("chat.fontScale") private var chatFontScale: Double = 1.0

    @State private var isSidebarPresented = false
    @State private var selectedThreadID: String?
    @State private var sessionSearchText = ""
    @State private var visibleSessionLimit = Self.sessionPageSize
    @State private var isDirectoryPickerPresented = false
    @State private var pickerListing: RelayDirectoryListing?
    @State private var pickerError: String?
    @State private var pickerIsLoading = false

    private enum FocusField: Hashable {
        case message
    }

    private static let sessionPageSize = 80
    private static let minFontScale = 0.8
    private static let maxFontScale = 1.45

    var body: some View {
        NavigationStack {
            Group {
                if isRegularLayout {
                    regularLayout
                } else {
                    compactLayout
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSidebarPresented)
            .navigationTitle("Chats")
            .toolbar {
                if isRegularLayout == false {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismissKeyboard()
                            withAnimation {
                                isSidebarPresented.toggle()
                            }
                        } label: {
                            Label("Sessions", systemImage: "sidebar.left")
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    displayMenu
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
        }
        .sheet(isPresented: $isDirectoryPickerPresented) {
            directoryPickerSheet
        }
        .task {
            await viewModel.bootstrap()
            selectedThreadID = viewModel.activeThreadID
            resetSessionWindow()
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            if newValue == .regular {
                isSidebarPresented = false
            }
        }
        .onChange(of: viewModel.activeThreadID) { _, newValue in
            if selectedThreadID != newValue {
                selectedThreadID = newValue
            }
        }
        .onChange(of: viewModel.threads.count) { _, _ in
            resetSessionWindow()
        }
        .onChange(of: sessionSearchText) { _, _ in
            resetSessionWindow()
        }
    }

    private var displayMenu: some View {
        Menu {
            Section("Message Text") {
                presetButton(title: "Compact (85%)", scale: 0.85)
                presetButton(title: "Default (100%)", scale: 1.0)
                presetButton(title: "Large (115%)", scale: 1.15)
                presetButton(title: "XL (130%)", scale: 1.3)
            }

            Divider()

            Button("Decrease Size") {
                adjustFontScale(by: -0.05)
            }
            .disabled(clampedFontScale <= Self.minFontScale)

            Button("Increase Size") {
                adjustFontScale(by: 0.05)
            }
            .disabled(clampedFontScale >= Self.maxFontScale)

            Button("Reset Size") {
                chatFontScale = 1.0
            }
        } label: {
            Label("Display", systemImage: "textformat.size")
        }
    }

    private func presetButton(title: String, scale: Double) -> some View {
        Button {
            chatFontScale = scale
        } label: {
            HStack {
                Text(title)
                Spacer()
                if abs(clampedFontScale - scale) < 0.01 {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            sidebarPanel
                .frame(width: 320)

            Divider()

            detailPane
        }
    }

    private var compactLayout: some View {
        GeometryReader { proxy in
            let drawerWidth = min(320, max(260, proxy.size.width * 0.74))

            ZStack(alignment: .leading) {
                detailPane

                if isSidebarPresented {
                    Color.black.opacity(0.14)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                isSidebarPresented = false
                            }
                        }

                    sidebarPanel
                        .frame(width: drawerWidth)
                        .transition(.move(edge: .leading))
                        .overlay(
                            Rectangle()
                                .fill(Color(uiColor: .separator).opacity(0.35))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                        .zIndex(1)
                }
            }
        }
    }

    private var sidebarPanel: some View {
        sessionsSidebar
            .background(sidebarBackground)
    }

    private var detailPane: some View {
        VStack(spacing: 10) {
            activeSessionCard
            messageList
            composer
            statusLine
        }
        .padding(isRegularLayout ? 16 : 12)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private var sessionsSidebar: some View {
        let filteredThreads = self.filteredThreads
        let visibleThreads = Array(filteredThreads.prefix(visibleSessionLimit))
        let hasMoreThreads = filteredThreads.count > visibleThreads.count

        return VStack(spacing: 8) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                Spacer()
                Text("\(filteredThreads.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            TextField("Search ID or last message", text: $sessionSearchText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 12)

            List {
                Section("Actions") {
                    Button {
                        dismissKeyboard()
                        viewModel.startNewSession()
                        selectedThreadID = nil
                        if isRegularLayout == false {
                            withAnimation {
                                isSidebarPresented = false
                            }
                        }
                    } label: {
                        Label("New Session", systemImage: "square.and.pencil")
                    }

                    Button {
                        dismissKeyboard()
                        Task { await viewModel.refreshThreads() }
                    } label: {
                        Label("Sync Sessions", systemImage: "arrow.clockwise")
                    }
                }

                Section("Threads") {
                    if visibleThreads.isEmpty {
                        Text(filteredThreads.isEmpty ? "No sessions yet." : "No sessions match your search.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleThreads) { thread in
                            Button {
                                selectThread(thread.id)
                            } label: {
                                sessionRow(thread)
                            }
                            .buttonStyle(.plain)
                        }

                        if hasMoreThreads {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("Loading more...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .onAppear {
                                loadNextSessionPage()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    private var activeSessionCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)

            if let activeThreadID = viewModel.activeThreadID {
                Text("Session \(viewModel.shortID(activeThreadID))")
                    .font(.subheadline.monospaced())
                    .lineLimit(1)
            } else {
                Text("No active session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("A \(Int(clampedFontScale * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("\(viewModel.messages.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: scaled(10)) {
                    if viewModel.messages.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "ellipsis.bubble")
                                .font(.system(size: scaled(24)))
                                .foregroundStyle(.secondary)

                            Text("No messages yet")
                                .font(.system(size: scaled(15), weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text("Send a message to start a real-time relay chat.")
                                .font(.system(size: scaled(13), weight: .regular, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                    }

                    ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                        if shouldShowDateSeparator(at: index) {
                            dateSeparator(for: message.timestamp)
                        }

                        messageRow(message, isPending: isPendingMessage(at: index, message: message))
                            .id(messageID(for: index))
                    }

                    if viewModel.isSending {
                        waitingForResponseRow
                            .id("assistant-waiting")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                dismissKeyboard()
            }
            .background(transcriptBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 0.5)
            )
            .overlay(alignment: .center) {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(10)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.activeThreadID) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private var transcriptBackground: some View {
        Color(uiColor: .systemBackground)
    }

    private func messageRow(_ message: RelayMessage, isPending: Bool) -> some View {
        let isAssistant = message.role == .assistant

        return HStack(alignment: .bottom, spacing: 10) {
            if isAssistant {
                speakerBadge(systemName: "sparkles", tint: .orange)
                messageBubble(message, isAssistant: true, isPending: false)
                Spacer(minLength: 50)
            } else {
                Spacer(minLength: 50)
                messageBubble(message, isAssistant: false, isPending: isPending)
                speakerBadge(systemName: "person.fill", tint: .blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: isAssistant ? .leading : .trailing)
    }

    private func speakerBadge(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: scaled(11), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: scaled(24), height: scaled(24))
            .background(tint.gradient, in: Circle())
    }

    private var waitingForResponseRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            speakerBadge(systemName: "sparkles", tint: .orange)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Codex is thinking...")
                    .font(bodyFont)
            }
            .padding(.horizontal, scaled(12))
            .padding(.vertical, scaled(10))
            .background(
                LinearGradient(
                    colors: [
                        Color(uiColor: .secondarySystemBackground),
                        Color(uiColor: .tertiarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: bubbleShape(isAssistant: true)
            )

            Spacer(minLength: 50)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageBubble(_ message: RelayMessage, isAssistant: Bool, isPending: Bool) -> some View {
        VStack(alignment: .leading, spacing: scaled(8)) {
            ForEach(messageSegments(for: message.content)) { segment in
                switch segment.kind {
                case let .text(text):
                    MarkdownBlockListView(
                        blocks: markdownBlocks(from: text),
                        basePointSize: scaled(16),
                        lineSpacing: scaled(2),
                        textColor: isAssistant ? .primary : .white,
                        secondaryTextColor: isAssistant ? .secondary : Color.white.opacity(0.78)
                    )
                    .tint(isAssistant ? .blue : .white)
                case let .code(language, body):
                    if isDiffSnippet(text: body, language: language) {
                        DiffSnippetView(
                            diffText: body,
                            font: codeFont,
                            isAssistantBubble: isAssistant
                        )
                    } else {
                        CodeSnippetView(
                            text: body,
                            language: language,
                            font: codeFont,
                            isAssistantBubble: isAssistant
                        )
                    }
                }
            }

            if isAssistant {
                let options = QuickChoiceParser.options(from: message.content)
                if options.isEmpty == false {
                    optionChips(options)
                }
            }

            HStack(spacing: 6) {
                Text(isAssistant ? "Codex" : "You")
                Spacer(minLength: 8)
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.white.opacity(0.95))
                    Text("Sending...")
                } else {
                    Text(Self.timeFormatter.string(from: message.timestamp))
                }
            }
            .font(metaFont)
            .foregroundStyle(isAssistant ? .secondary : Color.white.opacity(0.85))
        }
        .padding(.horizontal, scaled(12))
        .padding(.vertical, scaled(10))
        .foregroundStyle(isAssistant ? Color.primary : Color.white)
        .background(
            bubbleBackground(isAssistant: isAssistant),
            in: bubbleShape(isAssistant: isAssistant)
        )
        .frame(maxWidth: 520, alignment: isAssistant ? .leading : .trailing)
        .textSelection(.enabled)
    }

    private func bubbleShape(isAssistant: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 18,
                bottomLeading: isAssistant ? 8 : 18,
                bottomTrailing: isAssistant ? 18 : 8,
                topTrailing: 18
            ),
            style: .continuous
        )
    }

    private func bubbleBackground(isAssistant: Bool) -> LinearGradient {
        if isAssistant {
            LinearGradient(
                colors: [
                    Color(uiColor: .secondarySystemBackground),
                    Color(uiColor: .tertiarySystemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color.blue,
                    Color.indigo
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func optionChips(_ options: [QuickChoiceOption]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 78), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(options, id: \.label) { option in
                Button {
                    insertQuickChoice(option.insertionText)
                } label: {
                    Text(option.label)
                        .font(.system(size: scaled(13), weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.canPickDirectoryForNewSession {
                newSessionDirectoryPicker
            } else if let workingDirectory = viewModel.displayWorkingDirectory {
                workingDirectoryReadOnly(workingDirectory)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Codex...", text: $viewModel.inputText, axis: .vertical)
                    .font(bodyFont)
                    .focused($focusedField, equals: .message)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )

                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: scaled(26)))
                            .foregroundStyle(
                                viewModel.inputText.trimmedForSend.isEmpty ? Color.secondary : Color.blue
                            )
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending || viewModel.isLoading || viewModel.inputText.trimmedForSend.isEmpty)
                .accessibilityLabel("Send Message")
            }
        }
    }

    private var newSessionDirectoryPicker: some View {
        HStack(spacing: 8) {
            Label(
                viewModel.newSessionWorkingDirectory.trimmedForSend.isEmpty
                    ? "No directory selected"
                    : viewModel.newSessionWorkingDirectory,
                systemImage: "folder"
            )
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.secondary)

            Spacer()

            if viewModel.newSessionWorkingDirectory.trimmedForSend.isEmpty == false {
                Button("Clear") {
                    viewModel.updateNewSessionWorkingDirectory("")
                }
                .font(.caption)
            }

            Button("Browse") {
                dismissKeyboard()
                isDirectoryPickerPresented = true
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func workingDirectoryReadOnly(_ path: String) -> some View {
        Label(path, systemImage: "folder")
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.secondary)
    }

    private var directoryPickerSheet: some View {
        NavigationStack {
            Group {
                if pickerIsLoading {
                    ProgressView("Loading folders…")
                } else if let pickerError {
                    VStack(spacing: 10) {
                        Text("Unable to browse folders")
                            .font(.headline)
                        Text(pickerError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadDirectoryListing(path: pickerListing?.path) }
                        }
                    }
                    .padding()
                } else if let listing = pickerListing {
                    List {
                        if viewModel.recentWorkingDirectories.isEmpty == false {
                            Section("Recent") {
                                ForEach(viewModel.recentWorkingDirectories, id: \.self) { item in
                                    Button {
                                        Task { await loadDirectoryListing(path: item) }
                                    } label: {
                                        Label(item, systemImage: "clock.arrow.circlepath")
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }

                        Section("Current") {
                            Button {
                                viewModel.updateNewSessionWorkingDirectory(listing.path)
                                isDirectoryPickerPresented = false
                            } label: {
                                Label("Use This Folder", systemImage: "checkmark.circle.fill")
                            }
                        }

                        if let parentPath = listing.parentPath {
                            Section("Navigate") {
                                Button {
                                    Task { await loadDirectoryListing(path: parentPath) }
                                } label: {
                                    Label("..", systemImage: "arrow.up.left")
                                }
                            }
                        }

                        Section("Folders") {
                            if listing.entries.isEmpty {
                                Text("No subfolders")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(listing.entries) { entry in
                                    Button {
                                        Task { await loadDirectoryListing(path: entry.path) }
                                    } label: {
                                        Label(entry.name, systemImage: "folder")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("Loading folders…")
                }
            }
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isDirectoryPickerPresented = false
                    }
                }
            }
        }
        .task(id: isDirectoryPickerPresented) {
            guard isDirectoryPickerPresented else { return }
            let preferred = viewModel.newSessionWorkingDirectory.trimmedForSend
            await loadDirectoryListing(path: preferred.isEmpty ? nil : preferred)
        }
    }

    @MainActor
    private func loadDirectoryListing(path: String?) async {
        pickerIsLoading = true
        pickerError = nil
        defer { pickerIsLoading = false }

        do {
            pickerListing = try await viewModel.listDirectories(path: path)
        } catch {
            pickerError = error.localizedDescription
        }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.errorText == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(viewModel.errorText == nil ? Color.green : Color.red)
                    .font(.caption)

                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateSeparator(for date: Date) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)

            Text(Self.dateFormatter.string(from: date))
                .font(metaFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }

    private func sessionRow(_ thread: RelayThreadSummary) -> some View {
        let isSelected = thread.id == selectedThreadID

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(viewModel.shortID(thread.id))
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)

                Spacer()

                Text(thread.updatedAt, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(thread.lastMessage ?? "No messages")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("\(thread.messageCount) message\(thread.messageCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var sidebarBackground: some View {
        Color(uiColor: .systemGroupedBackground)
    }

    private var filteredThreads: [RelayThreadSummary] {
        let query = sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return viewModel.threads }

        let normalized = query.lowercased()
        return viewModel.threads.filter { thread in
            thread.id.lowercased().contains(normalized)
                || (thread.lastMessage?.lowercased().contains(normalized) ?? false)
        }
    }

    private func selectThread(_ threadID: String) {
        selectedThreadID = threadID
        dismissKeyboard()
        Task { await viewModel.loadThread(id: threadID) }

        if isRegularLayout == false {
            withAnimation {
                isSidebarPresented = false
            }
        }
    }

    private func resetSessionWindow() {
        visibleSessionLimit = Self.sessionPageSize
    }

    private func loadNextSessionPage() {
        let total = filteredThreads.count
        guard visibleSessionLimit < total else { return }
        visibleSessionLimit = min(visibleSessionLimit + Self.sessionPageSize, total)
    }

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = viewModel.messages[index].timestamp
        let previous = viewModel.messages[index - 1].timestamp
        return Calendar.current.isDate(current, inSameDayAs: previous) == false
    }

    private func isPendingMessage(at index: Int, message: RelayMessage) -> Bool {
        guard viewModel.isSending else { return false }
        guard message.role == .user else { return false }
        return index == viewModel.messages.indices.last
    }

    private func messageID(for index: Int) -> String {
        "message-\(index)"
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastIndex = viewModel.messages.indices.last else { return }
        let id = messageID(for: lastIndex)
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func insertQuickChoice(_ option: String) {
        let existing = viewModel.inputText.trimmedForSend
        viewModel.inputText = existing.isEmpty ? option : "\(existing)\n\(option)"
        focusedField = .message
    }

    private func adjustFontScale(by delta: Double) {
        chatFontScale = min(Self.maxFontScale, max(Self.minFontScale, chatFontScale + delta))
    }

    private var clampedFontScale: Double {
        min(Self.maxFontScale, max(Self.minFontScale, chatFontScale))
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * CGFloat(clampedFontScale)
    }

    private var bodyFont: Font {
        .system(size: scaled(16), weight: .regular, design: .rounded)
    }

    private var metaFont: Font {
        .system(size: scaled(11), weight: .medium, design: .monospaced)
    }

    private var codeFont: Font {
        .system(size: scaled(13), weight: .regular, design: .monospaced)
    }

    private func markdownBlocks(from text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append(MarkdownBlock(kind: .thematicBreak))
                index += 1
                continue
            }

            if let heading = headingInfo(for: trimmed) {
                blocks.append(MarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.isEmpty == false, candidate.hasPrefix(">") else { break }
                    quoteLines.append(stripBlockquotePrefix(candidate))
                    index += 1
                }
                let quoteBody = quoteLines.joined(separator: "\n")
                if quoteBody.isEmpty == false {
                    blocks.append(MarkdownBlock(kind: .blockquote(quoteBody)))
                }
                continue
            }

            if let firstItem = unorderedListItem(from: trimmed) {
                var items: [String] = [firstItem]
                index += 1

                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = unorderedListItem(from: candidate) else { break }
                    items.append(item)
                    index += 1
                }

                blocks.append(MarkdownBlock(kind: .unorderedList(items)))
                continue
            }

            if let firstItem = orderedListItem(from: trimmed) {
                var items: [String] = [firstItem]
                index += 1

                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = orderedListItem(from: candidate) else { break }
                    items.append(item)
                    index += 1
                }

                blocks.append(MarkdownBlock(kind: .orderedList(items)))
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                guard candidate.isEmpty == false else { break }
                guard isMarkdownBoundaryLine(candidate) == false else { break }
                paragraphLines.append(candidate)
                index += 1
            }

            if paragraphLines.isEmpty == false {
                blocks.append(MarkdownBlock(kind: .paragraph(paragraphLines.joined(separator: "\n"))))
                continue
            }

            index += 1
        }

        if blocks.isEmpty {
            let fallback = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if fallback.isEmpty == false {
                return [MarkdownBlock(kind: .paragraph(fallback))]
            }
        }

        return blocks
    }

    private func isMarkdownBoundaryLine(_ line: String) -> Bool {
        if isThematicBreak(line) {
            return true
        }
        if headingInfo(for: line) != nil {
            return true
        }
        if line.hasPrefix(">") {
            return true
        }
        if unorderedListItem(from: line) != nil {
            return true
        }
        if orderedListItem(from: line) != nil {
            return true
        }
        return false
    }

    private func headingInfo(for line: String) -> (level: Int, text: String)? {
        var level = 0
        for char in line {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }

        guard (1...6).contains(level) else { return nil }

        let markerEnd = line.index(line.startIndex, offsetBy: level)
        guard markerEnd < line.endIndex else { return nil }
        guard line[markerEnd] == " " else { return nil }

        let textStart = line.index(after: markerEnd)
        guard textStart <= line.endIndex else { return nil }

        let headingText = String(line[textStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard headingText.isEmpty == false else { return nil }

        return (level, headingText)
    }

    private func stripBlockquotePrefix(_ line: String) -> String {
        guard let marker = line.firstIndex(of: ">") else {
            return line
        }

        var contentStart = line.index(after: marker)
        if contentStart < line.endIndex, line[contentStart] == " " {
            contentStart = line.index(after: contentStart)
        }

        guard contentStart <= line.endIndex else { return "" }
        return String(line[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func unorderedListItem(from line: String) -> String? {
        guard let first = line.first, first == "-" || first == "*" || first == "+" else {
            return nil
        }

        let afterMarker = line.index(after: line.startIndex)
        guard afterMarker < line.endIndex, line[afterMarker] == " " else {
            return nil
        }

        let contentStart = line.index(after: afterMarker)
        guard contentStart <= line.endIndex else {
            return nil
        }

        let content = String(line[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private func orderedListItem(from line: String) -> String? {
        let characters = Array(line)
        var digitCount = 0

        while digitCount < characters.count, characters[digitCount].isNumber {
            digitCount += 1
        }

        guard digitCount > 0 else { return nil }
        guard digitCount + 1 < characters.count else { return nil }
        guard characters[digitCount] == ".", characters[digitCount + 1] == " " else { return nil }

        let contentStart = line.index(line.startIndex, offsetBy: digitCount + 2)
        guard contentStart <= line.endIndex else { return nil }

        let content = String(line[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        guard let marker = compact.first, marker == "-" || marker == "*" || marker == "_" else {
            return false
        }
        return compact.allSatisfy { $0 == marker }
    }

    private func messageSegments(for content: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var buffer: [String] = []
        var inCodeBlock = false
        var codeLanguage: String?

        func flushText() {
            guard buffer.isEmpty == false else { return }
            let text = buffer.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else {
                buffer = []
                return
            }
            segments.append(MessageSegment(kind: .text(text)))
            buffer = []
        }

        func flushCode() {
            guard buffer.isEmpty == false else { return }
            let code = buffer.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            guard code.isEmpty == false else {
                buffer = []
                return
            }
            segments.append(MessageSegment(kind: .code(language: codeLanguage, body: code)))
            buffer = []
        }

        for line in content.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    flushCode()
                    inCodeBlock = false
                    codeLanguage = nil
                } else {
                    flushText()
                    inCodeBlock = true
                    let tag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLanguage = tag.isEmpty ? nil : tag.lowercased()
                }
            } else {
                buffer.append(line)
            }
        }

        if inCodeBlock {
            flushCode()
        } else {
            flushText()
        }

        if segments.isEmpty {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                if isDiffSnippet(text: trimmed, language: nil) {
                    return [MessageSegment(kind: .code(language: "diff", body: trimmed))]
                }
                return [MessageSegment(kind: .text(trimmed))]
            }
        }

        if segments.count == 1,
           case let .text(text) = segments[0].kind,
           isDiffSnippet(text: text, language: nil) {
            return [MessageSegment(kind: .code(language: "diff", body: text))]
        }

        return segments
    }

    private func isDiffSnippet(text: String, language: String?) -> Bool {
        if let language {
            let lower = language.lowercased()
            if lower == "diff" || lower == "patch" {
                return true
            }
        }

        let lines = text.components(separatedBy: .newlines)
        let markers = lines.filter { line in
            line.hasPrefix("@@") || line.hasPrefix("+++ ") || line.hasPrefix("--- ")
                || line.hasPrefix("+") || line.hasPrefix("-")
        }

        if markers.count >= 3 && (text.contains("@@") || text.contains("+++ ") || text.contains("--- ")) {
            return true
        }

        return false
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case blockquote(String)
        case unorderedList([String])
        case orderedList([String])
        case thematicBreak
    }

    let id = UUID()
    let kind: Kind
}

private struct MarkdownBlockListView: View {
    let blocks: [MarkdownBlock]
    let basePointSize: CGFloat
    let lineSpacing: CGFloat
    let textColor: Color
    let secondaryTextColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: max(6, basePointSize * 0.33)) {
            ForEach(blocks) { block in
                switch block.kind {
                case let .heading(level, text):
                    MarkdownInlineTextView(
                        markdown: text,
                        font: headingFont(for: level),
                        lineSpacing: lineSpacing,
                        foregroundColor: textColor
                    )
                case let .paragraph(text):
                    MarkdownInlineTextView(
                        markdown: text,
                        font: bodyFont,
                        lineSpacing: lineSpacing,
                        foregroundColor: textColor
                    )
                case let .blockquote(text):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(secondaryTextColor.opacity(0.7))
                            .frame(width: 3)
                        MarkdownInlineTextView(
                            markdown: text,
                            font: bodyFont,
                            lineSpacing: lineSpacing,
                            foregroundColor: textColor
                        )
                    }
                case let .unorderedList(items):
                    listView(items: items, ordered: false)
                case let .orderedList(items):
                    listView(items: items, ordered: true)
                case .thematicBreak:
                    Rectangle()
                        .fill(secondaryTextColor.opacity(0.65))
                        .frame(height: 1)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func listView(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: max(4, basePointSize * 0.24)) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: basePointSize * 0.95, weight: .semibold, design: .rounded))
                        .foregroundStyle(secondaryTextColor)
                        .frame(minWidth: 20, alignment: .leading)

                    MarkdownInlineTextView(
                        markdown: item,
                        font: bodyFont,
                        lineSpacing: lineSpacing,
                        foregroundColor: textColor
                    )
                }
            }
        }
    }

    private var bodyFont: Font {
        .system(size: basePointSize, weight: .regular, design: .rounded)
    }

    private func headingFont(for level: Int) -> Font {
        let clamped = max(1, min(6, level))
        let ratios: [CGFloat] = [1.28, 1.18, 1.08, 1.0, 0.95, 0.9]
        let size = basePointSize * ratios[clamped - 1]
        let weight: Font.Weight = clamped == 1 ? .bold : .semibold
        return .system(size: size, weight: weight, design: .rounded)
    }
}

private struct MarkdownInlineTextView: View {
    let markdown: String
    let font: Font
    let lineSpacing: CGFloat
    let foregroundColor: Color

    var body: some View {
        Group {
            if let parsed {
                Text(parsed)
            } else {
                Text(markdown)
            }
        }
        .font(font)
        .lineSpacing(lineSpacing)
        .foregroundStyle(foregroundColor)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var parsed: AttributedString? {
        do {
            return try AttributedString(
                markdown: markdown,
                options: .init(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return nil
        }
    }
}

private struct MessageSegment: Identifiable {
    enum Kind {
        case text(String)
        case code(language: String?, body: String)
    }

    let id = UUID()
    let kind: Kind
}

private struct CodeSnippetView: View {
    let text: String
    let language: String?
    let font: Font
    let isAssistantBubble: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, language.isEmpty == false {
                Text(language.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(isAssistantBubble ? .secondary : Color.white.opacity(0.8))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: text)
                    .font(font)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isAssistantBubble ? Color.black.opacity(0.06) : Color.white.opacity(0.16))
                    )
            }
        }
    }
}

private struct DiffSnippetView: View {
    let diffText: String
    let font: Font
    let isAssistantBubble: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DIFF")
                .font(.caption2.monospaced())
                .foregroundStyle(isAssistantBubble ? .secondary : Color.white.opacity(0.85))

            ForEach(Array(diffText.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let style = styleForLine(line)
                Text(verbatim: line.isEmpty ? " " : line)
                    .font(font)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(style.background)
                    )
                    .foregroundStyle(style.foreground)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isAssistantBubble ? Color.black.opacity(0.05) : Color.white.opacity(0.12))
        )
    }

    private func styleForLine(_ line: String) -> (foreground: Color, background: Color) {
        if line.hasPrefix("@@") {
            return (Color.orange, Color.orange.opacity(0.16))
        }
        if line.hasPrefix("+"), line.hasPrefix("+++") == false {
            return (Color.green, Color.green.opacity(0.14))
        }
        if line.hasPrefix("-"), line.hasPrefix("---") == false {
            return (Color.red, Color.red.opacity(0.14))
        }
        if line.hasPrefix("+++ ") || line.hasPrefix("--- ") {
            return (Color.blue, Color.blue.opacity(0.12))
        }
        return (Color.secondary, Color.secondary.opacity(0.08))
    }
}

private extension String {
    var trimmedForSend: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ContentView(viewModel: ChatViewModel())
}
