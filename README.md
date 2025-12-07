# smith-parser

A consolidated build output parser for Swift and Xcode builds within the Smith Tools ecosystem.

## Overview

smith-parser provides a unified interface for parsing and analyzing build logs from both Swift Package Manager and Xcode build systems. It automatically detects the build system type and applies appropriate parsing logic to extract errors, warnings, and diagnostic information.

## Features

- **Auto-detection**: Automatically identifies whether input is from Swift or Xcode build systems
- **Multiple output formats**: Support for text, JSON, and summary formats
- **Flexible filtering**: Filter to show only errors or warnings
- **Stdin support**: Read from stdin for easy integration with build pipelines
- **Structured output**: Clean, organized output with visual indicators

## Installation

### From Source

```bash
# Clone the repository
git clone <repository-url>
cd smith-parser

# Build the executable
swift build -c release

# Install to /usr/local/bin (optional)
sudo cp .build/release/smith-parser /usr/local/bin/
```

### Using Swift Package Manager

Add as a dependency in your `Package.swift`:

```swift
.package(path: "./smith-parser")
```

## Usage

### Basic Usage

Process build output from stdin:

```bash
# Swift Package Manager build
swift build 2>&1 | smith-parser

# Xcode build
xcodebuild -scheme MyApp clean build | smith-parser
```

### Process Log Files

```bash
# Read from a file
cat build.log | smith-parser

# Or redirect input
smith-parser < build.log
```

### Output Format Options

```bash
# Text output (default)
swift build | smith-parser

# JSON format for programmatic use
swift build | smith-parser --format json > results.json

# Summary output
swift build | smith-parser --format summary
```

### Filtering Options

```bash
# Show only errors
swift build | smith-parser --errors

# Show only warnings
swift build | smith-parser --warnings

# Verbose output
swift build | smith-parser --verbose
```

### Writing to File

```bash
# Write output to a file instead of stdout
swift build | smith-parser --output analysis.txt
```

## Command Line Options

```
USAGE: smith-parser [--verbose] [--format <format>] [--errors] [--warnings] [--output <output>] [--help]

OPTIONS:
  -v, --verbose            Enable verbose output for detailed analysis
  -f, --format <format>    Output format: json, text, or summary (default: text)
  -e, --errors             Filter to show only errors
  -w, --warnings           Filter to show only warnings
  -o, --output <output>    Path to output file (default: stdout)
  -h, --help               Show help information.
```

## Examples

### Example 1: Quick Build Analysis

```bash
# Build a project and parse the output
swift build 2>&1 | smith-parser --format summary
```

### Example 2: Continuous Integration

```bash
# In CI pipelines, save structured output
xcodebuild -scheme MyApp test 2>&1 | smith-parser --format json --output build-analysis.json
```

### Example 3: Error Monitoring

```bash
# Focus on build errors only
swift build 2>&1 | smith-parser --errors --verbose
```

## Architecture

smith-parser is built on top of the `smith-build-analysis` library, which provides shared parsing logic for both Swift and Xcode build systems. It uses Swift's Argument Parser library for command-line interface handling.

### Key Components

- **Auto-detection**: Pattern matching to identify build system type
- **Parsing Engine**: Delegated to smith-build-analysis library
- **Output Formatter**: Multiple format support (text, JSON, summary)
- **Filtering System**: Error/warning filtering and verbose modes

## Integration with Smith Tools

smith-parser is part of the Smith Tools ecosystem and integrates with:

- `smith-xcsift`: Xcode build analysis
- `smith-sbsift`: Swift build analysis
- `smith-validation`: TCA validation tools

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Add tests if applicable
5. Build and verify: `swift build`
6. Submit a pull request

## License

This project is part of the Smith Tools organization. See LICENSE file for details.

## Roadmap

- [ ] Full implementation using smith-build-analysis library
- [ ] Enhanced error categorization
- [ ] Integration with Xcode for real-time build monitoring
- [ ] Support for additional build systems
- [ ] Machine learning-based build outcome prediction
