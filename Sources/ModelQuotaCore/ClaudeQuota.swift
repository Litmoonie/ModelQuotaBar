import Foundation

public struct ClaudeQuota: Codable, Sendable {
    public static var snapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ModelQuotaBar/claude-quota.json")
    }

    public struct Window: Codable, Sendable {
        let usedPercentage: Double
        let resetsAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

        public func remainingPercent(now: Date = Date()) -> Int? {
            guard (0...100).contains(usedPercentage), resetsAt > now.timeIntervalSince1970 else {
                return nil
            }
            return Int((100 - usedPercentage).rounded())
        }
    }

    private struct StatusLineInput: Decodable {
        struct RateLimits: Decodable {
            let fiveHour: Window?
            let sevenDay: Window?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
            }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                fiveHour = try? values.decode(Window.self, forKey: .fiveHour)
                sevenDay = try? values.decode(Window.self, forKey: .sevenDay)
            }
        }

        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    let capturedAt: TimeInterval

    public static func capture(_ input: Data, to url: URL = snapshotURL, now: Date = Date()) throws {
        let limits = try JSONDecoder().decode(StatusLineInput.self, from: input).rateLimits
        let snapshot = ClaudeQuota(fiveHour: limits?.fiveHour, sevenDay: limits?.sevenDay,
                                  capturedAt: now.timeIntervalSince1970)
        let fileManager = FileManager.default
        let data = try JSONEncoder().encode(snapshot)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if snapshot.fiveHour != nil || snapshot.sevenDay != nil {
            try data.write(to: url, options: .atomic)
        } else {
            do {
                try data.write(to: url, options: .withoutOverwriting)
            } catch CocoaError.fileWriteFileExists {
                return
            }
        }
    }

    public static func read(from url: URL = snapshotURL) -> ClaudeQuota? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(ClaudeQuota.self, from: data)
    }
}
