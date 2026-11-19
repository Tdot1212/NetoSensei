import Foundation

enum UniFiClients {
    struct Client: Decodable, Identifiable {
        let id: String
        let name: String?
        let type: String
        let ipAddress: String?
        let macAddress: String?

        var displayName: String { WiFiDeviceInventory.clean(name) ?? "Unnamed client" }
        var connection: String {
            switch type.uppercased() {
            case "WIRELESS": return "Wi-Fi"
            case "WIRED": return "Wired"
            case "VPN": return "VPN"
            default: return "Other connection"
            }
        }
    }

    struct Page: Decodable {
        let data: [Client]
        let offset: Int
        let count: Int
        let totalCount: Int
    }

    enum Failure: LocalizedError {
        case invalidSetup, unauthorized, unavailable, unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidSetup: return "Enter a console ID, a site UUID and a UniFi API key."
            case .unauthorized: return "UniFi rejected this key. Check that it has access to the selected console."
            case .unavailable: return "UniFi couldn’t find or reach the selected console or site. Check the IDs and that Connector is available."
            case .unexpectedResponse: return "UniFi did not return a valid client list. Try again."
            }
        }
    }

    static func request(console: String, site: String, key: String, offset: Int) throws -> URLRequest {
        let console = console.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: site) != nil, offset >= 0 else { throw Failure.invalidSetup }
        return try request(path: "\(consolePath(console))/sites/\(site)/clients", key: key,
                           query: [.init(name: "offset", value: String(offset)), .init(name: "limit", value: "25")])
    }

    struct Choice: Decodable, Identifiable {
        struct ReportedState: Decodable { let hostname: String? }
        let id: String
        let name: String?
        let reportedState: ReportedState?

        var title: String { WiFiDeviceInventory.clean(name ?? reportedState?.hostname) ?? id }
    }

    private struct Choices: Decodable {
        let data: [Choice]
    }

    static func consoles(key: String) async throws -> [Choice] {
        let request = try request(path: "/v1/hosts", key: key, query: [])
        return try JSONDecoder().decode(Choices.self, from: await responseData(for: request)).data
    }

    static func sites(console: String, key: String) async throws -> [Choice] {
        let request = try request(path: "\(consolePath(console))/sites", key: key,
                                  query: [.init(name: "limit", value: "100")])
        return try JSONDecoder().decode(Choices.self, from: await responseData(for: request)).data
    }

    private static func consolePath(_ console: String) throws -> String {
        let permitted = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_:")
        guard (1...160).contains(console.count), console.unicodeScalars.allSatisfy(permitted.contains) else {
            throw Failure.invalidSetup
        }
        return "/v1/connector/consoles/\(console)/proxy/network/integration/v1"
    }

    private static func request(path: String, key: String, query: [URLQueryItem]) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw Failure.invalidSetup
        }
        var endpoint = URLComponents()
        endpoint.scheme = "https"
        endpoint.host = "api.ui.com"
        endpoint.path = path
        endpoint.queryItems = query.isEmpty ? nil : query
        guard let url = endpoint.url else { throw Failure.invalidSetup }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        return request
    }

    static func decodePage(_ data: Data, expectedOffset: Int) throws -> Page {
        guard let page = try? JSONDecoder().decode(Page.self, from: data),
              page.offset == expectedOffset, page.count == page.data.count,
              page.totalCount >= 0, page.count <= 100,
              page.count > 0 || expectedOffset >= page.totalCount else { throw Failure.unexpectedResponse }
        return page
    }

    static func fetch(console: String, site: String, key: String, offset: Int) async throws -> Page {
        let request = try request(console: console, site: site, key: key, offset: offset)
        return try decodePage(await responseData(for: request), expectedOffset: offset)
    }

    private static func responseData(for request: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 18
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 401, 403: throw Failure.unauthorized
        case 404, 502, 503, 504: throw Failure.unavailable
        default: throw Failure.unexpectedResponse
        }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
