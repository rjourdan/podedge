import Foundation

/// Central registration point for tools available to the assistant.
public actor ToolRegistry {
    private var tools: [String: any ToolDefinition] = [:]

    public init() {}

    /// Registers a tool. Replaces any existing tool with the same name.
    public func register(_ tool: any ToolDefinition) {
        tools[tool.name] = tool
    }

    /// Removes the tool with the given name, if present.
    @discardableResult
    public func unregister(named name: String) -> Bool {
        tools.removeValue(forKey: name) != nil
    }

    /// Returns the tool with the given name, or `nil` if not registered.
    public func tool(named name: String) -> (any ToolDefinition)? {
        tools[name]
    }

    /// Returns all registered tools.
    public func allTools() -> [any ToolDefinition] {
        Array(tools.values)
    }

    /// Returns tools matching the given scope.
    public func tools(withScope scope: ToolScope) -> [any ToolDefinition] {
        tools.values.filter { $0.scope == scope }
    }

    /// Returns tools accessible at the given capability tier.
    public func tools(availableTo tier: CapabilityTier) -> [any ToolDefinition] {
        tools.values.filter { $0.requiredTier <= tier }
    }
}
