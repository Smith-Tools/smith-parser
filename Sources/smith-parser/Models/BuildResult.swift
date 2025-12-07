import Foundation

// MARK: - Build Format Detection

/// Supported build output formats
public enum BuildFormat: String, Codable, CaseIterable {
    case xcode = "xcode"
    case swift = "swift"
    case spm = "spm"
    case unknown = "unknown"
}

// MARK: - Build Status

/// Overall build status
public enum BuildStatus: String, Codable {
    case success = "success"
    case failed = "failed"
    case unknown = "unknown"
}

// MARK: - Diagnostic Types

/// Severity levels for build diagnostics
public enum DiagnosticSeverity: String, Codable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

/// Category of diagnostic
public enum DiagnosticCategory: String, Codable {
    case build = "build"
    case compilation = "compilation"
    case linking = "linking"
    case dependency = "dependency"
    case other = "other"
}

/// A single diagnostic (error, warning, or info) from build output
public struct Diagnostic: Codable, Equatable {
    public let severity: DiagnosticSeverity
    public let category: DiagnosticCategory
    public let message: String
    public let location: String?
    public let lineNumber: Int?
    public let column: Int?
    public let filePath: String?

    public init(
        severity: DiagnosticSeverity,
        category: DiagnosticCategory = .build,
        message: String,
        location: String? = nil,
        lineNumber: Int? = nil,
        column: Int? = nil,
        filePath: String? = nil
    ) {
        self.severity = severity
        self.category = category
        self.message = message
        self.location = location
        self.lineNumber = lineNumber
        self.column = column
        self.filePath = filePath
    }
}

// MARK: - Build Metrics

/// Metrics collected during build parsing
public struct BuildMetrics: Codable, Equatable {
    public var errorCount: Int
    public var warningCount: Int
    public var infoCount: Int
    public var compiledFiles: [String]
    public var targetCount: Int
    public var totalDuration: TimeInterval?

    public init(
        errorCount: Int = 0,
        warningCount: Int = 0,
        infoCount: Int = 0,
        compiledFiles: [String] = [],
        targetCount: Int = 0,
        totalDuration: TimeInterval? = nil
    ) {
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.infoCount = infoCount
        self.compiledFiles = compiledFiles
        self.targetCount = targetCount
        self.totalDuration = totalDuration
    }
}

// MARK: - Build Timing

/// Timing information for the build
public struct BuildTiming: Codable, Equatable {
    public var startTime: Date?
    public var endTime: Date?
    public var totalDuration: TimeInterval

    public init(startTime: Date? = nil, endTime: Date? = nil, totalDuration: TimeInterval = 0.0) {
        self.startTime = startTime
        self.endTime = endTime
        self.totalDuration = totalDuration
    }
}

// MARK: - Parsed Build Result

/// Unified result type for all build parsers
public struct ParsedBuildResult {
    public let format: BuildFormat
    public let status: BuildStatus
    public let diagnostics: [Diagnostic]
    public let metrics: BuildMetrics
    public let timing: BuildTiming
    public private(set) var spmInfo: [String: Any]?

    public init(
        format: BuildFormat,
        status: BuildStatus,
        diagnostics: [Diagnostic],
        metrics: BuildMetrics,
        timing: BuildTiming,
        spmInfo: [String: Any]? = nil
    ) {
        self.format = format
        self.status = status
        self.diagnostics = diagnostics
        self.metrics = metrics
        self.timing = timing
        self.spmInfo = spmInfo
    }

    /// Convenience accessor for errors only
    public var errors: [Diagnostic] {
        diagnostics.filter { $0.severity == .error || $0.severity == .critical }
    }

    /// Convenience accessor for warnings only
    public var warnings: [Diagnostic] {
        diagnostics.filter { $0.severity == .warning }
    }

    /// Check if build succeeded
    public var succeeded: Bool {
        status == .success
    }
}

// MARK: - Compact Result (for minimal output)

/// Compact representation for token-efficient output
public struct CompactBuildResult {
    public let format: BuildFormat
    public let status: BuildStatus
    public let errors: Int
    public let warnings: Int
    public let files: Int
    public let duration: TimeInterval

    public init(from result: ParsedBuildResult) {
        self.format = result.format
        self.status = result.status
        self.errors = result.metrics.errorCount
        self.warnings = result.metrics.warningCount
        self.files = result.metrics.compiledFiles.count
        self.duration = result.timing.totalDuration
    }
}
