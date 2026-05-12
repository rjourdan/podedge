import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os
import PodedgeCore

/// Sidebar list of episodes for the selected show, with status dots and drag-drop MP3 import.
struct EpisodeListView: View {
    let selectedShowID: PersistentIdentifier?
    @Binding var selectedEpisodeID: PersistentIdentifier?

    @Query(sort: \Episode.createdAt, order: .reverse) private var allEpisodes: [Episode]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices

    @State private var isDropTargeted = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var ingestError: Error?
    @State private var showingIngestError = false

    /// Episodes filtered to the selected show.
    private var episodes: [Episode] {
        guard let showID = selectedShowID else { return [] }
        return allEpisodes.filter { $0.show?.persistentModelID == showID }
    }

    var body: some View {
        List(selection: $selectedEpisodeID) {
            ForEach(episodes) { episode in
                EpisodeRow(episode: episode)
                    .tag(episode.persistentModelID)
            }
            .onDelete { offsets in
                pendingDeleteOffsets = offsets
                showingDeleteConfirmation = true
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if selectedShowID == nil {
                ContentUnavailableView("Select a Show", systemImage: "sidebar.left", description: Text("Choose a show from the Shows tab to see its episodes."))
            } else if episodes.isEmpty {
                ContentUnavailableView("No Episodes", systemImage: "waveform", description: Text("Drop an MP3 file here to create an episode."))
            }
        }
        .onDrop(of: [.mp3, .mpeg4Audio, .audio], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .border(isDropTargeted ? Color.accentColor : Color.clear, width: 2)
        .alert("Delete Episode?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    for index in offsets {
                        modelContext.delete(episodes[index])
                    }
                }
                pendingDeleteOffsets = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteOffsets = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Import Failed", isPresented: $showingIngestError) {
            Button("OK", role: .cancel) { ingestError = nil }
        } message: {
            Text(ingestError?.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard selectedShowID != nil else { return false }
        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, error in
                guard let url, error == nil else { return }
                // Copy to a temp location we own (the callback URL is ephemeral).
                let tempCopy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: tempCopy)

                Task { @MainActor in
                    importAudio(from: tempCopy)
                }
            }
        }
        return true
    }

    /// Ingests a dropped audio file via `IngestService`, creating an episode with follow-up jobs.
    private func importAudio(from tempURL: URL) {
        guard let showID = selectedShowID,
              let services = appServices else { return }
        guard let show = modelContext.model(for: showID) as? Show else { return }
        Task { @MainActor in
            do {
                let episode = try await services.ingestService.ingest(fileURL: tempURL, show: show)
                selectedEpisodeID = episode.persistentModelID
            } catch {
                ingestError = error
                showingIngestError = true
            }
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}

// MARK: - Episode Row

private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: episode.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let number = episode.number {
                        Text("Ep. \(number)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(episode.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                // Inline play — AVAudioPlayer integration placeholder
            } label: {
                Image(systemName: "play.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(episode.title)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(episode.title), \(episode.status.rawValue)")
    }
}
