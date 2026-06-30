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
    @AppStorage("assistantPaneVisible") private var paneVisible = true
    @Environment(\.openSettings) private var openSettings
    @Environment(\.appServices) private var appServices

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if paneVisible {
                    Divider()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Assistant")
                                .font(.headline)
                            Spacer()
                            Button {
                                paneVisible = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hide assistant pane")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider()
                        AssistantPaneView()
                    }
                    .frame(width: 320)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    paneVisible.toggle()
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                .accessibilityLabel("Toggle assistant pane")
            }
        }
        .background {
            Button("") { activateAssistant() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
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

    // MARK: - Assistant Activation

    private func activateAssistant() {
        if paneVisible {
            // Already visible — start fresh conversation per spec
            appServices?.assistantController.reset()
        }
        paneVisible = true
        NotificationCenter.default.post(name: .focusAssistantInput, object: nil)
    }
}
