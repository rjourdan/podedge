import SwiftUI
import PodedgeCore

/// Reusable button that invokes a named tool through ``ToolBroker``.
///
/// Handles the `.needsConfirmation` result by routing to ``ConfirmationCoordinator``.
struct ToolButton: View {
    let title: String
    let toolName: String
    let input: @Sendable () -> Data
    let broker: ToolBroker
    let caller: any ToolCaller
    var systemImage: String? = nil

    @Environment(ConfirmationCoordinator.self) private var coordinator
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await invoke() }
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .disabled(isRunning)
        .accessibilityLabel(title)
        .popover(isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Text(errorMessage ?? "")
                .padding()
                .frame(maxWidth: 280)
        }
    }

    private func invoke() async {
        isRunning = true
        defer { isRunning = false }

        let result = await broker.invoke(
            toolNamed: toolName,
            input: input(),
            caller: caller
        )

        switch result {
        case .success:
            break
        case .failure(let message):
            errorMessage = message
        case .needsConfirmation(let name, let data):
            coordinator.requestConfirmation(
                toolName: name,
                input: data,
                broker: broker,
                caller: caller
            )
        }
    }
}
