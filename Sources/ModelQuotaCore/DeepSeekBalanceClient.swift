import Foundation

public enum DeepSeekBalanceError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case cnyBalanceNotFound
    case invalidBalanceValue(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "DeepSeek balance response was invalid."
        case .httpStatus(let status):
            return "DeepSeek balance request failed with HTTP \(status)."
        case .cnyBalanceNotFound:
            return "DeepSeek CNY balance was not found."
        case .invalidBalanceValue(let value):
            return "DeepSeek balance value was invalid: \(value)"
        }
    }
}

public struct DeepSeekBalanceClient: Sendable {
    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            preconditionFailure("Invalid DeepSeek balance endpoint URL.")
        }
        return url
    }()

    private let endpoint: URL

    public init(endpoint: URL = Self.defaultEndpoint) {
        self.endpoint = endpoint
    }

    public func fetchCNYBalance(apiKey: String) async throws -> Decimal {
        try Task.checkCancellation()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekBalanceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DeepSeekBalanceError.httpStatus(httpResponse.statusCode)
        }

        let value = try Self.parseCNYBalance(from: data)
        try Task.checkCancellation()

        return value
    }

    public static func parseCNYBalance(from data: Data) throws -> Decimal {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(DeepSeekBalanceResponse.self, from: data)

        guard let balance = payload.balanceInfos.first(where: { $0.currency == "CNY" }) else {
            throw DeepSeekBalanceError.cnyBalanceNotFound
        }

        guard let value = Decimal(string: balance.totalBalance, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DeepSeekBalanceError.invalidBalanceValue(balance.totalBalance)
        }

        return value
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    var isAvailable: Bool
    var balanceInfos: [DeepSeekBalanceInfo]
}

private struct DeepSeekBalanceInfo: Decodable {
    var currency: String
    var totalBalance: String
    var grantedBalance: String
    var toppedUpBalance: String
}
