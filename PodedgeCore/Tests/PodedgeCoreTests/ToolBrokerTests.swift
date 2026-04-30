import Foundation
import Testing

@testable import PodedgeCore

// MARK: - Test Helpers

/// A minimal tool for testing.
struct StubTool: ToolDefinition {
    var name: String
    var description: String = "stub"
    var scope: ToolScope
    var requiredTier: CapabilityTier
    var parameterSchema: String = "{}"

    func execute(input: Data) async throws -> Data {
        Data("ok".utf8)
    }
}

/// A minimal caller for testing.
struct StubCaller: ToolCaller {
    var capabilityTier: CapabilityTier
}

// MARK: - ToolScope Tests

@Suite("ToolScope")
struct ToolScopeTests {

    @Test("Scopes are ordered readOnly < mutating < destructive")
    func ordering() {
        #expect(ToolScope.readOnly < .mutating)
        #expect(ToolScope.mutating < .destructive)
        #expect(ToolScope.readOnly < .destructive)
    }

    @Test("Equal scopes are not less-than")
    func equality() {
        #expect(!(ToolScope.readOnly < .readOnly))
        #expect(!(ToolScope.destructive < .destructive))
    }
}

// MARK: - CapabilityTier Tests

@Suite("CapabilityTier")
struct CapabilityTierTests {

    @Test("Tiers are ordered basic < standard < full")
    func ordering() {
        #expect(CapabilityTier.basic < .standard)
        #expect(CapabilityTier.standard < .full)
        #expect(CapabilityTier.basic < .full)
    }

    @Test("Basic tier cannot access full-tier tools")
    func basicCannotAccessFull() {
        #expect(CapabilityTier.basic < CapabilityTier.full)
        #expect(!(CapabilityTier.full <= CapabilityTier.basic))
    }
}

// MARK: - ToolRegistry Tests

@Suite("ToolRegistry")
struct ToolRegistryTests {

    @Test("Register and lookup by name")
    func registerAndLookup() async {
        let registry = ToolRegistry()
        let tool = StubTool(name: "list_shows", scope: .readOnly, requiredTier: .basic)
        await registry.register(tool)

        let found = await registry.tool(named: "list_shows")
        #expect(found?.name == "list_shows")
    }

    @Test("Unregister removes tool")
    func unregister() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "t1", scope: .readOnly, requiredTier: .basic))

        let removed = await registry.unregister(named: "t1")
        #expect(removed)
        #expect(await registry.tool(named: "t1") == nil)
    }

    @Test("Unregister returns false for unknown tool")
    func unregisterUnknown() async {
        let registry = ToolRegistry()
        let removed = await registry.unregister(named: "nonexistent")
        #expect(!removed)
    }

    @Test("Filter by scope")
    func filterByScope() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "read", scope: .readOnly, requiredTier: .basic))
        await registry.register(StubTool(name: "write", scope: .mutating, requiredTier: .standard))
        await registry.register(StubTool(name: "delete", scope: .destructive, requiredTier: .full))

        let readOnly = await registry.tools(withScope: .readOnly)
        #expect(readOnly.count == 1)
        #expect(readOnly.first?.name == "read")
    }

    @Test("Filter by tier")
    func filterByTier() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "basic_tool", scope: .readOnly, requiredTier: .basic))
        await registry.register(StubTool(name: "full_tool", scope: .destructive, requiredTier: .full))

        let basicTools = await registry.tools(availableTo: .basic)
        #expect(basicTools.count == 1)
        #expect(basicTools.first?.name == "basic_tool")

        let fullTools = await registry.tools(availableTo: .full)
        #expect(fullTools.count == 2)
    }

    @Test("allTools returns everything")
    func allTools() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "a", scope: .readOnly, requiredTier: .basic))
        await registry.register(StubTool(name: "b", scope: .mutating, requiredTier: .standard))

        let all = await registry.allTools()
        #expect(all.count == 2)
    }
}

// MARK: - ToolBroker Tests

@Suite("ToolBroker")
struct ToolBrokerTests {

    @Test("Broker filters tools by caller tier")
    func filtersToolsByTier() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "basic_tool", scope: .readOnly, requiredTier: .basic))
        await registry.register(StubTool(name: "full_tool", scope: .readOnly, requiredTier: .full))

        let broker = ToolBroker(registry: registry)
        let caller = StubCaller(capabilityTier: .basic)
        let available = await broker.availableTools(for: caller)

        #expect(available.count == 1)
        #expect(available.first?.name == "basic_tool")
    }

    @Test("Broker returns needsConfirmation for destructive tools")
    func destructiveNeedsConfirmation() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "delete_all", scope: .destructive, requiredTier: .full))

        let broker = ToolBroker(registry: registry)
        let caller = StubCaller(capabilityTier: .full)
        let result = await broker.invoke(toolNamed: "delete_all", input: Data(), caller: caller)

        if case .needsConfirmation(let name, _) = result {
            #expect(name == "delete_all")
        } else {
            Issue.record("Expected needsConfirmation, got \(result)")
        }
    }

    @Test("Broker executes read-only tool successfully")
    func executesReadOnly() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "list", scope: .readOnly, requiredTier: .basic))

        let broker = ToolBroker(registry: registry)
        let caller = StubCaller(capabilityTier: .basic)
        let result = await broker.invoke(toolNamed: "list", input: Data(), caller: caller)

        if case .success(let data) = result {
            #expect(String(data: data, encoding: .utf8) == "ok")
        } else {
            Issue.record("Expected success, got \(result)")
        }
    }

    @Test("Broker rejects caller with insufficient tier")
    func rejectsInsufficientTier() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "admin_tool", scope: .mutating, requiredTier: .full))

        let broker = ToolBroker(registry: registry)
        let caller = StubCaller(capabilityTier: .basic)
        let result = await broker.invoke(toolNamed: "admin_tool", input: Data(), caller: caller)

        if case .failure(let message) = result {
            #expect(message.contains("insufficient"))
        } else {
            Issue.record("Expected failure, got \(result)")
        }
    }

    @Test("Broker returns failure for unknown tool")
    func unknownTool() async {
        let registry = ToolRegistry()
        let broker = ToolBroker(registry: registry)
        let caller = StubCaller(capabilityTier: .full)
        let result = await broker.invoke(toolNamed: "nope", input: Data(), caller: caller)

        if case .failure(let message) = result {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected failure, got \(result)")
        }
    }

    @Test("invokeConfirmed executes destructive tool after confirmation")
    func confirmedExecution() async {
        let registry = ToolRegistry()
        await registry.register(StubTool(name: "delete_all", scope: .destructive, requiredTier: .full))

        let broker = ToolBroker(registry: registry)
        let caller = StubCaller(capabilityTier: .full)
        let result = await broker.invokeConfirmed(toolNamed: "delete_all", input: Data(), caller: caller)

        if case .success(let data) = result {
            #expect(String(data: data, encoding: .utf8) == "ok")
        } else {
            Issue.record("Expected success after confirmation, got \(result)")
        }
    }
}
