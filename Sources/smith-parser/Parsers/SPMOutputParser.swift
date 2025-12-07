import Foundation

// MARK: - SPM Command Types

public enum SPMCommand: String, Codable, CaseIterable {
    case dumpPackage = "dump-package"
    case showDependencies = "show-dependencies"
    case resolve = "resolve"
    case describe = "describe"
    case update = "update"
    case unknown = "unknown"
}

// MARK: - Dependency Types

public enum SPMDependencyType: String, Codable {
    case sourceControl = "source-control"
    case binary = "binary"
    case registry = "registry"
}

// MARK: - SPM-Specific Models

public struct SPMDependency: Codable {
    public let name: String
    public let version: String
    public let type: SPMDependencyType
    public let url: String?

    public init(name: String, version: String, type: SPMDependencyType, url: String? = nil) {
        self.name = name
        self.version = version
        self.type = type
        self.url = url
    }
}

public struct SPMTarget: Codable {
    public let name: String
    public let type: String
    public let dependencies: [String]

    public init(name: String, type: String, dependencies: [String] = []) {
        self.name = name
        self.type = type
        self.dependencies = dependencies
    }
}

public struct SPMInfo: Codable {
    public let command: SPMCommand
    public let success: Bool
    public let targets: [SPMTarget]?
    public let dependencies: [SPMDependency]?
    public let packageName: String?
    public let version: String?

    public init(
        command: SPMCommand,
        success: Bool,
        targets: [SPMTarget]? = nil,
        dependencies: [SPMDependency]? = nil,
        packageName: String? = nil,
        version: String? = nil
    ) {
        self.command = command
        self.success = success
        self.targets = targets
        self.dependencies = dependencies
        self.packageName = packageName
        self.version = version
    }
}

// MARK: - SPM Output Parser

public class SPMOutputParser {
    public init() {}

    /// Detects if the input is SPM output
    public static func canParse(_ input: String) -> Bool {
        let output = input.lowercased()

        // Check for dump-package output (JSON format) - need both "name" and something else
        if (output.contains("\"name\"") && output.contains("\"targets\"")) ||
           (output.contains("\"name\"") && output.contains("\"products\"")) ||
           (output.contains("\"name\"") && output.contains("\"dependencies\"")) {
            return true
        }

        // Check for show-dependencies output (tree format)
        if output.contains("├─") || output.contains("└─") || output.contains("│") ||
           output.contains("dependencies:") {
            return true
        }

        // Check for resolve/update output
        if output.contains("resolving") || output.contains("fetching") ||
           output.contains("resolved") || output.contains("updating") ||
           output.contains("cloning") {
            return true
        }

        // Check for describe output
        if output.contains("package name:") || output.contains("package version:") {
            return true
        }

        return false
    }

    /// Parses SPM output and returns a ParsedBuildResult
    public func parse(_ input: String) -> ParsedBuildResult {
        let commandType = detectCommandType(from: input)

        switch commandType {
        case .dumpPackage:
            return parseDumpPackage(input)

        case .showDependencies:
            return parseShowDependencies(input)

        case .resolve, .update:
            return parseResolveUpdate(input, command: commandType)

        case .describe:
            return parseDescribe(input)

        default:
            return createUnknownResult(input)
        }
    }

    // MARK: - Command Detection

    private func detectCommandType(from output: String) -> SPMCommand {
        let output = output.lowercased()

        // Check for dump-package output (JSON format)
        // Check for "name" field or any JSON-like structure starting with {
        if output.contains("\"name\"") || output.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            return .dumpPackage
        }

        // Check for show-dependencies output (tree format)
        // Check for tree characters OR "dependencies:" header
        if output.contains("├─") || output.contains("└─") || output.contains("│") ||
           output.contains("dependencies:") {
            return .showDependencies
        }

        // Check for resolve output
        if output.contains("resolving") || output.contains("fetching") ||
           output.contains("resolved") || output.contains("updating") {
            return .resolve
        }

        // Check for describe output
        if output.contains("package name:") || output.contains("package version:") {
            return .describe
        }

        // Check for update output
        if output.contains("updating") || output.contains("updated") ||
           output.contains("checking out") {
            return .update
        }

