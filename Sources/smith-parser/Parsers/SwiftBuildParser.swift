import Foundation

/// SwiftBuildParser - Parses Swift Package Manager and Swift compiler output
///
/// Extracts errors, warnings, build status, timing, and file compilation information
/// from `swift build`, `swift test`, and related SPM command output.
public struct SwiftBuildParser {

    public init() {}

    /// Parse Swift/SPM build output and return structured result
    /// - Parameter output: Raw swift build output string
    /// - Returns: ParsedBuildResult with extracted information
    public func parse(_ output: String) -> ParsedBuildResult {
        var diagnostics: [Diagnostic] = []
        var metrics = BuildMetrics()
        var status: BuildStatus = .unknown
        var timing = BuildTiming()

        // Split output into lines for analysis
        let lines = output.components(separatedBy: .newlines)

        // Total duration tracking
        var totalDuration: TimeInterval = 0.0

        // Track unique modules/targets for accurate target count
        var linkedTargets = Set<String>()

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmedLine.isEmpty else { continue }

            // Detect build phases (for logging/verbose output)
            // Note: Phase detection available for future metrics extension

            // Detect build status
            if trimmedLine.contains("Build complete!") ||
               trimmedLine.contains("build complete") ||
               trimmedLine.contains("BUILD SUCCEEDED") {
                status = .success
            } else if trimmedLine.contains("build failed") ||
                      trimmedLine.contains("BUILD FAILED") ||
                      trimmedLine.contains("error: build failed") {
                status = .failed
            }

            // Parse errors - Swift compiler patterns
            // Pattern: /path/file.swift:line:column: error: message
            // Also: error: message (no path)
            if trimmedLine.contains(": error:") || trimmedLine.hasPrefix("error:") {
                let diagnostic = parseDiagnostic(from: trimmedLine, severity: .error, lineNumber: index + 1)
                diagnostics.append(diagnostic)
                metrics.errorCount += 1
            }

            // Parse warnings
            if trimmedLine.contains(": warning:") || trimmedLine.hasPrefix("warning:") {
                let diagnostic = parseDiagnostic(from: trimmedLine, severity: .warning, lineNumber: index + 1)
                diagnostics.append(diagnostic)
                metrics.warningCount += 1
            }

            // Parse notes
            if trimmedLine.contains(": note:") || trimmedLine.hasPrefix("note:") {
                let diagnostic = parseDiagnostic(from: trimmedLine, severity: .info, lineNumber: index + 1)
                diagnostics.append(diagnostic)
                metrics.infoCount += 1
            }

            // Parse file compilation - SPM patterns
            // Pattern: "Compiling ModuleName filename.swift"
            if trimmedLine.hasPrefix("Compiling") && trimmedLine.contains(".swift") {
                let filename = extractFilename(from: trimmedLine)
                if !metrics.compiledFiles.contains(filename) {
                    metrics.compiledFiles.append(filename)
                }
            }

            // Extract timing from build output
            // Pattern: "X.Xs" duration markers (e.g., "Build complete! (12.34s)")
            if let duration = extractDuration(from: trimmedLine) {
                totalDuration = max(totalDuration, duration)
            }

            // Parse linking targets - these are the real targets
            if trimmedLine.hasPrefix("Linking") {
                let linkTarget = trimmedLine.replacingOccurrences(of: "Linking ", with: "").trimmingCharacters(in: .whitespaces)
                if !linkTarget.isEmpty {
                    linkedTargets.insert(linkTarget)
                }
            }
        }

        // Set target count from unique linked targets
        metrics.targetCount = linkedTargets.count

        // Determine final status
        // If we have errors, status is failed regardless of "Build complete!" messages
        if metrics.errorCount > 0 {
            status = .failed
        } else if status == .unknown {
            // If no explicit status was found and no errors, consider it success
            status = .success
        }

        timing.totalDuration = totalDuration
        metrics.totalDuration = totalDuration

