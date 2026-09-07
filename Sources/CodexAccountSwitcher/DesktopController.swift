import AppKit
import Foundation

enum DesktopControllerError: LocalizedError, Sendable {
    case applicationNotFound
    case bundledBackendNotExecutable
    case bundledBackendCompanionNotFound
    case quitRequestFailed
    case didNotExit
    case reopenFailed

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            "The Codex Desktop application could not be found."
        case .bundledBackendNotExecutable:
            "The bundled Codex app-server executable is not executable."
        case .bundledBackendCompanionNotFound:
            "The bundled Codex code-mode host could not be found beside the app-server executable."
        case .quitRequestFailed:
            "Codex Desktop rejected the quit request."
        case .didNotExit:
            "Codex Desktop did not finish quitting within 30 seconds. Finish or stop active tasks and close Desktop, then switch again. The account has not changed."
        case .reopenFailed:
            "Codex Desktop could not be reopened. Open it manually to continue."
        }
    }
}

// A quit request may be waiting for Desktop's active-task dialog or durable history writes.
// Expiry must stop the switch before credentials change; it must never escalate to SIGKILL.
struct DesktopQuitWaiter: Sendable {
    var timeout: Duration = .seconds(30)
    var pollInterval: Duration = .milliseconds(100)

    func wait(isRunning: @Sendable () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while await isRunning() {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw DesktopControllerError.didNotExit }
            try await Task.sleep(for: min(pollInterval, deadline - clock.now))
        }
        try Task.checkCancellation()
    }
}

struct DesktopController: DesktopControlling {
    private let bundleIdentifiers = ["com.openai.codex"]
    private let applicationPaths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]

    func closeDesktop() async throws {
        let running = NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
        guard !running.isEmpty else { return }
        for application in running where !application.isTerminated {
            let processIdentifier = application.processIdentifier
            guard application.terminate() || !isDesktopRunning(processIdentifier: processIdentifier) else {
                throw DesktopControllerError.quitRequestFailed
            }
        }

        try await DesktopQuitWaiter().wait {
            isDesktopRunning
        }
    }

    func reopenDesktop() async throws {
        guard let url = applicationURL() else {
            throw DesktopControllerError.applicationNotFound
        }
        let environment = try bundledBackendEnvironment()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.environment = environment
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw DesktopControllerError.reopenFailed
        }
    }

    private func bundledBackendEnvironment() throws -> [String: String] {
        guard let backendURL = Bundle.main.url(forAuxiliaryExecutable: "codex") else {
            return [:]
        }
        guard FileManager.default.isExecutableFile(atPath: backendURL.path) else {
            throw DesktopControllerError.bundledBackendNotExecutable
        }
        let companionURL = backendURL
            .deletingLastPathComponent()
            .appending(path: "codex-code-mode-host")
        guard FileManager.default.isExecutableFile(atPath: companionURL.path) else {
            throw DesktopControllerError.bundledBackendCompanionNotFound
        }
        return ["CODEX_CLI_PATH": backendURL.path]
    }

    private func applicationURL() -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return applicationPaths
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private var isDesktopRunning: Bool {
        !runningDesktopApplications.isEmpty
    }

    private var runningDesktopApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
    }

    private func isDesktopRunning(processIdentifier: pid_t) -> Bool {
        runningDesktopApplications.contains { $0.processIdentifier == processIdentifier }
    }
}
