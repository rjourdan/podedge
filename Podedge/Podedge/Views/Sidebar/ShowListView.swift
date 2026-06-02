import SwiftUI
import SwiftData
import PodedgeCore

/// Sidebar list of all shows with add/delete support.
struct ShowListView: View {
    @Binding var selectedShowID: PersistentIdentifier?
    @Binding var selectedEpisodeID: PersistentIdentifier?

    @Query(sort: \Show.title) private var shows: [Show]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices

    @State private var showingNewShowSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteOffsets: IndexSet?

    var body: some View {
        List(selection: $selectedShowID) {
            ForEach(shows) { show in
                ShowRow(show: show)
                    .tag(show.persistentModelID)
            }
            .onDelete { offsets in
                pendingDeleteOffsets = offsets
                showingDeleteConfirmation = true
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if shows.isEmpty {
                ContentUnavailableView("No Shows", systemImage: "mic.fill", description: Text("Create your first show to get started."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewShowSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New show")
            }
        }
        .sheet(isPresented: $showingNewShowSheet) {
            NewShowSheet()
        }
        .onChange(of: selectedShowID) {
            selectedEpisodeID = nil
        }
        .alert("Delete Show?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeleteOffsets, let services = appServices {
                    for index in offsets {
                        let showID = shows[index].id
                        let input = (try? JSONEncoder().encode(["showID": showID.uuidString])) ?? Data()
                        Task {
                            _ = await services.toolBroker.invokeConfirmed(
                                toolNamed: "show.delete",
                                input: input,
                                caller: AppCaller()
                            )
                        }
                    }
                }
                pendingDeleteOffsets = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteOffsets = nil
            }
        } message: {
            Text("This will delete the show and all its episodes. This action cannot be undone.")
        }
    }
}

// MARK: - Show Row

private struct ShowRow: View {
    let show: Show

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(show.title)
                .font(.body)
                .lineLimit(1)
            Text("\(show.episodes.count) episode\(show.episodes.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(show.title), \(show.episodes.count) episodes")
    }
}

// MARK: - New Show Sheet

private struct NewShowSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var author = ""
    @State private var summary = ""
    @State private var category = "Technology"
    @State private var ownerEmail = ""
    @State private var ownerName = ""

    var body: some View {
        Form {
            Section("Show Details") {
                TextField("Title", text: $title)
                TextField("Author", text: $author)
                TextField("Category", text: $category)
                TextField("Summary", text: $summary, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Owner") {
                TextField("Name", text: $ownerName)
                TextField("Email", text: $ownerEmail)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { createShow() }
                    .disabled(title.isEmpty || author.isEmpty)
            }
        }
    }

    private func createShow() {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let show = Show(
            title: title,
            author: author,
            summary: summary,
            category: category,
            ownerEmail: ownerEmail,
            ownerName: ownerName,
            hostBindingID: UUID(),
            feedRemotePath: "shows/\(slug)/feed.xml"
        )
        modelContext.insert(show)
        dismiss()
    }
}
