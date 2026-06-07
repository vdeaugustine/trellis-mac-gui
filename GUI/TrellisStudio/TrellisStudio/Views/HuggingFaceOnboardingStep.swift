import SwiftUI

/// Step 4 of onboarding — HuggingFace authentication and gated model access.
///
/// Use `HuggingFaceOnboardingStep` to prompt the user for their HuggingFace access token,
/// validate it, and verify that they have accepted the licenses for required gated models.
struct HuggingFaceOnboardingStep: View {
    @ObservedObject var hfAuth = HFAuthService.shared
    @Binding var hfToken: String
    @Binding var tokenValid: Bool

    @State private var showCLIInstructions = false
    @State private var tokenSavedToCache = false
    @State private var hasCheckedExisting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            tokenInputSection
            if hfAuth.isTokenValid {
                gatedModelSection
            }
            cliAlternativeSection
        }
        .onAppear { detectExistingTokenOnce() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HuggingFace Access Token")
                .font(.title2).bold()
            Text("Required to download gated model weights. The token authenticates your account so the pipeline can pull DINOv3 and RMBG-2.0.")
                .font(.body)
                .foregroundColor(Theme.slateGray)
        }
    }

    // MARK: - Token Input

    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Auto-detected banner
            if hfAuth.isTokenValid {
                authenticatedBanner
            }

            // Token field + actions
            if !hfAuth.isTokenValid {
                tokenEntryCard
            }
        }
    }

    private var authenticatedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundColor(Theme.successGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("Authenticated as \(hfAuth.username)")
                    .font(.headline)
                    .foregroundColor(Theme.successGreen)
                if tokenSavedToCache {
                    Text("Token saved for Python tools.")
                        .font(.caption)
                        .foregroundColor(Theme.slateGray)
                }
            }
            Spacer()
            Button("Change") {
                hfAuth.isTokenValid = false
                hfAuth.username = ""
                tokenValid = false
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(Theme.slateGray)
        }
        .padding(14)
        .background(Theme.successGreen.opacity(0.08))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(Theme.successGreen.opacity(0.3), lineWidth: 1)
        )
    }

    private var tokenEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Step 1: Get a token
            HStack(alignment: .top, spacing: 12) {
                stepBadge("1")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get an Access Token")
                        .font(.headline)
                    Text("Create a free read-only token on HuggingFace.")
                        .font(.subheadline)
                        .foregroundColor(Theme.slateGray)
                    Button(action: {
                        NSWorkspace.shared.open(HFAuthService.createTokenURL)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Create Token on huggingface.co")
                        }
                        .font(.subheadline)
                        .foregroundColor(Theme.accentIndigo)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.leading, 36)

            // Step 2: Paste it
            HStack(alignment: .top, spacing: 12) {
                stepBadge("2")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste Your Token")
                        .font(.headline)
                    HStack {
                        SecureField("hf_...", text: $hfToken)
                            .textFieldStyle(.roundedBorder)
                        validateButton
                    }
                    validationStatusRow
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.02))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var validateButton: some View {
        Button(hfAuth.isValidating ? "Checking…" : "Verify") {
            Task {
                await hfAuth.performValidation(token: hfToken)
                tokenValid = hfAuth.isTokenValid
                if hfAuth.isTokenValid {
                    tokenSavedToCache = hfAuth.saveTokenToHFCache(hfToken)
                    await hfAuth.checkAllGatedAccess(token: hfToken)
                }
            }
        }
        .disabled(hfAuth.isValidating || hfToken.isEmpty)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hfToken.isEmpty ? Color.white.opacity(0.05) : Theme.accentIndigo)
        .foregroundColor(.white)
        .cornerRadius(Theme.CornerRadius.button)
    }

    @ViewBuilder
    private var validationStatusRow: some View {
        if hfAuth.isValidating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Validating token…")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }
        } else if !hfToken.isEmpty && !hfAuth.isTokenValid && !hfAuth.username.isEmpty {
            // User tried and failed (username would be empty string from failed attempt)
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Theme.errorRed)
                Text("Invalid token or network error")
                    .font(.caption)
                    .foregroundColor(Theme.errorRed)
            }
        }
    }

    // MARK: - Gated Model Access

    private var gatedModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(Theme.accentIndigo)
                Text("Gated Model Access")
                    .font(.headline)
            }

            Text("These models require you to accept their license on HuggingFace. Approval is usually instant.")
                .font(.subheadline)
                .foregroundColor(Theme.slateGray)

            ForEach(hfAuth.gatedModels) { model in
                gatedModelRow(model)
            }

            if !hfAuth.isCheckingAccess && !hfAuth.allGatedAccessGranted {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(Theme.warningAmber)
                    Text("Click each link above, then \"Agree and access\" on the model page. Come back and hit Refresh.")
                        .font(.caption)
                        .foregroundColor(Theme.warningAmber)
                }
                .padding(10)
                .background(Theme.warningAmber.opacity(0.08))
                .cornerRadius(Theme.CornerRadius.button)
            }

            Button(action: {
                Task { await hfAuth.checkAllGatedAccess(token: hfToken) }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Access Status")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.accentIndigo)
            .disabled(hfAuth.isCheckingAccess)
        }
        .padding(20)
        .background(Color.white.opacity(0.02))
        .cornerRadius(Theme.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func gatedModelRow(_ model: GatedModelInfo) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: model.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.subheadline).bold()
                Text(model.repoId)
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                    .monospaced()
            }
            Spacer()
            if model.status == .denied || model.status == .unknown {
                Button("Request Access") {
                    NSWorkspace.shared.open(model.requestURL)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.accentIndigo.opacity(0.2))
                .foregroundColor(Theme.accentIndigo)
                .cornerRadius(Theme.CornerRadius.button)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.01))
        .cornerRadius(Theme.CornerRadius.button)
    }

    @ViewBuilder
    private func statusIcon(for status: GatedModelStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.successGreen)
        case .denied:
            Image(systemName: "lock.fill")
                .foregroundColor(Theme.warningAmber)
        case .checking:
            ProgressView().controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.errorRed)
        case .unknown:
            Image(systemName: "circle.dashed")
                .foregroundColor(Theme.slateGray)
        }
    }

    // MARK: - CLI Alternative

    private var cliAlternativeSection: some View {
        DisclosureGroup(isExpanded: $showCLIInstructions) {
            VStack(alignment: .leading, spacing: 12) {
                Text("If you prefer using the terminal, run these commands from the project directory:")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)

                cliCodeBlock(
                    """
                    source .venv/bin/activate
                    huggingface-cli login
                    """
                )

                Text("The CLI will prompt you for your token and save it automatically. Restart the app after logging in.")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text("Advanced: Use Terminal Instead")
                    .font(.subheadline)
            }
            .foregroundColor(Theme.slateGray)
        }
    }

    private func cliCodeBlock(_ code: String) -> some View {
        HStack {
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .textSelection(.enabled)
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(hex: 0x0A0C12))
        .cornerRadius(Theme.CornerRadius.button)
    }

    // MARK: - Helpers

    private func stepBadge(_ number: String) -> some View {
        Circle()
            .fill(Theme.accentIndigo.opacity(0.2))
            .frame(width: 24, height: 24)
            .overlay(
                Text(number)
                    .font(.system(.caption2, design: .rounded))
                    .bold()
                    .foregroundColor(Theme.accentIndigo)
            )
    }

    private func detectExistingTokenOnce() {
        guard !hasCheckedExisting else { return }
        hasCheckedExisting = true

        if let existing = hfAuth.detectExistingToken(), !existing.isEmpty {
            hfToken = existing
            Task {
                await hfAuth.performValidation(token: existing)
                await MainActor.run { tokenValid = hfAuth.isTokenValid }
                if hfAuth.isTokenValid {
                    tokenSavedToCache = true
                    await hfAuth.checkAllGatedAccess(token: existing)
                }
            }
        }
    }
}
