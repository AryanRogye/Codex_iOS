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
                TextField("Relay URL (ex: http://192.168.1.20:8787)", text: $viewModel.relayURLText)
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
                Button("Save") {
                    dismissKeyboard()
                    viewModel.saveSettings()
                }

                Button("Test") {
                    dismissKeyboard()
                    Task { await viewModel.testConnection() }
                }

                Button("Sync Sessions") {
                    dismissKeyboard()
                    Task { await viewModel.refreshThreads() }
                }
            }

            Section("Status") {
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
}

#Preview {
    NavigationStack {
        RelayOptionsView(viewModel: ChatViewModel(), showsDoneButton: false)
    }
}
