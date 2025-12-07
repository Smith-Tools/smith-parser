import Foundation

/// XcodeBuildParser - Parses xcodebuild command output
///
/// Extracts errors, warnings, build status, timing, and file compilation information
/// from xcodebuild output streams.
public struct XcodeBuildParser {

    public init() {}

    /// Parse xcodebuild output and return structured result
    /// - Parameter output: Raw xcodebuild output string
    /// - Returns: ParsedBuildResult with extracted information
    public func parse(_ output: String) -> ParsedBuildResult {
        var diagnostics: [Diagnostic] = []
        var metrics = BuildMetrics()
        var status: BuildStatus = .unknown
        var timing = BuildTiming()

        // Split output into lines for analysis
        let lines = output.components(separatedBy: .newlines)

        // Track build timing
        var buildStartTime: Date?

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Detect build start - be more specific to avoid matching "Build completed"
            if trimmedLine.contains("BUILD START") ||
               trimmedLine.hasPrefix("Build settings") ||
               trimmedLine.hasPrefix("Build target") ||
               trimmedLine.contains("xcodebuild") {
                if buildStartTime == nil {
                    buildStartTime = Date()
                    timing.startTime = buildStartTime
                }
            }

            // Extract timing from build output if present (e.g., "Build completed in X.XXs")
            // Do this FIRST before status detection to prevent overwriting
            if let duration = extractDuration(from: trimmedLine) {
                timing.totalDuration = duration
            }

            // Detect build status
            let lowercasedLine = trimmedLine.lowercased()
            if lowercasedLine.contains("build succeeded") || trimmedLine.contains("** BUILD SUCCEEDED **") {
                status = .success
                timing.endTime = Date()
                // Only set computed duration if we don't have an extracted one
                if timing.totalDuration == 0.0 {
                    if let start = buildStartTime {
                        timing.totalDuration = Date().timeIntervalSince(start)
                    }
                }
            } else if lowercasedLine.contains("build failed") || trimmedLine.contains("** BUILD FAILED **") {
                status = .failed
                timing.endTime = Date()
                // Only set computed duration if we don't have an extracted one
                if timing.totalDuration == 0.0 {
                    if let start = buildStartTime {
                        timing.totalDuration = Date().timeIntervalSince(start)
                    }
                }
            }

            // Parse errors - various xcodebuild patterns
            if trimmedLine.contains(": error:") || trimmedLine.contains(" error: ") {
                let diagnostic = parseDiagnostic(from: trimmedLine, severity: .error, lineNumber: index + 1)
                diagnostics.append(diagnostic)
                metrics.errorCount += 1
            }

            // Parse warnings
            if trimmedLine.contains(": warning:") || trimmedLine.contains(" warning: ") {
                let diagnostic = parseDiagnostic(from: trimmedLine, severity: .warning, lineNumber: index + 1)
                diagnostics.append(diagnostic)
                metrics.warningCount += 1
            }

            // Parse notes (xcodebuild also emits notes)
            if trimmedLine.contains(": note:") || trimmedLine.contains(" note: ") {
                let diagnostic = parseDiagnostic(from: trimmedLine, severity: .info, lineNumber: index + 1)
                diagnostics.append(diagnostic)
                metrics.infoCount += 1
            }

            // Parse file compilation (multiple patterns)
            var checkLine = trimmedLine
            // Strip "(in target...)" suffix for cleaner matching
            if let range = checkLine.range(of: " (in target") {
                checkLine = String(checkLine[..<range.lowerBound])
            }
            if (trimmedLine.contains("Compiling") && trimmedLine.contains(".swift")) ||
               (trimmedLine.contains("CompileSwift") && checkLine.contains(".swift")) ||
               (trimmedLine.contains("SwiftCompile") && checkLine.contains(".swift")) ||
               (checkLine.hasSuffix(".swift") && checkLine.contains("/")) {
                let filename = extractFilename(from: trimmedLine)
                if filename != "unknown.swift" && !metrics.compiledFiles.contains(filename) {
                    metrics.compiledFiles.append(filename)
                }
            }

            // Detect build targets
            if trimmedLine.contains("=== BUILD TARGET") || trimmedLine.contains("Build target") {
                metrics.targetCount += 1
            }
        }

        // Determine final status if not explicitly found
        if status == .unknown {
            status = metrics.errorCount == 0 ? .success : .failed
        }

        metrics.totalDuration = timing.totalDuration

