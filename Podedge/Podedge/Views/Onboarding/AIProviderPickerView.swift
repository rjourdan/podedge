import SwiftUI
import PodedgeCore

/// Presents AI provider options during onboarding: 3 MLX models + Ollama.
struct AIProviderPickerView: View {
    @Environment(\.appServices) private var appServices
    @Binding var isComplete: Bool

    @State private var selectedOption: ProviderOption?
    @State private var downloadProgress: Double?
    @State private var ollamaModels: [OllamaModelInfo] = []
    @State private var selectedOllamaModel: String = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private enum ProviderOption: String, CaseIterable {
        case gemma = "mlx-community/gemma-4-e4b-it-4bit-MAD"
        case qwen = "mlx-community/Qwen3-8B-4bit-DWQ-053125"
        case mistral = "mlx-community/Mistral-Small-24B-Instruct-2501-4bit"
        case ollama = "ollama"

        var displayName: String {
            switch self {
            case .gemma: "Gemma 4 E4B Instruct (4-bit)"
            case .qwen: "Qwen 3 8B (4-bit DWQ)"
            case .mistral: "Mistral Small 24B Instruct 2501 (4-bit)"
            case .ollama: "Ollama (advanced)"
            }
        }

        var guidance: String {
            switch self {
            case .gemma: "Fast and compact. Good for quick drafts. Works on any Apple Silicon Mac."
            case .qwen: "Balanced speed and reliability. Strong tool-use. Recommended for 16 GB+ Macs."
            case .mistral: "Most capable option. Best tool-use and Publish Assistant reliability. Requires 24 GB+ Mac."
            case .ollama: "Use a model you already have in Ollama. Runs as a separate local service. Requires `ollama serve` on localhost:11434."
            }
        }

        var sizeLabel: String? {
            switch self {
            case .gemma: "~2.5 GB"
            case .qwen: "~4.5 GB"
            case .mistral: "~14 GB"
            case .ollama: nil
            }
        }

        var isMLX: Bool { self != .ollama }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Choose a local AI model for metadata generation and the Assistant.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(ProviderOption.allCases, id: \.rawValue) { option in
                optionRow(option)
            }

            if selectedOption == .ollama {
                ollamaSection
            }

            if let progress = downloadProgress {
                ProgressView(value: progress)
                    .padding(.top, 4)
            }
        }
    }

    private func optionRow(_ option: ProviderOption) -> some View {
        Button {
            selectedOption = option
            if option.isMLX {
                startMLXDownload(option)
            } else {
                fetchOllamaModels()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(option.displayName).font(.callout)
                        if let size = option.sizeLabel {
                            Text(size).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Text(option.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedOption == option {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(8)
            .background(selectedOption == option ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ollamaModels.isEmpty && !isLoading {
                Text("Start Ollama with `ollama serve` and click Retry.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Retry") { fetchOllamaModels() }
                    .controlSize(.small)
            } else if !ollamaModels.isEmpty {
                Picker("Model", selection: $selectedOllamaModel) {
                    ForEach(ollamaModels, id: \.name) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .onChange(of: selectedOllamaModel) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    saveSelection(activeID: "ollama", modelID: newValue)
                }
            }
        }
        .padding(.leading, 16)
    }

    private func startMLXDownload(_ option: ProviderOption) {
        guard let appServices else { return }
        isLoading = true
        errorMessage = nil
        downloadProgress = 0
        Task { @MainActor in
            do {
                try await appServices.modelManager.downloadLLMModel(named: option.rawValue) { fraction in
                    Task { @MainActor in downloadProgress = fraction }
                }
                downloadProgress = nil
                saveSelection(activeID: "mlx", modelID: option.rawValue)
            } catch {
                errorMessage = error.localizedDescription
                downloadProgress = nil
            }
            isLoading = false
        }
    }

    private func fetchOllamaModels() {
        guard let appServices else { return }
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                ollamaModels = try await appServices.modelManager.availableOllamaModels()
                if let first = ollamaModels.first {
                    selectedOllamaModel = first.name
                    saveSelection(activeID: "ollama", modelID: first.name)
                }
            } catch {
                errorMessage = "Ollama is not running. Start it with `ollama serve` and try again."
                ollamaModels = []
            }
            isLoading = false
        }
    }

    private func saveSelection(activeID: String, modelID: String) {
        UserDefaults.standard.set(activeID, forKey: "llm.provider.activeID")
        UserDefaults.standard.set(modelID, forKey: "llm.provider.modelID")
        isComplete = true
    }
}
