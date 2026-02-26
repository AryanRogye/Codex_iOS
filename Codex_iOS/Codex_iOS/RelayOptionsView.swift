import SwiftUI

struct RelayOptionsView: View {
    @ObservedObject var viewModel: ChatViewModel
    let showsDoneButton: Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case relayURL
        case relayToken
        case model
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Relay URL (ex: https://192.168.1.20:8787)", text: $viewModel.relayURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .relayURL)
                    .onSubmit {
                        dismissKeyboard()
                    }

                SecureField("Relay token", text: $viewModel.relayToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .relayToken)
                    .onSubmit {
                        dismissKeyboard()
                    }

                TextField("Model (optional)", text: $viewModel.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .model)
                    .onSubmit {
                        dismissKeyboard()
                    }
            }

            Section("Actions") {
                relayActionButton(
                    title: "Save Settings",
                    subtitle: "Persist relay URL, token, and model",
                    systemImage: "square.and.arrow.down",
                    tint: .blue,
                    isLoading: false
                ) {
                    dismissKeyboard()
                    viewModel.saveSettings()
                }

                relayActionButton(
                    title: "Test Connection",
                    subtitle: "Check if relay is reachable",
                    systemImage: "bolt.horizontal.circle.fill",
                    tint: .orange,
                    isLoading: viewModel.isTestingConnection
                ) {
                    dismissKeyboard()
                    Task { await viewModel.testConnection() }
                }
                .disabled(viewModel.isTestingConnection || viewModel.isSyncingSessions)

                relayActionButton(
                    title: "Sync Sessions",
                    subtitle: "Refresh sessions from relay",
                    systemImage: "arrow.clockwise.circle.fill",
                    tint: .green,
                    isLoading: viewModel.isSyncingSessions
                ) {
                    dismissKeyboard()
                    Task { await viewModel.refreshThreads() }
                }
                .disabled(viewModel.isTestingConnection || viewModel.isSyncingSessions)
            }

            Section("Status") {
                if viewModel.isTestingConnection || viewModel.isSyncingSessions {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            viewModel.isTestingConnection
                                ? "Testing relay connection..."
                                : "Syncing relay sessions..."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let error = viewModel.errorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Relay Settings")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismissKeyboard()
                        dismiss()
                    }
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
            }
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func relayActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .tint(tint)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        RelayOptionsView(viewModel: ChatViewModel(), showsDoneButton: false)
    }
}