        return ParsedBuildResult(
            format: .xcode,
            status: status,
            diagnostics: diagnostics,
            metrics: metrics,
            timing: timing
        )
    }

    // MARK: - Private Helpers

    private func parseDiagnostic(from line: String, severity: DiagnosticSeverity, lineNumber: Int) -> Diagnostic {
        // Parse location info: /path/to/file.swift:42:10: error: message
        // Also handles Windows paths: C:\Projects\MyApp\File.swift:42:10: error: message
        var filePath: String? = nil
        var lineNum: Int? = nil
        var column: Int? = nil
        var message: String = line
        var location: String = ""

        // Find the position of severity marker (error:, warning:, note:)
        let severityMarkers = [": error:", ": warning:", ": note:", " error: ", " warning: ", " note: "]
        var severityPosition: String.Index? = nil
        var markerLength = 0

        for marker in severityMarkers {
            if let range = line.range(of: marker, options: .caseInsensitive) {
                if severityPosition == nil || range.lowerBound < severityPosition! {
                    severityPosition = range.lowerBound
                    markerLength = marker.count
                }
            }
        }

        if let pos = severityPosition {
            // Everything before the marker is the location
            let locationPart = String(line[..<pos]).trimmingCharacters(in: .whitespaces)
            location = locationPart

            // Everything after is the message (skip the marker)
            let afterMarker = line[line.index(pos, offsetBy: markerLength)...]
            message = String(afterMarker).trimmingCharacters(in: .whitespaces)

            // Parse location for file:line:column
            // Handle Windows paths (e.g., C:\path) by checking if it starts with a drive letter
            if locationPart.count >= 2 && locationPart[locationPart.index(locationPart.startIndex, offsetBy: 1)] == ":" {
                // Windows path - find the last colon-separated parts for line:column
                if let lastColonRange = locationPart.range(of: ":", options: .backwards) {
                    let afterLastColon = String(locationPart[lastColonRange.upperBound...])
                    if let col = Int(afterLastColon) {
                        column = col
                        let beforeLastColon = String(locationPart[..<lastColonRange.lowerBound])
                        if let secondLastColonRange = beforeLastColon.range(of: ":", options: .backwards) {
                            let afterSecondLastColon = String(beforeLastColon[secondLastColonRange.upperBound...])
                            if let ln = Int(afterSecondLastColon) {
                                lineNum = ln
                                filePath = String(beforeLastColon[..<secondLastColonRange.lowerBound])
                            } else {
                                filePath = beforeLastColon
                            }
                        } else {
                            filePath = beforeLastColon
                        }
                    } else if let ln = Int(afterLastColon) {
                        lineNum = ln
                        filePath = String(locationPart[..<lastColonRange.lowerBound])
                    } else {
                        filePath = locationPart
                    }
                } else {
                    filePath = locationPart
                }
            } else {
                // Unix path - use simple colon splitting
                let locationComponents = locationPart.components(separatedBy: ":")
                if locationComponents.count >= 1 {
                    filePath = locationComponents[0]
                }
                if locationComponents.count >= 2, let ln = Int(locationComponents[1]) {
                    lineNum = ln
                }
                if locationComponents.count >= 3, let col = Int(locationComponents[2]) {
                    column = col
                }
            }
        }

        return Diagnostic(
            severity: severity,
            category: .build,
            message: message,
            location: location.isEmpty ? nil : location,
            lineNumber: lineNum,
            column: column,
            filePath: filePath
        )
    }

    private func extractFilename(from line: String) -> String {
        // Try to extract Swift filename from compilation line
        // Handle patterns like "/path/to/file.swift (in target 'MyApp' from project 'MyApp')"
        var workingLine = line
        if let parenRange = workingLine.range(of: " (in target") {
            workingLine = String(workingLine[..<parenRange.lowerBound])
        }

        let components = workingLine.components(separatedBy: " ")
        for component in components.reversed() {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(".swift") {
                // Extract just the filename, not full path
                return (trimmed as NSString).lastPathComponent
            }
        }
        return "unknown.swift"
    }

    private func extractDuration(from line: String) -> TimeInterval? {
        // Match patterns like "Build completed in 12.34s" or "(X.XX seconds)"
        let patterns = [
            "completed in ([0-9.]+)s(?:\\s|$)",           // completed in 12.34s
            "completed in ([0-9.]+) second",              // completed in 12.34 second/seconds
            "\\(([0-9.]+) seconds?\\)",                   // (5.75 seconds)
            "\\(([0-9.]+)s\\)"                            // (5.75s)
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

extension XcodeBuildParser {
    /// Check if the input appears to be xcodebuild output
    public static func canParse(_ input: String) -> Bool {
        let xcodePatterns = [
            "xcodebuild",
            "BUILD SUCCEEDED",
            "BUILD FAILED",
            "** BUILD",
            "=== BUILD TARGET",
            "Build settings from",
            "CompileSwift",
            "SwiftCompile",
            "CodeSign",
            "ProcessInfoPlistFile"
        ]

        let lowercased = input.lowercased()

        // Check for Xcode-specific patterns
        for pattern in xcodePatterns {
            if lowercased.contains(pattern.lowercased()) {
                return true
            }
        }

        // "Ld " pattern needs exact check (space after Ld)
        if input.contains("Ld ") {
            return true
        }

        return false
    }
}
