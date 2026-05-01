import SwiftUI
import SwiftData
import PodedgeCore

/// Two-column NavigationSplitView with sidebar tabs and context-dependent content.
struct MainWindowView: View {
    /// Which sidebar tab is active.
    enum SidebarTab: String, CaseIterable {
        case shows = "Shows"
        case episodes = "Episodes"
    }

    @State private var sidebarTab: SidebarTab = .shows
    @State private var selectedShowID: PersistentIdentifier?
    @State private var selectedEpisodeID: PersistentIdentifier?
    @State private var chatText = ""
    @FocusState private var chatFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                detailContent
                Divider()
                chatBar
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        .frame(minWidth: 800, minHeight: 500)
        .keyboardShortcut("k", modifiers: .command)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            switch sidebarTab {
            case .shows:
                ShowListView(selectedShowID: $selectedShowID, selectedEpisodeID: $selectedEpisodeID)
            case .episodes:
                EpisodeListView(selectedShowID: selectedShowID, selectedEpisodeID: $selectedEpisodeID)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let episodeID = selectedEpisodeID {
            EpisodeEditorView(episodeID: episodeID)
        } else if let showID = selectedShowID {
            ShowEditorView(showID: showID)
        } else {
            DashboardView()
        }
    }

    // MARK: - Chat Bar (Placeholder for WS9)

    private var chatBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .foregroundStyle(.secondary)
            TextField("Ask Podedge… (⌘K)", text: $chatText)
                .textFieldStyle(.plain)
                .focused($chatFocused)
                .onSubmit { /* WS9: send to agent */ }
                .accessibilityLabel("Chat input")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
