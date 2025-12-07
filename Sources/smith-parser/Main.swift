import ArgumentParser
import Foundation

/// smith-parser - Consolidated build output parser for Smith Tools
///
/// A unified tool for parsing and analyzing Swift and Xcode build outputs.
/// Auto-detects build system type and applies appropriate parsing logic.
@main
struct SBParser: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A consolidated build output parser for Swift and Xcode builds",
        discussion: """
        smith-parser processes build logs from Swift Package Manager and Xcode build system.
        It automatically detects the build type and provides structured analysis of:
        - Errors and warnings
        - Build timing information
        - File dependencies
        - Compiler diagnostics

        The tool reads from stdin by default, making it easy to pipe build output directly:
        xcodebuild -scheme MyApp clean build | smith-parser

        Or process log files:
        cat build.log | smith-parser
        """,
        version: "0.4.0",
        subcommands: [],
        defaultSubcommand: nil
    )

    @Flag(name: .shortAndLong, help: "Enable verbose output for detailed analysis")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Output format: json, text, summary, or compact")
    var format: OutputFormat = .text

    @Flag(name: .shortAndLong, help: "Filter to show only errors")
    var errors: Bool = false

    @Flag(name: .shortAndLong, help: "Filter to show only warnings")
    var warnings: Bool = false

    @Option(name: .shortAndLong, help: "Path to output file (default: stdout)")
    var output: String?

    @Flag(name: .long, help: "Minimal one-line output (token efficient)")
    var minimal: Bool = false

    mutating func run() throws {
        // Read input from stdin
        let input = readInput()

        guard !input.isEmpty else {
            throw ValidationError("No input provided. Pipe build output to stdin or provide a file path.")
        }

        // Auto-detect build system type
        let buildFormat = detectBuildFormat(in: input)

        if verbose {
            fputs("Detected build format: \(buildFormat.rawValue)\n", stderr)
        }

        // Parse based on detected type
        let result = parseBuildOutput(input, format: buildFormat)

        // Filter results if requested
        let filteredResult = filterResult(result)

        // Output results
        try outputResult(filteredResult)
    }

    // MARK: - Private Methods

    private func readInput() -> String {
        return String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func detectBuildFormat(in input: String) -> BuildFormat {
        // Check for SPM patterns first (SPM has distinctive markers)
        if SPMOutputParser.canParse(input) {
            return .spm
        }

        // Check for Swift/SPM patterns first (SPM has distinctive markers)
        if SwiftBuildParser.canParse(input) {
            return .swift
        }

        // Check for Xcode patterns
        if XcodeBuildParser.canParse(input) {
            return .xcode
        }

        // Default to unknown
        return .unknown
    }

    private func parseBuildOutput(_ input: String, format: BuildFormat) -> ParsedBuildResult {
        switch format {
        case .xcode:
            let parser = XcodeBuildParser()
            return parser.parse(input)

        case .swift:
            let parser = SwiftBuildParser()
            return parser.parse(input)

        case .spm:
            let parser = SPMOutputParser()
            return parser.parse(input)

        case .unknown:
            // Best-effort parsing - try SPM parser first, then Swift, then Xcode
            if SPMOutputParser.canParse(input) {
                let parser = SPMOutputParser()
                return parser.parse(input)
            }
            if SwiftBuildParser.canParse(input) {
                let parser = SwiftBuildParser()
                return parser.parse(input)
            }
            let parser = XcodeBuildParser()
            return parser.parse(input)
        }
    }

    private func filterResult(_ result: ParsedBuildResult) -> ParsedBuildResult {
        if errors {
            let filtered = result.diagnostics.filter { $0.severity == .error || $0.severity == .critical }
            return ParsedBuildResult(
                format: result.format,
                status: result.status,
                diagnostics: filtered,
                metrics: result.metrics,
                timing: result.timing
            )
        } else if warnings {
            let filtered = result.diagnostics.filter { $0.severity == .warning }
            return ParsedBuildResult(
                format: result.format,
                status: result.status,
                diagnostics: filtered,
                metrics: result.metrics,
                timing: result.timing
            )
        }
        return result
    }

    private func outputResult(_ result: ParsedBuildResult) throws {
        let outputString: String

        if minimal {
            outputString = formatMinimal(result)
        } else {
            switch format {
            case .json:
                // Manually encode to JSON since ParsedBuildResult has [String: Any]
                outputString = formatAsJSON(result)
            case .text:
                outputString = formatAsText(result)
            case .summary:
                outputString = formatAsSummary(result)
            case .compact:
                outputString = formatAsCompact(result)
            }
        }

        if let outputPath = output {
            try outputString.write(toFile: outputPath, atomically: true, encoding: .utf8)
        } else {
            print(outputString)
        }
    }

    private func formatMinimal(_ result: ParsedBuildResult) -> String {
        let status = result.status == .success ? "SUCCESS" : "FAILED"
        let duration = String(format: "%.1fs", result.timing.totalDuration)
        return "\(status) | ERRORS: \(result.metrics.errorCount) | WARNINGS: \(result.metrics.warningCount) | FILES: \(result.metrics.compiledFiles.count) | \(duration)"
    }

    private func formatAsSummary(_ result: ParsedBuildResult) -> String {
        var output = ""
        output += "BUILD \(result.status.rawValue.uppercased())\n"
        output += "FORMAT \(result.format.rawValue)\n"
        output += "ERRORS \(result.metrics.errorCount)\n"
        output += "WARNINGS \(result.metrics.warningCount)\n"
        output += "FILES COMPILED \(result.metrics.compiledFiles.count)\n"
        output += "DURATION \(String(format: "%.1f", result.timing.totalDuration))s\n"

        if !result.diagnostics.isEmpty {
            output += "\nDIAGNOSTICS\n"
            for diagnostic in result.diagnostics.prefix(10) {
                let severity = diagnostic.severity.rawValue.uppercased()
                let location = diagnostic.location ?? "unknown"
                output += "[\(severity)] \(location): \(diagnostic.message)\n"
            }
            if result.diagnostics.count > 10 {
                output += "... and \(result.diagnostics.count - 10) more\n"
            }
        }
        return output
    }

    private func formatAsCompact(_ result: ParsedBuildResult) -> String {
        let compact = CompactBuildResult(from: result)
        let dict: [String: Any] = [
            "format": compact.format.rawValue,
            "status": compact.status.rawValue,
            "errors": compact.errors,
            "warnings": compact.warnings,
            "files": compact.files,
            "duration": compact.duration
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    private func formatAsText(_ result: ParsedBuildResult) -> String {
        var output = ""

        // Header
        output += "BUILD ANALYSIS\n"
        output += "==============\n"
        output += "Format: \(result.format.rawValue)\n"
        output += "Status: \(result.status.rawValue)\n"
        output += "Duration: \(String(format: "%.2f", result.timing.totalDuration))s\n"
        output += "Errors: \(result.metrics.errorCount)\n"
        output += "Warnings: \(result.metrics.warningCount)\n"
        output += "Files Compiled: \(result.metrics.compiledFiles.count)\n"
        output += "\n"

        // Errors
        let errorDiags = result.diagnostics.filter { $0.severity == .error || $0.severity == .critical }
        if !errorDiags.isEmpty {
            output += "ERRORS (\(errorDiags.count))\n"
            output += "------\n"
            for error in errorDiags {
                let location = error.location ?? "unknown"
                output += "[ERROR] \(location)\n"
                output += "  \(error.message)\n"
            }
            output += "\n"
        }

        // Warnings
        let warningDiags = result.diagnostics.filter { $0.severity == .warning }
        if !warningDiags.isEmpty {
            output += "WARNINGS (\(warningDiags.count))\n"
            output += "--------\n"
            for warning in warningDiags {
                let location = warning.location ?? "unknown"
                output += "[WARNING] \(location)\n"
                output += "  \(warning.message)\n"
            }
            output += "\n"
        }

        // Info/Notes
        let infoDiags = result.diagnostics.filter { $0.severity == .info }
        if verbose && !infoDiags.isEmpty {
            output += "NOTES (\(infoDiags.count))\n"
            output += "-----\n"
            for info in infoDiags {
                let location = info.location ?? "unknown"
                output += "[NOTE] \(location)\n"
                output += "  \(info.message)\n"
            }
            output += "\n"
        }

        if result.diagnostics.isEmpty {
            output += "No issues found in build output.\n"
        }

        return output
    }

    private func formatAsJSON(_ result: ParsedBuildResult) -> String {
        var dict: [String: Any] = [
            "format": result.format.rawValue,
            "status": result.status.rawValue,
            "metrics": [
                "errorCount": result.metrics.errorCount,
                "warningCount": result.metrics.warningCount,
                "infoCount": result.metrics.infoCount,
                "compiledFiles": result.metrics.compiledFiles,
                "targetCount": result.metrics.targetCount,
                "totalDuration": result.metrics.totalDuration ?? 0.0
            ] as [String: Any],
            "timing": [
                "totalDuration": result.timing.totalDuration
            ] as [String: Any],
            "diagnostics": result.diagnostics.map { diag in
                var diagDict: [String: Any] = [
                    "severity": diag.severity.rawValue,
                    "category": diag.category.rawValue,
                    "message": diag.message
                ]
                if let location = diag.location {
                    diagDict["location"] = location
                }
                if let lineNumber = diag.lineNumber {
                    diagDict["lineNumber"] = lineNumber
                }
                if let column = diag.column {
                    diagDict["column"] = column
                }
                if let filePath = diag.filePath {
                    diagDict["filePath"] = filePath
                }
                return diagDict
            }
        ]

        if let spmInfo = result.spmInfo {
            dict["spm"] = spmInfo
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
}

// MARK: - Supporting Types

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case text = "text"
    case json = "json"
    case summary = "summary"
    case compact = "compact"
}
