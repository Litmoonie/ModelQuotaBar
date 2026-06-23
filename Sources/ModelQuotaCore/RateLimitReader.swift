import Foundation

public struct RateLimitSnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var primary: RateLimitWindow
    public var secondary: RateLimitWindow?
    public var planType: String?
    public var sessionsDirectory: String

    public init(
        timestamp: Date,
        primary: RateLimitWindow,
        secondary: RateLimitWindow?,
        planType: String?,
        sessionsDirectory: String
    ) {
        self.timestamp = timestamp
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.sessionsDirectory = sessionsDirectory
    }
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public var remainingPercent: Int
    public var usedPercent: Double
    public var windowMinutes: Int?
    public var resetsAt: Date?
    public var resetInferred: Bool

    public init(
        remainingPercent: Int,
        usedPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        resetInferred: Bool = false
    ) {
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetInferred = resetInferred
    }
}

public enum RateLimitReaderError: Error, LocalizedError {
    case sessionsDirectoryMissing(String)
    case rateLimitNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .sessionsDirectoryMissing(let path):
            return "Codex sessions directory was not found: \(path)"
        case .rateLimitNotFound(let path):
            return "No Codex rate limit event was found in: \(path)"
        }
    }
}

public final class RateLimitReader {
    private let fileManager: FileManager
    private let sessionsDirectory: URL

    public init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions"),
        fileManager: FileManager = .default
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.fileManager = fileManager
    }

    public func latestSnapshot(now: Date = Date()) throws -> RateLimitSnapshot {
        let path = sessionsDirectory.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RateLimitReaderError.sessionsDirectoryMissing(path)
        }

        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var files: [(url: URL, modified: Date)] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }
            guard fileURL.pathExtension.lowercased() == "jsonl" || fileURL.pathExtension.lowercased() == "json" else {
                continue
            }

            files.append((fileURL, values.contentModificationDate ?? .distantPast))
        }

        files.sort { $0.modified > $1.modified }

        var latest: RateLimitSnapshot?

        for file in files {
            if let latest, file.modified <= latest.timestamp {
                break
            }

            if let snapshot = scanFile(file.url, sessionsPath: path, now: now),
               latest == nil || snapshot.timestamp > latest!.timestamp {
                latest = snapshot
            }
        }

        guard let latest else {
            throw RateLimitReaderError.rateLimitNotFound(path)
        }

        return latest
    }

    private func scanFile(_ fileURL: URL, sessionsPath: String, now: Date) -> RateLimitSnapshot? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var latest: RateLimitSnapshot?

        for line in contents.split(whereSeparator: \.isNewline) {
            guard line.contains("rate_limits"),
                  let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = dateValue(json["timestamp"]),
                  let payload = json["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any],
                  let primary = rateLimits["primary"] as? [String: Any],
                  let primaryWindow = rateLimitWindow(from: primary, eventTimestamp: timestamp, now: now) else {
                continue
            }

            let secondaryWindow = (rateLimits["secondary"] as? [String: Any]).flatMap {
                rateLimitWindow(from: $0, eventTimestamp: timestamp, now: now)
            }
            let planType = rateLimits["plan_type"] as? String

            let snapshot = RateLimitSnapshot(
                timestamp: timestamp,
                primary: primaryWindow,
                secondary: secondaryWindow,
                planType: planType,
                sessionsDirectory: sessionsPath
            )

            if latest == nil || snapshot.timestamp > latest!.timestamp {
                latest = snapshot
            }
        }

        return latest
    }
}

private func rateLimitWindow(from dictionary: [String: Any], eventTimestamp: Date, now: Date) -> RateLimitWindow? {
    guard let usedPercent = doubleValue(dictionary["used_percent"]) else {
        return nil
    }

    let resetsAt = doubleValue(dictionary["resets_at"]).map { Date(timeIntervalSince1970: $0) }
    let windowMinutes = intValue(dictionary["window_minutes"])

    // Codex may not write a fresh rate-limit event exactly when a window resets.
    // If the last known window has expired, mirror the app's refreshed state until a new event arrives.
    if let resetsAt, eventTimestamp < resetsAt, now >= resetsAt {
        return RateLimitWindow(
            remainingPercent: 99,
            usedPercent: 1,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt,
            resetInferred: true
        )
    }

    return RateLimitWindow(
        remainingPercent: remainingPercent(from: usedPercent),
        usedPercent: usedPercent,
        windowMinutes: windowMinutes,
        resetsAt: resetsAt
    )
}

private func remainingPercent(from usedPercent: Double) -> Int {
    let raw = 100 - usedPercent
    return Int(max(0, min(100, raw)).rounded())
}

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return Int(string) }
    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) }
    return nil
}

private func dateValue(_ value: Any?) -> Date? {
    if let number = value as? NSNumber {
        return Date(timeIntervalSince1970: number.doubleValue)
    }

    guard let string = value as? String else {
        return nil
    }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) {
        return date
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}
