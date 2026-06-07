import Foundation

/// A utility that reads hardware and operating system information.
///
/// Use `SystemInfoProvider` to retrieve system specifications, such as the active Apple Silicon chip
/// and available unified memory, for display in the application settings or logs.
struct SystemInfoProvider {
    /// The localized name of the active processor (e.g., `"Apple M4 Max"`).
    static var chipName: String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
        return String(cString: name)
    }

    /// Unified memory in human-readable format (e.g. "64 GB").
    static var memoryString: String {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb == gb.rounded() {
            return "\(Int(gb)) GB Unified Memory"
        }
        return String(format: "%.1f GB Unified Memory", gb)
    }

    /// macOS version string (e.g. "macOS 26.5").
    static var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.patchVersion == 0 {
            return "macOS \(v.majorVersion).\(v.minorVersion)"
        }
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