        return .unknown
    }

    // MARK: - Dump Package Parser

    private func parseDumpPackage(_ input: String) -> ParsedBuildResult {
        var diagnostics: [Diagnostic] = []
        var metrics = BuildMetrics()
        var spmInfoDict: [String: Any]?

        do {
            guard let data = input.data(using: .utf8) else {
                let diagnostic = Diagnostic(
                    severity: .error,
                    category: .build,
                    message: "Invalid UTF-8"
                )
                diagnostics.append(diagnostic)
                metrics.errorCount += 1
                return ParsedBuildResult(
                    format: .spm,
                    status: .failed,
                    diagnostics: diagnostics,
                    metrics: metrics,
                    timing: BuildTiming(totalDuration: 0.0),
                    spmInfo: spmInfoDict
                )
            }

            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dictionary = json as? [String: Any] else {
                let diagnostic = Diagnostic(
                    severity: .error,
                    category: .build,
                    message: "Invalid JSON format"
                )
                diagnostics.append(diagnostic)
                metrics.errorCount += 1
                return ParsedBuildResult(
                    format: .spm,
                    status: .failed,
                    diagnostics: diagnostics,
                    metrics: metrics,
                    timing: BuildTiming(totalDuration: 0.0),
                    spmInfo: spmInfoDict
                )
            }

            spmInfoDict = convertSPMInfoToDict(parsePackageDictionary(dictionary))

        } catch {
            let diagnostic = Diagnostic(
                severity: .error,
                category: .build,
                message: "Failed to parse Package.swift JSON: \(error.localizedDescription)"
            )
            diagnostics.append(diagnostic)
            metrics.errorCount += 1
        }

        return ParsedBuildResult(
            format: .spm,
            status: diagnostics.contains(where: { $0.severity == .error || $0.severity == .critical }) ? .failed : .success,
            diagnostics: diagnostics,
            metrics: metrics,
            timing: BuildTiming(totalDuration: 0.0),
            spmInfo: spmInfoDict
        )
    }

    private func parsePackageDictionary(_ dict: [String: Any]) -> SPMInfo {
        var targets: [SPMTarget] = []
        var dependencies: [SPMDependency] = []
        var packageName: String?
        var version: String?

        // Parse package name and version
        packageName = dict["name"] as? String

        if let products = dict["products"] as? [[String: Any]] {
            for product in products {
                if let targetName = product["name"] as? String {
                    let targetType = (product["type"] as? [String: String])?["name"] ?? "unknown"
                    targets.append(SPMTarget(name: targetName, type: targetType))
                }
            }
        }

        // Parse dependencies
        if let dependenciesArray = dict["dependencies"] as? [[String: Any]] {
            for depDict in dependenciesArray {
                if let dependency = parseDependencyFromDict(depDict) {
                    dependencies.append(dependency)
                }
            }
        }

        return SPMInfo(
            command: .dumpPackage,
            success: true,
            targets: targets.isEmpty ? nil : targets,
            dependencies: dependencies.isEmpty ? nil : dependencies,
            packageName: packageName,
            version: version
        )
    }

    private func parseDependencyFromDict(_ dict: [String: Any]) -> SPMDependency? {
        var depName = ""
        var url: String?
        var version = "unspecified"

        // Handle the complex dependency structure from dump-package
        if let sourceControl = dict["sourceControl"] as? [Any],
           let firstSourceControl = sourceControl.first as? [String: Any],
           let identity = firstSourceControl["identity"] as? String {
            depName = identity

            // Extract URL from location
            if let location = firstSourceControl["location"] as? [String: Any],
               let remote = location["remote"] as? [Any],
               let firstRemote = remote.first as? [String: Any],
               let urlString = firstRemote["urlString"] as? String {
                url = urlString
            }

            // Extract version from requirement
            if let requirement = firstSourceControl["requirement"] as? [String: Any],
               let range = requirement["range"] as? [Any],
               let firstRange = range.first as? [String: Any],
               let lowerBound = firstRange["lowerBound"] as? String,
               let upperBound = firstRange["upperBound"] as? String {
                version = "\(lowerBound) - \(upperBound)"
            }
        }

        // Try legacy format for backward compatibility
        if depName.isEmpty {
            if let legacyUrl = dict["url"] as? String {
                url = legacyUrl
                depName = dict["name"] as? String ?? extractNameFromURL(legacyUrl)
                version = extractVersion(from: dict)
            } else if let path = dict["path"] as? String {
                depName = dict["name"] as? String ?? extractNameFromPath(path)
                return SPMDependency(name: depName, version: "local", type: .sourceControl)
            }
        }

        guard !depName.isEmpty else { return nil }

        let dependencyType: SPMDependencyType
        if let dependencyUrl = url {
            if dependencyUrl.hasSuffix(".binary") {
                dependencyType = .binary
            } else if dependencyUrl.contains("@swift-package-registry") {
                dependencyType = .registry
            } else {
                dependencyType = .sourceControl
            }
            return SPMDependency(name: depName, version: version, type: dependencyType, url: dependencyUrl)
        }

        return SPMDependency(name: depName, version: version, type: .sourceControl)
    }

    // MARK: - Show Dependencies Parser

    private func parseShowDependencies(_ input: String) -> ParsedBuildResult {
        let lines = input.components(separatedBy: .newlines)
        var dependencies: [SPMDependency] = []
        var diagnostics: [Diagnostic] = []
        var metrics = BuildMetrics()
        var foundExplicitDependenciesHeader = false  // Track if we explicitly found "Dependencies:" header
        var foundDependenciesAutoDetect = false      // Track if we auto-detected via tree chars
        var rootPackageLine: String? = nil
        var firstDependencyIndent: Int? = nil
        var index = 0

        for line in lines {
            defer { index += 1 }
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            // Get indentation level of the original line
            let indent = line.count - line.trimmingCharacters(in: .whitespaces).count

            // Skip empty lines and headers
            if trimmedLine.isEmpty {
                continue
            }

            // Track when we've found the explicit Dependencies header
            if trimmedLine.contains("Dependencies:") {
                foundExplicitDependenciesHeader = true
                continue
            }

            if trimmedLine.lowercased().contains("package:") {
                // This is a package declaration, not a dependency
                continue
            }

            if trimmedLine.lowercased().contains("no dependencies") {
                foundExplicitDependenciesHeader = true
                continue
            }

            // Check for errors and warnings FIRST
            // This handles lines like "error: message" or "warning: message"
            let lowercased = trimmedLine.lowercased()
            if (lowercased.hasPrefix("error:") || lowercased.hasPrefix("warning:")) {
                let severity = lowercased.hasPrefix("error:") ? DiagnosticSeverity.error : DiagnosticSeverity.warning
                diagnostics.append(Diagnostic(
                    severity: severity,
                    category: .dependency,
                    message: trimmedLine
                ))
                if severity == .error {
                    metrics.errorCount += 1
                } else {
                    metrics.warningCount += 1
                }
                continue
            }

            // Check if this line has tree characters - if so, we've found dependencies
            let hasTreeChars = trimmedLine.contains("├") || trimmedLine.contains("└")
            if hasTreeChars {
                foundDependenciesAutoDetect = true
            }

            let foundDependenciesSection = foundExplicitDependenciesHeader || foundDependenciesAutoDetect

            // Only parse as dependency if we've found the Dependencies section
            if foundDependenciesSection {
                // Lines with tree characters may be dependencies or root package
                if hasTreeChars {
                    // Track first dependency indentation
                    if firstDependencyIndent == nil {
                        firstDependencyIndent = indent

                        // Check if this might be a root package by looking ahead
                        // Root packages are the first line and have children with more indentation
                        var isRootPackage = false
                        if foundExplicitDependenciesHeader && rootPackageLine == nil && index + 1 < lines.count {
                            // Look at the next few lines to see if they're more indented
                            for nextIdx in (index + 1)..<min(index + 3, lines.count) {
                                let nextLine = lines[nextIdx]
                                let nextIndent = nextLine.count - nextLine.trimmingCharacters(in: .whitespaces).count
                                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                                let nextHasTreeChars = nextTrimmed.contains("├") || nextTrimmed.contains("└")

                                if nextHasTreeChars && nextIndent > indent {
                                    isRootPackage = true
                                    break
                                }
                            }
                        }

                        if isRootPackage {
                            rootPackageLine = trimmedLine
                            continue
                        }
                    }

                    if let dependency = parseDependencyLine(trimmedLine) {
                        dependencies.append(dependency)
                    }
                } else {
                    // For non-tree-char lines, check if they could be dependencies
                    // (for formats without tree characters)
                    if !trimmedLine.isEmpty &&
                       (trimmedLine.split(separator: " ").count > 1 ||
                        trimmedLine.contains("@") || trimmedLine.contains("(") ||
                        trimmedLine.contains("[") || trimmedLine.contains("<")) {
                        // This looks like a dependency, not a root package
                        if let dependency = parseDependencyLine(trimmedLine) {
                            dependencies.append(dependency)
                        }
                    }
                }
            }
        }

        return ParsedBuildResult(
            format: .spm,
            status: diagnostics.contains(where: { $0.severity == .error }) ? .failed : ((foundExplicitDependenciesHeader || foundDependenciesAutoDetect) ? .success : .unknown),
            diagnostics: diagnostics,
            metrics: BuildMetrics(errorCount: metrics.errorCount, warningCount: metrics.warningCount, targetCount: dependencies.count),
            timing: BuildTiming(totalDuration: 0.0)
        )
    }

    private func parseDependencyLine(_ line: String) -> SPMDependency? {
        // Remove tree characters and whitespace (├── └── │── )
        var cleanLine = line
        // Remove tree characters using character set
        let treeChars = CharacterSet(charactersIn: "├└│─ ")
        cleanLine = cleanLine.trimmingCharacters(in: treeChars)
        // Also remove tree characters from the middle of the line
        cleanLine = cleanLine.replacingOccurrences(of: "├─", with: "")
        cleanLine = cleanLine.replacingOccurrences(of: "└─", with: "")
        cleanLine = cleanLine.replacingOccurrences(of: "│", with: "")
        cleanLine = cleanLine.replacingOccurrences(of: "─", with: "")
        let trimmed = cleanLine.trimmingCharacters(in: .whitespaces)

        // Skip empty lines
        guard !trimmed.isEmpty else { return nil }

        // Parse different dependency formats:
        // 1. "package-name (version)"
        // 2. "package-name@version"
        // 3. "package-name [url]"
        // 4. "package-name<url@version>"
        // 5. "package-name version" (space separated)
        // 6. "package-name revision: xxx" or "branch: xxx" or "exact: xxx"
        // 7. "package-name" (no version)

        // Format: "package-name (version)" e.g., "swift-algorithms (1.0.0..<2.0.0)"
        if let range = trimmed.range(of: #" \([^)]+\)$"#, options: .regularExpression) {
            let name = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let versionWithParens = String(trimmed[range])
            let version = String(versionWithParens.dropFirst(2).dropLast(1)) // Remove " (" and ")"

            return SPMDependency(
                name: name,
                version: version,
                type: determineDependencyType(from: version)
            )
        }

        // Format: "package-name@version"
        if let atIndex = trimmed.firstIndex(of: "@") {
            let name = String(trimmed[..<atIndex])
            let version = String(trimmed[atIndex...].dropFirst())

            return SPMDependency(
                name: name,
                version: version,
                type: determineDependencyType(from: version)
            )
        }

        // Format: "package-name [url]"
        if let bracketRange = trimmed.range(of: #" \[[^\]]+\]$"#, options: .regularExpression) {
            let name = String(trimmed[..<bracketRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let urlWithBrackets = String(trimmed[bracketRange])
            let url = String(urlWithBrackets.dropFirst(2).dropLast(1)) // Remove " [" and "]"

            return SPMDependency(
                name: name,
                version: "source-control",
                type: .sourceControl,
                url: url
            )
        }

        // Format: "package-name<url@version>"
        if let urlRange = trimmed.range(of: #"<[^>]+>"#, options: .regularExpression) {
            let name = String(trimmed[..<urlRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let urlWithVersion = String(trimmed[urlRange].dropFirst().dropLast()) // Remove < >

            // Split URL and version
            let components = urlWithVersion.components(separatedBy: "@")
            let url = components.first ?? urlWithVersion
            let version = components.count > 1 ? components[1] : "unspecified"

            return SPMDependency(
                name: name,
                version: version,
                type: .sourceControl,
                url: url
            )
        }

        // Format: "package-name revision: xxx" or "branch: xxx" or "exact: xxx"
        if trimmed.contains(" revision:") || trimmed.contains(" branch:") || trimmed.contains(" exact:") {
            let parts = trimmed.components(separatedBy: " ")
            if parts.count >= 2 {
                let name = parts[0]
                let version = parts.dropFirst().joined(separator: " ")
                return SPMDependency(
                    name: name,
                    version: version,
                    type: .sourceControl
                )
            }
        }

        // Format: "package-name version" (space separated, where version looks like a version number)
        let spaceParts = trimmed.components(separatedBy: " ")
        if spaceParts.count == 2 {
            let possibleVersion = spaceParts[1]
            // Check if the second part looks like a version (starts with digit or has dots)
            if possibleVersion.first?.isNumber == true || possibleVersion.contains(".") {
                return SPMDependency(
                    name: spaceParts[0],
                    version: possibleVersion,
                    type: determineDependencyType(from: possibleVersion)
                )
            }
        }

        // Format: "package-name" (no version specified)
        // Only if it looks like a package name (no spaces, or entire thing is a name)
        if !trimmed.contains(" ") {
            return SPMDependency(
                name: trimmed,
                version: "unspecified",
                type: .sourceControl
            )
        }

        return nil
    }

    private func determineDependencyType(from version: String) -> SPMDependencyType {
        // Check for explicit type indicators in version string
        if version.lowercased().contains("branch:") || version.lowercased().contains("revision:") {
            return .sourceControl
        } else if version.lowercased().contains(".binary") || version.lowercased().contains("xcframework") {
            return .binary
        } else if version.contains("..<") || version.contains(" - ") || version.contains("exact:") {
            // Version ranges or exact versions typically indicate registry dependencies
            return .registry
        } else {
            // Default to source control for simple version numbers or branch names
            return .sourceControl
        }
    }

    // MARK: - Resolve/Update Parser

    private func parseResolveUpdate(_ input: String, command: SPMCommand) -> ParsedBuildResult {
        var diagnostics: [Diagnostic] = []
        var metrics = BuildMetrics()
        let lines = input.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for error messages
            if trimmed.lowercased().contains("error:") ||
               trimmed.lowercased().contains("failed") {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    category: .dependency,
                    message: trimmed
                ))
                metrics.errorCount += 1
            } else if trimmed.lowercased().contains("warning:") {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    category: .dependency,
                    message: trimmed
                ))
                metrics.warningCount += 1
            } else if trimmed.lowercased().contains("resolving") ||
                      trimmed.lowercased().contains("cloning") ||
                      trimmed.lowercased().contains("fetching") ||
                      trimmed.lowercased().contains("completed") {
                // These are info messages
                diagnostics.append(Diagnostic(
                    severity: .info,
                    category: .dependency,
                    message: trimmed
                ))
                metrics.infoCount += 1
            }
        }

        return ParsedBuildResult(
            format: .spm,
            status: diagnostics.contains(where: { $0.severity == .error }) ? .failed : .success,
            diagnostics: diagnostics,
            metrics: metrics,
            timing: BuildTiming(totalDuration: 0.0)
        )
    }

    // MARK: - Describe Parser

    private func parseDescribe(_ input: String) -> ParsedBuildResult {
        var diagnostics: [Diagnostic] = []
        var metrics = BuildMetrics()
        let lines = input.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.lowercased().contains("error:") {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    category: .build,
                    message: trimmed
                ))
                metrics.errorCount += 1
            } else if trimmed.lowercased().contains("warning:") {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    category: .build,
                    message: trimmed
                ))
                metrics.warningCount += 1
            }
        }

        return ParsedBuildResult(
            format: .spm,
            status: diagnostics.contains(where: { $0.severity == .error }) ? .failed : .success,
            diagnostics: diagnostics,
            metrics: metrics,
            timing: BuildTiming(totalDuration: 0.0)
        )
    }

    // MARK: - Helper Methods

    private func extractNameFromURL(_ url: String) -> String {
        let components = url.components(separatedBy: "/")
        return components.last?.replacingOccurrences(of: ".git", with: "") ?? "unknown"
    }

    private func extractNameFromPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        return components.last ?? "unknown"
    }

    private func extractVersion(from dependency: [String: Any]) -> String {
        guard let requirement = dependency["requirement"] as? [String: Any] else {
            return "unspecified"
        }

        if let range = requirement["range"] as? [String], !range.isEmpty {
            return range.joined(separator: ", ")
        } else if let branch = requirement["branch"] as? String {
            return "branch: \(branch)"
        } else if let revision = requirement["revision"] as? String {
            return "revision: \(revision.prefix(7))"
        } else if let exact = requirement["exact"] as? String {
            return exact
        }

        return "unspecified"
    }

    private func createErrorResult(_ message: String, input: String) -> ParsedBuildResult {
        let diagnostic = Diagnostic(
            severity: .error,
            category: .build,
            message: message
        )

        return ParsedBuildResult(
            format: .spm,
            status: .failed,
            diagnostics: [diagnostic],
            metrics: BuildMetrics(),
            timing: BuildTiming(totalDuration: 0.0)
        )
    }

    private func createUnknownResult(_ input: String) -> ParsedBuildResult {
        return ParsedBuildResult(
            format: .spm,
            status: .unknown,
            diagnostics: [],
            metrics: BuildMetrics(),
            timing: BuildTiming(totalDuration: 0.0)
        )
    }

    private func convertSPMInfoToDict(_ info: SPMInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "command": info.command.rawValue,
            "success": info.success
        ]

        if let targets = info.targets {
            dict["targets"] = targets.map { target in
                [
                    "name": target.name,
                    "type": target.type,
                    "dependencies": target.dependencies
                ]
            }
        }

        if let dependencies = info.dependencies {
            dict["dependencies"] = dependencies.map { dep in
                var depDict: [String: Any] = [
                    "name": dep.name,
                    "version": dep.version,
                    "type": dep.type.rawValue
                ]
                if let url = dep.url {
                    depDict["url"] = url
                }
                return depDict
            }
        }

        if let packageName = info.packageName {
            dict["packageName"] = packageName
        }

        if let version = info.version {
            dict["version"] = version
        }

        return dict
    }
}
