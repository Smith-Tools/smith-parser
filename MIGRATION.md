# Migration Guide: Build Parser Tools v3.1.0

This guide helps you migrate from the deprecated parse commands in smith-xcsift, smith-sbsift, and smith-spmsift to the unified `sbparser` tool.

## Overview

**What Changed?**

Starting with v3.1.0, the `parse` command has been removed from:
- smith-xcsift
- smith-sbsift
- smith-spmsift

All parsing functionality has been consolidated into the dedicated `sbparser` tool.

**Why?**

- **Separation of Concerns**: Parsing is now handled by a dedicated, specialized tool
- **Better Maintainability**: Parse logic is more modular and testable
- **Clearer Tool Responsibilities**: Each tool focuses on its specific domain
- **Unified Experience**: Consistent parsing interface across all build systems

## Migration Steps

### 1. smith-xcsift Migration

**Old Command:**
```bash
# Parse xcodebuild output
xcodebuild build -scheme MyApp 2>&1 | smith-xcsift parse

# With specific format
xcodebuild build -scheme MyApp 2>&1 | smith-xcsift parse --format summary

# Compact mode
xcodebuild build -scheme MyApp 2>&1 | smith-xcsift parse --format compact --minimal
```

**New Command:**
```bash
# Parse xcodebuild output
xcodebuild build -scheme MyApp 2>&1 | sbparser parse

# With specific format
xcodebuild build -scheme MyApp 2>&1 | sbparser parse --format summary

# Compact mode
xcodebuild build -scheme MyApp 2>&1 | sbparser parse --format compact --minimal
```

**Changes:**
- Replace `smith-xcsift parse` with `sbparser parse`
- All existing flags and options work the same way

---

### 2. smith-sbsift Migration

**Old Command:**
```bash
# Parse Swift build output
swift build 2>&1 | smith-sbsift parse

# With format
swift build 2>&1 | smith-sbsift parse --format json

# Summary format
swift test 2>&1 | smith-sbsift parse --format summary
```

**New Command:**
```bash
# Parse Swift build output
swift build 2>&1 | sbparser parse

# With format
swift build 2>&1 | sbparser parse --format json

# Summary format
swift test 2>&1 | sbparser parse --format summary
```

**Changes:**
- Replace `smith-sbsift parse` with `sbparser parse`
- All existing flags and options work the same way

---

### 3. smith-spmsift Migration

**Old Command:**
```bash
# Parse Swift Package Manager output
swift package dump-package | smith-spmsift parse

# With format
swift package show-dependencies | smith-spmsift parse --format json

# Summary format
swift package resolve | smith-spmsift parse --format summary
```

**New Command:**
```bash
# Parse Swift Package Manager output
swift package dump-package | sbparser parse

# With format
swift package show-dependencies | sbparser parse --format json

# Summary format
swift package resolve | sbparser parse --format summary
```

**Changes:**
- Replace `smith-spmsift parse` with `sbparser parse`
- All existing flags and options work the same way

---

## Command Reference

### Basic Usage

```bash
# Any build command output piped to sbparser
<build-command> | sbparser parse [options]
```

### Common Options

| Option | Description | Example |
|--------|-------------|---------|
| `--format <format>` | Output format (json, compact, summary, detailed) | `--format summary` |
| `--minimal` | Minimal output mode (85%+ size reduction) | `--minimal` |
| `--compact` | Compact output mode (60-70% size reduction) | `--compact` |
| `--severity <level>` | Minimum severity to include (info, warning, error) | `--severity error` |
| `--verbose` | Include raw output for debugging | `--verbose` |
| `--timing` | Include build timing metrics | `--timing` |
| `--files` | Include file-specific analysis | `--files` |

### Output Formats

#### JSON (default)
Structured JSON output with full build information:
```bash
xcodebuild build | sbparser parse --format json
```

#### Compact
Compressed JSON with essential information only:
```bash
xcodebuild build | sbparser parse --format compact
```

#### Summary
Human-readable summary with key metrics:
```bash
xcodebuild build | sbparser parse --format summary
```

#### Detailed
Comprehensive output with all diagnostics:
```bash
xcodebuild build | sbparser parse --format detailed
```

---

## Migration Examples

### CI/CD Pipeline

**Before (smith-xcsift):**
```yaml
- name: Parse Xcode Build
  run: xcodebuild build | smith-xcsift parse --format json > build-result.json
```

**After (sbparser):**
```yaml
- name: Parse Xcode Build
  run: xcodebuild build | sbparser parse --format json > build-result.json
```