        return ParsedBuildResult(
            format: .swift,
            status: status,
            diagnostics: diagnostics,
            metrics: metrics,
            timing: timing
        )
    }

    // MARK: - Private Helpers

    private func parseDiagnostic(from line: String, severity: DiagnosticSeverity, lineNumber: Int) -> Diagnostic {
        var filePath: String? = nil
        var lineNum: Int? = nil
        var column: Int? = nil
        var message: String = line
        var location: String = ""
        var category: DiagnosticCategory = .compilation

        // Swift compiler diagnostic pattern: /path/file.swift:line:column: severity: message
        // Also handles: <module-includes>:1:1: note: ...
        // Also handles: error: message (no path prefix)

        // Check if this is a path-less error/warning/note
        if line.hasPrefix("error:") || line.hasPrefix("warning:") || line.hasPrefix("note:") {
            // No path, just extract the message
            let parts = line.components(separatedBy: ": ")
            if parts.count >= 2 {
                message = Array(parts.dropFirst()).joined(separator: ": ")
            } else {
                message = line
            }
        } else {
            // Split by ": " to separate location from message
            let colonPattern = line.components(separatedBy: ": ")

            if colonPattern.count >= 2 {
                let locationPart = colonPattern[0].trimmingCharacters(in: .whitespaces)
                location = locationPart

                // Extract file:line:column from location
                let locationComponents = locationPart.components(separatedBy: ":")
                if locationComponents.count >= 1 && !locationComponents[0].isEmpty {
                    filePath = locationComponents[0]
                }
                if locationComponents.count >= 2, let ln = Int(locationComponents[1]) {
                    lineNum = ln
                }
                if locationComponents.count >= 3, let col = Int(locationComponents[2]) {
                    column = col
                }

                // Extract message (skip severity label)
                let messageComponents = Array(colonPattern.dropFirst())
                message = messageComponents.joined(separator: ": ")

                // Remove severity prefix from message
                let severityLabels = ["error:", "warning:", "note:"]
                for label in severityLabels {
                    if message.lowercased().hasPrefix(label) {
                        message = String(message.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
                        break
                    } else if message.lowercased().hasPrefix(" \(label)") {
                        message = String(message.dropFirst(label.count + 1)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }
        }

        // Categorize based on message content
        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("linker") || lowercasedMessage.contains("undefined symbol") || lowercasedMessage.contains("ld:") {
            category = .linking
        } else if lowercasedMessage.contains("package") ||
                  lowercasedMessage.contains(" dependency") ||
                  lowercasedMessage.contains("dependency ") ||
                  (lowercasedMessage.contains("resolve") && !lowercasedMessage.contains("unresolved")) {
            category = .dependency
        }

        return Diagnostic(
            severity: severity,
            category: category,
            message: message,
            location: location.isEmpty ? nil : location,
            lineNumber: lineNum ?? lineNumber,
            column: column,
            filePath: filePath
        )
    }

    private func extractFilename(from line: String) -> String {
        // SPM pattern: "Compiling ModuleName filename.swift"
        let components = line.components(separatedBy: " ")
        for component in components.reversed() {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(".swift") {
                // Return just the filename without path
                return (trimmed as NSString).lastPathComponent
            }
        }
        return "unknown.swift"
    }

    private func extractDuration(from line: String) -> TimeInterval? {
        // Match patterns like "Build complete! (12.34s)" or "Xs" or "X.XXs"
        let patterns = [
            "\\(([0-9.]+)s\\)",                    // (12.34s)
            "\\[([0-9.]+)s\\]",                    // [12.34s]
            "completed.*?([0-9.]+)s",              // completed in 12.34s
            "([0-9]+\\.[0-9]+)s(?:\\s|$)",         // 12.34s at word boundary
            "([0-9]+)s(?:\\s|$)"                   // 12s at word boundary
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, options: [], range: range),
                   let durationRange = Range(match.range(at: 1), in: line),
                   let duration = Double(line[durationRange]) {
                    return duration
                }
            }
        }
        return nil
    }
}

// MARK: - Format Detection Extension

extension SwiftBuildParser {
    /// Check if the input appears to be Swift/SPM build output
    public static func canParse(_ input: String) -> Bool {
        let swiftPatterns = [
            "Swift Compiler",
            "swift build",
            "swift test",
            "Apple Swift version",
            "Building for",
            "Compiling Swift Module",
            "swift-package",
            "Fetching https://",
            "Cloning https://",
            "Resolving https://",
            "SwiftPM",
            ".build/checkouts",
            "Compiling ",
            "Linking "
        ]

        // Check case-sensitive patterns first
        for pattern in swiftPatterns {
            if input.contains(pattern) {
                return true
            }
        }

        // Check case-insensitive patterns
        let lowercased = input.lowercased()
        if lowercased.contains("build complete!") {
            return true
        }

        // Also check for typical SPM diagnostic patterns without Xcode markers
        if (input.contains(": error:") || input.contains(": warning:")) &&
           !XcodeBuildParser.canParse(input) {
            return true
        }

        return false
    }
}
