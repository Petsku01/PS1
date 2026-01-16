# PowerShell Script Analysis Tools

A two-tier PowerShell script analysis system for code quality and security checking.

**Author:** -pk

## Overview

This repository contains two PowerShell script analyzers:

1. **Enterprise Version** - Comprehensive analysis with AST parsing and 20+ checks
2. **Simple Version** - Lightweight standalone checker with 8 essential checks

## Enterprise Version

**Location:** Root directory  
**Main Script:** `Update-Scripts.ps1`  
**Grade:** A- (88/100) - Production Ready

### Features
- AST-based code analysis (95% accuracy) - INTEGRATED
- Thread-safe result container - INTEGRATED
- Security hardened (XSS prevention, path traversal protection)
- 20+ comprehensive checks
- HTML report generation with Reports folder
- Auto-fix capability
- Pester test suite (24 tests)
- **NEW:** Advanced parameter validation
- **NEW:** Parallel processing support (PowerShell 7+)
- **NEW:** Set-StrictMode for strict code execution
- **NEW:** Comprehensive error handling throughout
- **NEW:** Verbose logging capability

### Usage

```powershell
# Analyze single script
.\Update-Scripts.ps1 -ScriptPath .\MyScript.ps1

# Analyze folder with report
.\Update-Scripts.ps1 -ScriptPath .\scripts -Report

# Analyze with auto-fix
.\Update-Scripts.ps1 -ScriptPath .\scripts -Fix

# NEW: Parallel processing (PowerShell 7+)
.\Update-Scripts.ps1 -ScriptPath .\scripts -Parallel -Verbose

# Use WhatIf to preview changes
.\Update-Scripts.ps1 -ScriptPath .\scripts -Fix -WhatIf
```

### Components

- **Update-Scripts.ps1** (814 lines) - Main analyzer with AST integration
- **CommonFunctions.psm1** (324 lines) - Shared utilities
- **src/Analyzers/AstAnalyzer.ps1** (263 lines) - AST analysis module (ACTIVE)
- **src/Core/AnalysisResult.ps1** (104 lines) - Thread-safe results (ACTIVE)
- **tests/** - Pester test suite

## Simple Version

**Location:** `SimpleScriptChecker/`  
**Main Script:** `Check-Script.ps1`  
**Grade:** Great for everyday use

### Features
- Single file, zero dependencies
- 8 essential checks
- Fast execution (<1 second per script)
- HTML report generation
- XSS-safe output
- Easy to customize

### Usage

```powershell
cd SimpleScriptChecker

# Check a single script
.\Check-Script.ps1 -ScriptPath ..\MyScript.ps1

# Check folder with report
.\Check-Script.ps1 -ScriptPath ..\scripts -ShowReport
```

### When to Use

**Use Simple Version for:**
- Quick personal script checks
- Learning PowerShell best practices
- Small teams without strict standards
- One-off validation
- Basic CI/CD quality gates

**Use Enterprise Version for:**
- Large codebases (100+ scripts)
- FAANG-level code review
- Compliance requirements
- Complex security auditing
- Automated remediation

## Security Features (Both Versions)

- **XSS Prevention** - Severity whitelisting + HTML encoding
- **Path Traversal Protection** - Filename whitelisting + canonical path validation
- **Thread Safety** - ConcurrentBag for parallel processing (Enterprise)
- **Input Validation** - Strict parameter validation

## Requirements

- PowerShell 5.1+ (both versions)
- PowerShell 7+ compatible (both versions)
- No external dependencies (Simple version)
- Pester 3.4.0+ for tests (Enterprise version)

## Reports

Both versions save HTML reports to dedicated folders:
- Enterprise: `Reports/ScriptAnalysis_[timestamp].html`
- Simple: `SimpleScriptChecker/Reports/ScriptCheck_[timestamp].html`

## Documentation

- **SimpleScriptChecker/README.md** - Simple version documentation
- **This file** - Main project overview

## License

Author: -pk  
Created: 2026

