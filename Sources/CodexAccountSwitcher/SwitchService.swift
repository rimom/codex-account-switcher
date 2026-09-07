import Foundation

protocol DesktopControlling: Sendable {
    func closeDesktop() async throws
    func reopenDesktop() async throws
}

protocol CodexIdentityReading: Sendable {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity
}

protocol SwitchServicing: Sendable {
    func switchAccount(to targetID: UUID) async throws
}

struct SwitchService: SwitchServicing {
    let desktop: any DesktopControlling
    let store: any AccountStoring
    let codex: any CodexIdentityReading
    let configuration: any ProviderConfigurationServicing

    func switchAccount(to targetID: UUID) async throws {
        let target: AccountProfile
        let originalActiveID: UUID?
        let originalProfile: AccountProfile?
        let codexHome = await store.activeCodexHome()
        let originalProviderID: String
        do {
            target = try await store.profile(id: targetID)
        } catch {
            throw OperationError.stage(.activateTargetCredential, error)
        }

        do {
            originalProviderID = try await configuration
                .readConfiguration(codexHome: codexHome)
                .activeProviderID
        } catch {
            throw OperationError.stage(.activateTargetProvider, error)
        }

        do {
            let registry = try await store.loadRegistry()
            originalActiveID = registry.activeAccountID
            if let activeID = registry.activeAccountID {
                guard let profile = registry.accounts.first(where: { $0.id == activeID }) else {
                    throw AccountStoreError.activeProfileMissing
                }
                originalProfile = profile
            } else {
                guard await !store.activeCredentialExists() else {
                    throw AccountStoreError.activeProfileMissing
                }
                originalProfile = nil
            }
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
        }

        do {
            try await desktop.closeDesktop()
        } catch {
            throw OperationError.stage(.closeDesktop, error)
        }

        var failedStage = SwitchStage.activateTargetProvider
        var restoresCredential = false
        do {
            try await configuration.activateProvider(
                id: CodexConfigurationClient.openAIProviderID,
                codexHome: codexHome
            )

            failedStage = .saveCurrentCredential
            if let originalProfile {
                let identity = try await codex.readIdentity(profileHome: codexHome)
                guard identity.matches(originalProfile) else {
                    throw AccountStoreError.activeCredentialMismatch
                }
                try await store.saveCurrentCredential()
            } else if await store.activeCredentialExists() {
                throw AccountStoreError.activeCredentialMismatch
            }

            failedStage = .activateTargetCredential
            restoresCredential = true
            try await store.activateTargetCredential(id: targetID)

            failedStage = .verifyTargetIdentity
            let identity = try await codex.readIdentity(profileHome: codexHome)
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }

            failedStage = .commitActiveAccountID
            try await store.commitActiveAccountID(targetID)
        } catch {
            let restoredError = await restoringOriginalState(
                originalActiveID: originalActiveID,
                originalProviderID: originalProviderID,
                codexHome: codexHome,
                restoresCredential: restoresCredential,
                failedStage: failedStage,
                originalError: error
            )
            throw await reopeningDesktop(after: restoredError)
        }

        do {
            try await desktop.reopenDesktop()
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
    }

    private func restoringOriginalState(
        originalActiveID: UUID?,
        originalProviderID: String,
        codexHome: URL,
        restoresCredential: Bool,
        failedStage: SwitchStage,
        originalError: any Error
    ) async -> OperationError {
        var restorationErrors: [String] = []
        if restoresCredential {
            do {
                if let originalActiveID {
                    try await store.restoreActiveCredential(id: originalActiveID)
                } else {
                    try await store.clearActiveCredential()
                }
            } catch let restorationError {
                restorationErrors.append("credential: \(restorationError.localizedDescription)")
            }
        }
        do {
            try await configuration.activateProvider(id: originalProviderID, codexHome: codexHome)
        } catch let restorationError {
            restorationErrors.append("provider: \(restorationError.localizedDescription)")
        }
        guard !restorationErrors.isEmpty else {
            return OperationError.stage(failedStage, originalError)
        }
        return OperationError(
            stage: failedStage,
            titleKey: "switch_failed",
            messageKey: nil,
            message: """
            \(originalError.localizedDescription) Restoring the previous state also failed: \
            \(restorationErrors.joined(separator: "; "))
            """,
            underlyingDescription: """
            \(String(describing: originalError)); restoration: \
            \(restorationErrors.joined(separator: "; "))
            """
        )
    }

    private func reopeningDesktop(after error: OperationError) async -> OperationError {
        do {
            try await desktop.reopenDesktop()
            return error
        } catch let reopenError {
            return OperationError(
                stage: error.stage,
                titleKey: error.titleKey,
                messageKey: nil,
                message: """
                \(error.message) Reopening Codex Desktop also failed: \
                \(reopenError.localizedDescription)
                """,
                underlyingDescription: """
                \(error.underlyingDescription ?? error.message); reopen: \
                \(String(describing: reopenError))
                """
            )
        }
    }
}
