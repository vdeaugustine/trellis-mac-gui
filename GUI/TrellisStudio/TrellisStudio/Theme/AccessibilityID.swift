import Foundation

/// Centralized accessibility identifiers for UI testing.
///
/// Use `AccessibilityID` to assign stable, hardcoded identifiers to user interface elements.
/// Keeping all IDs in one place helps avoid typos and enables autocomplete during UI testing.
enum AccessibilityID {
    // MARK: - Content View
    static let daemonStatusDot = "daemon-status-dot"
    static let daemonStatusText = "daemon-status-text"
    static let daemonRestartButton = "daemon-restart-button"
    static let errorBanner = "error-banner"
    static let errorBannerDismiss = "error-banner-dismiss"

    // MARK: - Input Panel
    static let dropZone = "input-drop-zone"
    static let browseButton = "input-browse-button"
    static let imagePreview = "input-image-preview"
    static let removeImageButton = "input-remove-image"
    static let imageFilename = "input-image-filename"

    // MARK: - Parameter Panel
    static let seedTextField = "param-seed-field"
    static let randomizeSeedButton = "param-randomize-seed"
    static let pipelinePicker = "param-pipeline-picker"
    static let textureSizePicker = "param-texture-size-picker"
    static let noTextureToggle = "param-no-texture-toggle"
    static let generateButton = "param-generate-button"
    static let statusHint = "param-status-hint"
    static let presetFastDraft = "preset-fast-draft"
    static let presetBalanced = "preset-balanced"
    static let presetMaxQuality = "preset-max-quality"

    // MARK: - Sidebar
    static let newGenerationButton = "sidebar-new-generation"
    static let batchModeToggle = "sidebar-batch-mode"
    static let searchField = "sidebar-search-field"

    // MARK: - Generation Progress
    static let progressTitle = "progress-title"
    static let progressErrorMessage = "progress-error-message"
    static let progressVertexCount = "progress-vertex-count"
    static let progressTriangleCount = "progress-triangle-count"

    // MARK: - Onboarding
    static let onboardingView = "onboarding-view"

    // MARK: - Settings
    static let settingsView = "settings-view"
}
