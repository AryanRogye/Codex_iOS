import SwiftUI

struct AppNavigationView: View {
    enum Tab: Hashable {
        case home
        case chats
        case settings
    }

    @State private var selectedTab: Tab = .home
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            AppHomeView(selectedTab: $selectedTab)
                .tag(Tab.home)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            ContentView(viewModel: viewModel)
                .tag(Tab.chats)
                .tabItem {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                }

            AppSettingsView(viewModel: viewModel)
                .tag(Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

private struct AppHomeView: View {
    @Binding var selectedTab: AppNavigationView.Tab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    quickActions
                    tipsCard
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Home")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Codex Relay", systemImage: "bolt.horizontal.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)

            Text("Continue desktop sessions from iOS and manage relay behavior in one place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                selectedTab = .chats
            } label: {
                Label("Open Chats", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)

            Button {
                selectedTab = .chats
            } label: {
                Label("Start or resume a chat", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                selectedTab = .settings
            } label: {
                Label("Configure relay options", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Navigation")
                .font(.headline)

            Text("Use Home for entry, Chats for sessions, and Settings for relay controls.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct AppSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Relay") {
                    NavigationLink {
                        RelayOptionsView(viewModel: viewModel, showsDoneButton: false)
                    } label: {
                        Label("Relay Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    AppNavigationView()
}
