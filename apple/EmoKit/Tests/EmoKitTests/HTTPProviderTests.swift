import Foundation
import Testing
@testable import EmoKit

final class StubTransport: HTTPTransport, @unchecked Sendable {
    var response: Result<(Int, String), Error>
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, body: String) { response = .success((status, body)) }
    init(error: Error) { response = .failure(error) }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = try response.get()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func body(_ i: Int = 0) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: requests[i].httpBody!) as! [String: Any]
    }
}

/// Returns a different canned response per call.
final class SequenceTransport: HTTPTransport, @unchecked Sendable {
    private var responses: [(Int, String)]
    private(set) var bodies: [[String: Any]] = []
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        bodies.append(try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any])
        let (status, body) = responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite struct ClaudeProviderTests {
    let conversation = [ChatTurn(.user, "report, 2 hours, for my boss")]
    let taskJSON = #"{"question":null,"task":{"name":"Write report","estimatedHours":2,"energyCost":"high","category":"external_commitment"}}"#

    func reply(_ text: String, stop: String = "end_turn") -> String {
        let escaped = String(data: try! JSONSerialization.data(withJSONObject: [text]), encoding: .utf8)!.dropFirst().dropLast()
        return #"{"stop_reason":"\#(stop)","content":[{"type":"thinking","thinking":""},{"type":"text","text":\#(escaped)}]}"#
    }

    @Test func buildsAStructuredOutputRequest() async throws {
        let stub = StubTransport(body: reply(taskJSON))
        _ = try await ClaudeProvider(apiKey: "sk-test", transport: stub)
            .generate(ClarifierReply.self, instructions: "be helpful", conversation: conversation)

        let request = try #require(stub.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try stub.body()
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["system"] as? String == "be helpful")
        #expect(body["temperature"] == nil)
        #expect(body["tool_choice"] == nil)
        #expect(body["fallbacks"] as? String == "default")
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "low")
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["schema"] as? [String: Any])?["additionalProperties"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "report, 2 hours, for my boss"]])
    }

    @Test func parsesTheTextBlockIgnoringThinking() async throws {
        let stub = StubTransport(body: reply(taskJSON))
        let result = try await ClaudeProvider(apiKey: "k", transport: stub)
            .generate(ClarifierReply.self, instructions: "", conversation: conversation)
        #expect(result.task?.name == "Write report")
        #expect(result.question == nil)
    }

    @Test func refusalAndTruncationAreErrors() async {
        for stop in ["refusal", "max_tokens"] {
            let stub = StubTransport(body: reply("{}", stop: stop))
            await #expect(throws: LLMError.self) {
                try await ClaudeProvider(apiKey: "k", transport: stub).generate(ClarifierReply.self, instructions: "", conversation: conversation)
            }
        }
    }

    @Test(arguments: [(401, "rejected the API key"), (404, "model not found"), (429, "rate-limited"), (529, "overloaded")])
    func httpErrorsBecomeReadable(status: Int, phrase: String) async throws {
        let stub = StubTransport(status: status, body: #"{"type":"error","error":{"type":"x","message":"m"}}"#)
        do {
            _ = try await ClaudeProvider(apiKey: "k", transport: stub).generate(ClarifierReply.self, instructions: "", conversation: conversation)
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription.contains(phrase))
        }
    }

    @Test func missingKeyIsUnavailableWithoutANetworkCall() async {
        let stub = StubTransport(body: "{}")
        let provider = ClaudeProvider(apiKey: "  ", transport: stub)
        #expect(await provider.availability() != .available)
        await #expect(throws: LLMError.self) { try await provider.generate(ClarifierReply.self, instructions: "", conversation: conversation) }
        #expect(stub.requests.isEmpty)
    }

    @Test func offlineIsReadable() async {
        let stub = StubTransport(error: URLError(.notConnectedToInternet))
        await #expect(throws: LLMError.transport("You're offline.")) {
            try await ClaudeProvider(apiKey: "k", transport: stub).generate(ClarifierReply.self, instructions: "", conversation: conversation)
        }
    }
}

