import Testing
@testable import PodedgeCore

@Suite("Router")
struct RouterTests {

    @Test
    func keywordRulePromoter() async {
        let router = Router(llmProvider: MockLLMProvider())
        let decision = await router.route(utterance: "/promote my latest episode")
        guard case .agent(let id) = decision else {
            Issue.record("Expected .agent, got \(decision)")
            return
        }
        #expect(id == "promoter")
    }

    @Test
    func keywordRulePublish() async {
        let router = Router(llmProvider: MockLLMProvider())
        let decision = await router.route(utterance: "/publish episode 5")
        guard case .agent(let id) = decision else {
            Issue.record("Expected .agent, got \(decision)")
            return
        }
        #expect(id == "publish-assistant")
    }

    @Test
    func unknownUtteranceCallsLLM() async {
        let mock = MockLLMProvider(completeResponse: "unknown")
        let router = Router(llmProvider: mock)
        let decision = await router.route(utterance: "what's the weather?")
        // LLM returns "unknown" which doesn't match known agent IDs → .unknown
        guard case .unknown = decision else {
            Issue.record("Expected .unknown, got \(decision)")
            return
        }
        #expect(mock.completeCallCount > 0)
    }

    @Test
    func keywordsCaseInsensitive() async {
        let router = Router(llmProvider: MockLLMProvider())
        let decision = await router.route(utterance: "/PROMOTE this")
        guard case .agent(let id) = decision else {
            Issue.record("Expected .agent")
            return
        }
        #expect(id == "promoter")
    }

    @Test
    func llmReturnsPromoter() async {
        let mock = MockLLMProvider(completeResponse: "promoter")
        let router = Router(llmProvider: mock)
        let decision = await router.route(utterance: "create social posts for my episode")
        guard case .agent(let id) = decision else {
            Issue.record("Expected .agent, got \(decision)")
            return
        }
        #expect(id == "promoter")
    }

    @Test
    func llmThrowsReturnsUnknown() async {
        let mock = MockLLMProvider()
        mock.shouldThrow = true
        let router = Router(llmProvider: mock)
        let decision = await router.route(utterance: "do something")
        guard case .unknown = decision else {
            Issue.record("Expected .unknown when LLM throws, got \(decision)")
            return
        }
    }
}
