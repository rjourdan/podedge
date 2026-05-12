import Foundation

/// Mediates tool invocations, enforcing capability tiers and requiring
/// confirmation for destructive operations.
public actor ToolBroker {
    private let registry: ToolRegistry

    /// Creates a broker backed by the given registry.
    public init(registry: ToolRegistry) {
        self.registry = registry
    }

    /// Returns tools the caller is permitted to invoke.
    public func availableTools(for caller: any ToolCaller) async -> [any ToolDefinition] {
        await registry.tools(availableTo: caller.capabilityTier)
    }

    /// Invokes a tool by name on behalf of a caller.
    ///
    /// - Returns: A ``ToolResult`` indicating success, failure, or that
    ///   user confirmation is required (for destructive tools).
    public func invoke(
        toolNamed name: String,
        input: Data,
        caller: any ToolCaller
    ) async -> ToolResult {
        guard let tool = await resolveTool(named: name, caller: caller) else {
            return resolveFailure
        }
        if tool.scope == .destructive {
            return .needsConfirmation(toolName: name, input: input)
        }
        do {
            let output = try await tool.execute(input: input)
            return .success(output)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Executes a destructive tool after the caller has confirmed.
    ///
    /// Bypasses the confirmation gate but still enforces tier checks.
    public func invokeConfirmed(
        toolNamed name: String,
        input: Data,
        caller: any ToolCaller
    ) async -> ToolResult {
        guard let tool = await resolveTool(named: name, caller: caller) else {
            return resolveFailure
        }
        guard tool.scope == .destructive else {
            return .failure("Only destructive tools require confirmation")
        }
        do {
            let output = try await tool.execute(input: input)
            return .success(output)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Private

    /// Cached failure message from the last failed ``resolveTool(named:caller:)`` call.
    ///
    /// This avoids returning a tuple from the resolve helper while keeping
    /// the actor-isolated state simple.
    private var resolveFailure: ToolResult = .failure("Unknown error")

    /// Looks up a tool by name and verifies the caller's tier is sufficient.
    ///
    /// Returns the tool on success, or `nil` on failure (with ``resolveFailure`` set).
    private func resolveTool(
        named name: String,
        caller: any ToolCaller
    ) async -> (any ToolDefinition)? {
        guard let tool = await registry.tool(named: name) else {
            resolveFailure = .failure(
                PodedgeError.notFound(entity: "Tool", id: name).localizedDescription
            )
            return nil
        }
        guard tool.requiredTier <= caller.capabilityTier else {
            resolveFailure = .failure(
                PodedgeError.preconditionViolated(
                    reason: "Caller tier \(caller.capabilityTier) insufficient for tool '\(name)' requiring \(tool.requiredTier)"
                ).localizedDescription
            )
            return nil
        }
        return tool
    }
}
