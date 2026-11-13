import Foundation

/// The network seam for HTTP-based providers, so tests can stub responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("No HTTP response.") }
        return (data, http)
    }
}

enum HTTPProviderSupport {
    /// Serialises `body` and inserts `schema` verbatim under `path` (e.g. ["format"] or
    /// ["output_config", "format", "schema"]).
    ///
    /// The schema must not go through `JSONSerialization`: dictionaries lose key order, and
    /// grammar-constrained models generate properties in schema order. With `task` ahead of
    /// `question`, gemma4 on Ollama emitted whitespace until it timed out (measured 2026-11-13).
    static func jsonBody(_ body: [String: Any], insertingSchema schema: String, at path: [String]) throws -> Data {
        guard (try? JSONSerialization.jsonObject(with: Data(schema.utf8))) != nil else {
            throw LLMError.badResponse("invalid schema")
        }
        let placeholder = "__EMO_SCHEMA_\(UUID().uuidString)__"
        func inserting(_ dict: [String: Any], _ path: ArraySlice<String>) -> [String: Any] {
            var dict = dict
            guard let key = path.first else { return dict }
            dict[key] = path.count == 1 ? placeholder : inserting(dict[key] as? [String: Any] ?? [:], path.dropFirst())
            return dict
        }
        let data = try JSONSerialization.data(withJSONObject: inserting(body, path[...]))
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"\(placeholder)\"", with: schema)
        return Data(text.utf8)
    }

    /// Sends, mapping connection failures to readable errors.
    static func send(_ request: URLRequest, via transport: any HTTPTransport, unreachable: String) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw LLMError.transport("You're offline.")
            case .timedOut:
                throw LLMError.transport("The request timed out. Try again.")
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                throw LLMError.transport(unreachable)
            default:
                throw LLMError.transport(error.localizedDescription)
            }
        }
    }

    static func decode<Output: Decodable>(_ type: Output.Type, fromJSONText text: String) throws -> Output {
        guard let data = text.data(using: .utf8) else { throw LLMError.badResponse("empty reply") }
        do {
            return try JSONDecoder().decode(Output.self, from: data)
        } catch {
            throw LLMError.badResponse("reply didn't match the expected format")
        }
    }
}
