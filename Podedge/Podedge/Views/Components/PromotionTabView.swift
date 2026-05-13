import SwiftUI
import SwiftData
import PodedgeCore

/// Promotion tab within the episode editor — generates social media blurbs.
struct PromotionTabView: View {
    let episode: Episode

    @Query private var allSuggestions: [EpisodeSuggestions]
    @Environment(\.appServices) private var appServices

    @State private var selectedPlatform = "x"
    @State private var generatedText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private let platforms = [
        ("x", "X (Twitter)", 280),
        ("bluesky", "Bluesky", 300),
        ("mastodon", "Mastodon", 500),
        ("threads", "Threads", 500),
        ("linkedin", "LinkedIn", 3000),
    ]

    /// Returns the suggestions matching this episode, if any exist.
    private var suggestions: EpisodeSuggestions? {
        allSuggestions.first { $0.episodeID == episode.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Social Promotion")
                .font(.headline)

            Picker("Platform", selection: $selectedPlatform) {
                ForEach(platforms, id: \.0) { platform in
                    Text(platform.1).tag(platform.0)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Social media platform")

            if isGenerating {
                ProgressView("Generating blurb…")
            } else {
                TextEditor(text: $generatedText)
                    .frame(minHeight: 120)
                    .border(.separator)
                    .accessibilityLabel("Generated social media text")

                if let limit = platforms.first(where: { $0.0 == selectedPlatform })?.2 {
                    HStack {
                        Text("\(generatedText.count)/\(limit) characters")
                            .font(.caption)
                            .foregroundStyle(generatedText.count > limit ? .red : .secondary)
                        Spacer()
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Generate Blurb") {
                    if let suggestions {
                        generatedText = blurb(for: selectedPlatform, from: suggestions)
                    } else {
                        // TODO: Route through ToolBroker once Spec 08 (Tool Registry Wiring) is complete.
                        Task {
                            guard let services = appServices else { return }
                            let job = Job(kind: .generateMetadata, targetID: episode.id)
                            let context = services.modelContainer.mainContext
                            context.insert(job)
                            try? context.save()
                        }
                    }
                }
                .disabled(isGenerating)
                .accessibilityLabel("Generate social media blurb")

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generatedText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(generatedText.isEmpty)
                .accessibilityLabel("Copy blurb to clipboard")
            }
        }
        .padding()
        .onChange(of: selectedPlatform) { _, newValue in
            if let suggestions {
                generatedText = blurb(for: newValue, from: suggestions)
            }
        }
        .onAppear {
            if generatedText.isEmpty, let suggestions {
                generatedText = blurb(for: selectedPlatform, from: suggestions)
            }
        }
    }

    // MARK: - Helpers

    private func blurb(for platform: String, from suggestions: EpisodeSuggestions) -> String {
        switch platform {
        case "x": return suggestions.blurbTwitter
        case "bluesky": return suggestions.blurbBluesky
        case "mastodon": return suggestions.blurbMastodon
        case "threads": return suggestions.blurbThreads
        case "linkedin": return suggestions.blurbLinkedIn
        default: return ""
        }
    }
}
