import Foundation

/// Mediates tool invocations, enforcing capability tiers and requiring
/// confirmation for destructive operations.
public actor ToolBroker {
    private let registry: ToolRegistry
    private let auditLog: AuditLogService?

    /// Creates a broker backed by the given registry.
    ///
    /// - Parameters:
    ///   - registry: The tool registry to look up tools.
    ///   - auditLog: Optional audit log service for recording invocations.
    public init(registry: ToolRegistry, auditLog: AuditLogService? = nil) {
        self.registry = registry
        self.auditLog = auditLog
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
        let start = ContinuousClock.now
        do {
            let output = try await tool.execute(input: input)
            let duration = start.duration(to: .now)
            await recordAudit(
                caller: caller, tool: tool, input: input,
                outputSummary: Self.truncate(output),
                duration: duration, success: true
            )
            return .success(output)
        } catch {
            let duration = start.duration(to: .now)
            await recordAudit(
                caller: caller, tool: tool, input: input,
                outputSummary: error.localizedDescription,
                duration: duration, success: false
            )
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
        let start = ContinuousClock.now
        do {
            let output = try await tool.execute(input: input)
            let duration = start.duration(to: .now)
            await recordAudit(
                caller: caller, tool: tool, input: input,
                outputSummary: Self.truncate(output),
                duration: duration, success: true
            )
            return .success(output)
        } catch {
            let duration = start.duration(to: .now)
            await recordAudit(
                caller: caller, tool: tool, input: input,
                outputSummary: error.localizedDescription,
                duration: duration, success: false
            )
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

    /// Records an audit entry via the MainActor-isolated audit log service.
    private func recordAudit(
        caller: any ToolCaller,
        tool: any ToolDefinition,
        input: Data,
        outputSummary: String,
        duration: Duration,
        success: Bool
    ) async {
        guard let auditLog else { return }
        let agentName = String(describing: caller)
        let toolName = tool.name
        let scope = tool.scope
        let inputSummary = Self.truncate(input)
        let durationSeconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        await MainActor.run {
            auditLog.log(
                agentName: agentName,
                toolName: toolName,
                scope: scope,
                inputSummary: inputSummary,
                outputSummary: outputSummary,
                durationSeconds: durationSeconds,
                success: success
            )
        }
    }

    /// Returns the first 200 characters of the UTF-8 representation of `data`.
    nonisolated private static func truncate(_ data: Data) -> String {
        let str = String(decoding: data, as: UTF8.self)
        return str.count <= 200 ? str : String(str.prefix(200))
    }
}