@Suite struct OllamaProviderTests {
    let conversation = [ChatTurn(.user, "gym session")]
    let content = #"{\"question\":\"How long is the session?\",\"task\":null}"#

    @Test func buildsAChatRequestWithFormatSchema() async throws {
        let stub = StubTransport(body: #"{"message":{"role":"assistant","content":"\#(content)"}}"#)
        let result = try await OllamaProvider(host: "https://ollama.com", model: "gpt-oss:20b", apiKey: "ok-key", transport: stub)
            .generate(ClarifierReply.self, instructions: "rules", conversation: conversation)

        #expect(result.question == "How long is the session?")
        let request = try #require(stub.requests.first)
        #expect(request.url?.absoluteString == "https://ollama.com/api/chat")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ok-key")
        let body = try stub.body()
        #expect(body["model"] as? String == "gpt-oss:20b")
        #expect(body["stream"] as? Bool == false)
        #expect(body["think"] as? Bool == false)
        #expect((body["format"] as? [String: Any])?["type"] as? String == "object")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.first == ["role": "system", "content": "rules"])
        #expect(messages.last == ["role": "user", "content": "gym session"])
    }

    @Test func schemaKeyOrderIsPreservedVerbatim() async throws {
        let stub = StubTransport(body: #"{"message":{"content":"\#(content)"}}"#)
        _ = try await OllamaProvider(transport: stub).generate(ClarifierReply.self, instructions: "", conversation: conversation)
        let raw = String(decoding: try #require(stub.requests.first?.httpBody), as: UTF8.self)
        let question = try #require(raw.range(of: "\"question\""))
        let task = try #require(raw.range(of: "\"task\""))
        #expect(question.lowerBound < task.lowerBound)
        #expect((try stub.body()["options"] as? [String: Any])?["num_predict"] as? Int == 1024)
    }

    @Test func localHostSendsNoAuthorization() async throws {
        let stub = StubTransport(body: #"{"message":{"content":"\#(content)"}}"#)
        _ = try await OllamaProvider(transport: stub).generate(ClarifierReply.self, instructions: "", conversation: conversation)
        #expect(stub.requests.first?.url?.absoluteString == "http://localhost:11434/api/chat")
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func missingModelAndUnreachableHostAreReadable() async {
        let missing = StubTransport(status: 404, body: #"{"error":"model not found"}"#)
        await #expect(throws: LLMError.self) {
            try await OllamaProvider(transport: missing).generate(ClarifierReply.self, instructions: "", conversation: conversation)
        }
        let down = StubTransport(error: URLError(.cannotConnectToHost))
        do {
            _ = try await OllamaProvider(transport: down).generate(ClarifierReply.self, instructions: "", conversation: conversation)
        } catch {
            #expect(error.localizedDescription.contains("Is it running?"))
        }
    }

    @Test func retriesWithoutThinkWhenTheModelRejectsIt() async throws {
        let stub = SequenceTransport([
            (400, #"{"error":"\"llama3\" does not support thinking"}"#),
            (200, #"{"message":{"content":"\#(content)"}}"#),
        ])
        let result = try await OllamaProvider(model: "llama3", transport: stub)
            .generate(ClarifierReply.self, instructions: "", conversation: conversation)
        #expect(result.question == "How long is the session?")
        #expect(stub.bodies.count == 2)
        #expect(stub.bodies[0]["think"] as? Bool == false)
        #expect(stub.bodies[1]["think"] == nil)
    }

    @Test func malformedContentIsABadResponse() async {
        let stub = StubTransport(body: #"{"message":{"content":"not json"}}"#)
        await #expect(throws: LLMError.self) {
            try await OllamaProvider(transport: stub).generate(ClarifierReply.self, instructions: "", conversation: conversation)
        }
    }
}
