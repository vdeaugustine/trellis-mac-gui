import Foundation

/// Status of access to a specific gated HuggingFace model repository.
enum GatedModelStatus: Equatable {
    case unknown
    case checking
    case granted
    case denied
    case error(String)
}

/// Represents a gated model that requires explicit access approval.
struct GatedModelInfo: Identifiable {
    let id: String
    let repoId: String
    let displayName: String
    let requestURL: URL
    var status: GatedModelStatus = .unknown
}

/// HuggingFace authentication and access management.
final class HFAuthService: ObservableObject {
    static let shared = HFAuthService()

    /// Username from whoami API after validation.
    @Published var username: String = ""

    /// Whether the current token has been validated.
    @Published var isTokenValid: Bool = false

    /// Whether a validation request is in progress.
    @Published var isValidating: Bool = false

    /// Gated models required by Trellis.
    @Published var gatedModels: [GatedModelInfo] = [
        GatedModelInfo(
            id: "dinov3",
            repoId: "facebook/dinov3-vitl16-pretrain-lvd1689m",
            displayName: "DINOv3 (Meta)",
            requestURL: URL(string: "https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m")!
        ),
        GatedModelInfo(
            id: "rmbg",
            repoId: "briaai/RMBG-2.0",
            displayName: "RMBG-2.0 (BRIA AI)",
            requestURL: URL(string: "https://huggingface.co/briaai/RMBG-2.0")!
        )
    ]

    private let hfCacheTokenPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.cache/huggingface/token"
    }()

    private init() {}

    // MARK: - Token Detection

    /// Checks `~/.cache/huggingface/token` for an existing token from CLI login.
    func detectExistingToken() -> String? {
        guard FileManager.default.fileExists(atPath: hfCacheTokenPath),
              let contents = try? String(contentsOfFile: hfCacheTokenPath, encoding: .utf8) else {
            return nil
        }
        let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - Token Validation

    /// Validates a token against the HuggingFace whoami API.
    /// Returns the username on success, nil on failure.
    func validateToken(_ token: String) async -> String? {
        guard !token.isEmpty else { return nil }

        var request = URLRequest(url: URL(string: "https://huggingface.co/api/whoami-v2")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["name"] as? String {
                return name
            }
            return "authenticated"
        } catch {
            return nil
        }
    }

    /// Full validation flow: validates token, updates published state.
    @MainActor
    func performValidation(token: String) async {
        isValidating = true
        defer { isValidating = false }

        if let name = await validateToken(token) {
            username = name
            isTokenValid = true
        } else {
            username = ""
            isTokenValid = false
        }
    }

    // MARK: - Gated Model Access

    /// Checks whether the given token has access to a specific gated model.
    func checkModelAccess(token: String, repoId: String) async -> GatedModelStatus {
        guard !token.isEmpty else { return .error("No token") }

        var request = URLRequest(url: URL(string: "https://huggingface.co/api/models/\(repoId)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("No response")
            }
            switch http.statusCode {
            case 200: return .granted
            case 401: return .error("Invalid token")
            case 403: return .denied
            default: return .error("HTTP \(http.statusCode)")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Checks access for all gated models and updates published state.
    @MainActor
    func checkAllGatedAccess(token: String) async {
        for index in gatedModels.indices {
            gatedModels[index].status = .checking
        }

        for index in gatedModels.indices {
            let status = await checkModelAccess(
                token: token,
                repoId: gatedModels[index].repoId
            )
            gatedModels[index].status = status
        }
    }

    // MARK: - Token Persistence

    /// Writes the token to `~/.cache/huggingface/token` so Python tools find it natively.
    func saveTokenToHFCache(_ token: String) -> Bool {
        let cacheDir = (hfCacheTokenPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: cacheDir,
                withIntermediateDirectories: true
            )
            try token.write(toFile: hfCacheTokenPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Whether all gated models have been granted access.
    var allGatedAccessGranted: Bool {
        gatedModels.allSatisfy { $0.status == .granted }
    }

    /// Whether any gated model access check is still in progress.
    var isCheckingAccess: Bool {
        gatedModels.contains { $0.status == .checking }
    }

    /// URL to create a new read-only HuggingFace token.
    static let createTokenURL = URL(
        string: "https://huggingface.co/settings/tokens/new?tokenType=read"
    )!
}
