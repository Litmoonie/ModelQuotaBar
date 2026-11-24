import AppKit
import ModelQuotaCore
import Foundation

@main
@MainActor
final class ModelQuotaBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let deepSeekCoordinator = DeepSeekStatusCoordinator()
    private let codexRefreshInterval: TimeInterval = 10
    private let deepSeekAutoRefreshInterval: TimeInterval = 300
    private var timer: Timer?
    private var latestSnapshot: RateLimitSnapshot?
    private var claudeQuota: ClaudeQuota?
    private var latestError: Error?
    private var deepSeekState = DeepSeekDisplayState.loading
    private var lastDeepSeekRefresh: Date?
    private var refreshTask: Task<Void, Never>?
    private var deepSeekRefreshTask: Task<Void, Never>?

    static func main() {
        if CommandLine.arguments.contains("--capture-claude-quota") {
            do {
                try ClaudeQuota.capture(FileHandle.standardInput.readDataToEndOfFile())
                exit(0)
            } catch {
                exit(1)
            }
        }

        if CommandLine.arguments.contains("--self-test") {
            runSelfTestAndExit()
        }

        if CommandLine.arguments.contains("--print-snapshot") {
            printSnapshotAndExit()
        }

        let application = NSApplication.shared
        let delegate = ModelQuotaBarApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "Codex ..."
        performRefresh(forceDeepSeek: true)
        timer = Timer.scheduledTimer(
            timeInterval: codexRefreshInterval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func timerFired() {
        performRefresh(forceDeepSeek: false)
    }

    @objc private func refresh() {
        performRefresh(forceDeepSeek: true)
    }

    private func performRefresh(forceDeepSeek: Bool) {
        refreshDeepSeekIfNeeded(force: forceDeepSeek)

        refreshTask?.cancel()
        refreshTask = Task {
            async let localQuotas = Task.detached(priority: .utility) {
                (Result { try RateLimitReader().latestSnapshot() }, ClaudeQuota.read())
            }.value
            let (result, nextClaudeQuota) = await localQuotas

            guard !Task.isCancelled else {
                return
            }

            switch result {
            case .success(let snapshot):
                latestError = nil
                latestSnapshot = snapshot
            case .failure(let error):
                latestError = error
                latestSnapshot = nil
            }

            claudeQuota = nextClaudeQuota
            statusItem.button?.title = statusTitle()
            rebuildMenu()
        }
    }

    private func refreshDeepSeekIfNeeded(force: Bool) {
        if force {
            deepSeekRefreshTask?.cancel()
            deepSeekState = .loading
            rebuildMenu()
        } else {
            guard deepSeekRefreshTask == nil else { return }
            if let lastDeepSeekRefresh,
               Date().timeIntervalSince(lastDeepSeekRefresh) < deepSeekAutoRefreshInterval {
                return
            }
        }

        deepSeekRefreshTask = Task {
            let nextState = await deepSeekCoordinator.refresh()
            guard !Task.isCancelled else { return }
            deepSeekState = nextState
            lastDeepSeekRefresh = Date()
            deepSeekRefreshTask = nil
            rebuildMenu()
        }
    }

    private func statusTitle() -> String {
        let codex = latestSnapshot.map { String($0.primary.remainingPercent) }
        guard let claudeQuota else {
            return codex.map { "Codex \($0)%" } ?? "Codex --"
        }
        let claude = claudeQuota.fiveHour?.remainingPercent().map(String.init) ?? "--"
        return "CX \(codex ?? "--") · CC \(claude)"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let claudeQuota {
            let codex = quotaPercent(latestSnapshot?.primary.remainingPercent)
            let claude = quotaPercent(claudeQuota.fiveHour?.remainingPercent())
            menu.addItem(disabledItem("Codex 5-hour remaining \(codex)"))
            menu.addItem(disabledItem("Claude 5-hour remaining \(claude)"))
        }
        let weeklyQuota = quotaPercent(latestSnapshot?.secondary?.remainingPercent)
        menu.addItem(disabledItem("Codex weekly \(weeklyQuota)"))
        if let claudeQuota {
            let weekly = quotaPercent(claudeQuota.sevenDay?.remainingPercent())
            menu.addItem(disabledItem("Claude weekly \(weekly)"))
        }
        menu.addItem(deepSeekItem("DS balance \(deepSeekState.balance.display)", value: deepSeekState.balance))
        menu.addItem(.separator())

        if let latestError {
            menu.addItem(disabledItem(latestError.localizedDescription))
            menu.addItem(.separator())
        }

        menu.addItem(actionItem("Refresh", #selector(refresh)))
        menu.addItem(actionItem("Quit", #selector(quit)))
        statusItem.menu = menu
    }

    @objc func setDeepSeekAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Set DeepSeek API Key"
        alert.informativeText = "Used to read your DeepSeek account balance. The key is stored in macOS Keychain."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "sk-..."
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let apiKey = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return
        }

        do {
            try DeepSeekAPIKeyStore.saveAPIKey(apiKey)
            deepSeekState = .loading
            lastDeepSeekRefresh = nil
            rebuildMenu()
            performRefresh(forceDeepSeek: true)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quit() {
        refreshTask?.cancel()
        deepSeekRefreshTask?.cancel()
        timer?.invalidate()
        NSApplication.shared.terminate(nil)
    }
}

private func printSnapshotAndExit() -> Never {
    do {
        let snapshot = try RateLimitReader().latestSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

private func runSelfTestAndExit() -> Never {
    do {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let file = root.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"timestamp":"2026-06-16T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":70,"window_minutes":300,"resets_at":1781616753},"secondary":{"used_percent":10,"window_minutes":10080,"resets_at":1781793973},"plan_type":"plus"}}}"#,
            #"{"timestamp":"2026-06-16T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":78,"window_minutes":300,"resets_at":1781616753},"secondary":{"used_percent":18,"window_minutes":10080,"resets_at":1781793973},"plan_type":"plus"}}}"#,
            #"{"timestamp":"2026-06-16T00:02:00.000Z","payload":{"rate_limits":{"limit_id":"alternate-model","primary":{"used_percent":90}}}}"#,
            #"{"timestamp":"2026-06-16T00:03:00.000Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":"NaN"}}}}"#
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        // One second after primary.resets_at, so the self-test covers inferred reset behavior.
        let now = Date(timeIntervalSince1970: 1_781_616_754)
        let snapshot = try RateLimitReader(sessionsDirectory: root).latestSnapshot(now: now)
        try check(snapshot.primary.remainingPercent == 99, "expected inferred 99%, got \(snapshot.primary.remainingPercent)%")
        try check(snapshot.primary.resetInferred, "expected primary reset to be inferred")
        try check(snapshot.secondary?.remainingPercent == 82, "expected 82% weekly")
        try check(snapshot.planType == "plus", "expected plus plan")

        let claudeURL = root.appendingPathComponent("claude-quota.json")
        try check(ClaudeQuota.read(from: claudeURL) == nil, "expected Claude to start disabled")
        let claudeInput = #"{"cwd":"private-path","rate_limits":{"five_hour":{"used_percentage":42.25,"resets_at":1781616755},"seven_day":{"used_percentage":18,"resets_at":1781616754}}}"#
        try ClaudeQuota.capture(Data(claudeInput.utf8), to: claudeURL, now: now)
        try ClaudeQuota.capture(Data("{}".utf8), to: claudeURL, now: now)
        let claude = ClaudeQuota.read(from: claudeURL)
        try check(claude?.fiveHour?.remainingPercent(now: now) == 58, "expected 58% Claude 5-hour")
        try check(claude?.sevenDay?.remainingPercent(now: now) == nil, "expected expired Claude week to be unavailable")
        let storedClaude = try String(contentsOf: claudeURL, encoding: .utf8)
        try check(!storedClaude.contains("private-path"), "expected quota-only Claude snapshot")
        let weeklyOnly = #"{"rate_limits":{"seven_day":{"used_percentage":18,"resets_at":1781793973}}}"#
        try ClaudeQuota.capture(Data(weeklyOnly.utf8), to: claudeURL, now: now)
        let claudeWeekly = ClaudeQuota.read(from: claudeURL)
        try check(claudeWeekly?.fiveHour == nil, "expected missing Claude 5-hour window")
        try check(claudeWeekly?.sevenDay?.remainingPercent(now: now) == 82, "expected 82% Claude weekly")
        let malformedWindow = #"{"rate_limits":{"five_hour":{"used_percentage":22},"seven_day":{"used_percentage":15,"resets_at":1781793973}}}"#
        try ClaudeQuota.capture(Data(malformedWindow.utf8), to: claudeURL, now: now)
        let partialClaude = ClaudeQuota.read(from: claudeURL)
        try check(partialClaude?.fiveHour == nil, "expected malformed Claude 5-hour window to be skipped")
        try check(partialClaude?.sevenDay?.remainingPercent(now: now) == 85, "expected valid Claude weekly despite malformed 5-hour window")

        let deepSeekBalanceJSON = #"""
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "USD",
              "total_balance": "4.20",
              "granted_balance": "0.00",
              "topped_up_balance": "4.20"
            },
            {
              "currency": "CNY",
              "total_balance": "32.15",
              "granted_balance": "0.00",
              "topped_up_balance": "32.15"
            }
          ]
        }
        """#
        let deepSeekBalance = try DeepSeekBalanceClient.parseCNYBalance(from: Data(deepSeekBalanceJSON.utf8))
        let expectedBalance = Decimal(string: "32.15", locale: Locale(identifier: "en_US_POSIX"))
        try check(deepSeekBalance == expectedBalance, "expected DeepSeek CNY balance 32.15, got \(deepSeekBalance)")

        print("Self-test passed.")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Self-test failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

private struct SelfTestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func quotaPercent(_ remaining: Int?) -> String {
    remaining.map { "\($0)%" } ?? "--"
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw SelfTestFailure(message: message)
    }
}

@MainActor
private func disabledItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
}

@MainActor
private func actionItem(_ title: String, _ selector: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
    item.target = NSApplication.shared.delegate
    return item
}

@MainActor
private func deepSeekItem(_ title: String, value: DeepSeekMenuValue) -> NSMenuItem {
    switch value.action {
    case .setAPIKey:
        return actionItem(title, #selector(ModelQuotaBarApp.setDeepSeekAPIKey))
    case nil:
        return disabledItem(title)
    }
}