### Shell Scripts

**Before (smith-sbsift):**
```bash
#!/bin/bash
swift build 2>&1 | smith-sbsift parse --format summary
```

**After (sbparser):**
```bash
#!/bin/bash
swift build 2>&1 | sbparser parse --format summary
```

### Xcode Build Logs

**Before (smith-xcsift):**
```bash
xcodebuild archive -scheme MyApp -configuration Release 2>&1 | smith-xcsift parse --format compact --minimal
```

**After (sbparser):**
```bash
xcodebuild archive -scheme MyApp -configuration Release 2>&1 | sbparser parse --format compact --minimal
```

### Swift Package Manager

**Before (smith-spmsift):**
```bash
swift package resolve 2>&1 | smith-spmsift parse --format json
```

**After (sbparser):**
```bash
swift package resolve 2>&1 | sbparser parse --format json
```

---

## Troubleshooting

### Issue: Command not found

**Problem:** `sbparser: command not found`

**Solution:**
```bash
# Install sbparser
# Option 1: Via Homebrew
brew tap smith-tools/smith
brew install sbparser

# Option 2: From source
git clone https://github.com/Smith-Tools/sbparser.git
cd sbparser
swift build -c release
sudo cp .build/release/sbparser /usr/local/bin/
```

### Issue: Unknown flag or option

**Problem:** `error: Unknown option '--some-flag'`

**Solution:**
- Check the available options: `sbparser parse --help`
- Some flags may have been renamed or consolidated
- Refer to the [Command Reference](#command-reference) section above

### Issue: Different output format

**Problem:** The output looks different from the old tool

**Solution:**
- Use `--format json` for machine-readable output
- Use `--format detailed` for comprehensive output
- The parsing logic is the same, but formatting may have improved
- Check [Output Formats](#output-formats) for details

### Issue: Missing functionality

**Problem:** A feature I used in the old tool is missing

**Solution:**
- sbparser is the dedicated parsing tool that consolidates all functionality
- Features from all three tools (smith-xcsift, smith-sbsift, smith-spmsift) are now in one place
- Check `sbparser parse --help` for all available options
- If a feature is missing, please file an issue at https://github.com/Smith-Tools/sbparser/issues

---

## Tools Comparison

### Before (v3.0.x)

| Tool | Purpose | Parse Command |
|------|---------|---------------|
| smith-xcsift | Xcode build analysis | `smith-xcsift parse` |
| smith-sbsift | Swift build analysis | `smith-sbsift parse` |
| smith-spmsift | SPM analysis | `smith-spmsift parse` |

### After (v3.1.0+)

| Tool | Purpose | Commands |
|------|---------|----------|
| smith-xcsift | Xcode build analysis | `smith-xcsift analyze`, `smith-xcsift validate` |
| smith-sbsift | Swift build analysis | `smith-sbsift analyze`, `smith-sbsift monitor`, `smith-sbsift validate` |
| smith-spmsift | SPM analysis | `smith-spmsift analyze`, `smith-spmsift validate`, `smith-spmsift optimize` |
| **sbparser** | **Build output parsing** | **`sbparser parse`** |

---

## Frequently Asked Questions

### Q: Do I need to update my scripts immediately?

**A:** No. The deprecated tools will continue to work, but they show deprecation warnings. We recommend migrating at your convenience before v4.0.0 (when the old parse commands will be fully removed).

### Q: Will the output format change?

**A:** The core parsing logic is the same, so the output structure remains consistent. You may see improvements in formatting and additional metadata in some cases.

### Q: Can I still use smith-xcsift/smith-sbsift/smith-spmsift for non-parse commands?

**A:** Yes! All other commands remain unchanged:
- smith-xcsift: `analyze`, `validate`
- smith-sbsift: `analyze`, `monitor`, `validate`
- smith-spmsift: `analyze`, `validate`, `optimize`

### Q: How do I install sbparser?

**A:** See the [Installation Guide](README.md#installation) in the README.

### Q: Where can I report issues or request features?

**A:** Please file issues at https://github.com/Smith-Tools/sbparser/issues

### Q: Is there a changelog?

**A:** Yes, see [CHANGELOG.md](CHANGELOG.md) for detailed changes.

---

## Support

If you need help with migration:

1. Check this migration guide
2. Run `sbparser parse --help` for command options
3. Check the [Troubleshooting](#troubleshooting) section
4. File an issue at https://github.com/Smith-Tools/sbparser/issues

---

**Last Updated:** December 6, 2025
**Migration Guide Version:** 1.0.0
