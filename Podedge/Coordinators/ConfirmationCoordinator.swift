import Foundation
import Observation
import PodedgeCore

/// Bridges PodedgeCore's `.needsConfirmation` tool result to a SwiftUI confirmation sheet.
///
/// When ``ToolBroker`` returns `.needsConfirmation`, the UI sets ``pendingConfirmation``,
/// which triggers a sheet. On approval, ``confirm()`` calls ``ToolBroker/invokeConfirmed``.
@Observable
@MainActor
final class ConfirmationCoordinator {

    /// The pending confirmation item, presented as a sheet when non-nil.
    var pendingConfirmation: ConfirmationItem?

    /// The broker to call back on confirmation.
    private var broker: ToolBroker?

    /// The caller identity for the confirmed invocation.
    private var caller: (any ToolCaller & Sendable)?

    /// Presents a confirmation sheet for a destructive tool invocation.
    ///
    /// - Parameters:
    ///   - toolName: The name of the destructive tool.
    ///   - input: The JSON-encoded input for the tool.
    ///   - broker: The broker to invoke on confirmation.
    ///   - caller: The caller identity.
    func requestConfirmation(
        toolName: String,
        input: Data,
        broker: ToolBroker,
        caller: any ToolCaller & Sendable
    ) {
        self.broker = broker
        self.caller = caller
        pendingConfirmation = ConfirmationItem(toolName: toolName, input: input)
    }

    /// Confirms the pending action and invokes the tool.
    func confirm() async {
        guard let item = pendingConfirmation,
              let broker, let caller else { return }
        pendingConfirmation = nil
        _ = await broker.invokeConfirmed(
            toolNamed: item.toolName,
            input: item.input,
            caller: caller
        )
        self.broker = nil
        self.caller = nil
    }

    /// Cancels the pending confirmation without invoking the tool.
    func cancel() {
        pendingConfirmation = nil
        broker = nil
        caller = nil
    }
}

/// Data for a pending destructive-action confirmation.
struct ConfirmationItem: Identifiable {
    let id = UUID()
    let toolName: String
    let input: Data

    /// Human-readable description of the action for the confirmation sheet.
    var displayName: String {
        toolName
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
