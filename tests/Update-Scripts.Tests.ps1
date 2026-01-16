#Requires -Modules Pester

<#
.SYNOPSIS
    Pester test suite for Update-Scripts analyzer
    Compatible with Pester 3.4.0+

.DESCRIPTION
    Tests for security fixes, AST analyzer, result container, and error handling
#>

# Import modules at top level
$scriptRoot = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptRoot

# Source the classes directly 
. (Join-Path $projectRoot 'src\Core\AnalysisResult.ps1')
. (Join-Path $projectRoot 'src\Analyzers\AstAnalyzer.ps1')

# Load main script
. (Join-Path $projectRoot 'Update-Scripts.ps1')

Describe 'XSS Prevention Tests' {
    It 'HTML encodes angle brackets' {
        $text = '<script>alert("xss")</script>'
        $encoded = [System.Web.HttpUtility]::HtmlEncode($text)
        $encoded | Should -Match '&lt;script&gt;'
        $encoded | Should -Not -Match '<script>'
    }
    
    It 'HTML encodes ampersands' {
        $text = 'Tom & Jerry'
        $encoded = [System.Web.HttpUtility]::HtmlEncode($text)
        $encoded | Should -Match '&amp;'
    }
    
    It 'HTML encodes quotes' {
        $text = 'He said "Hello"'
        $encoded = [System.Web.HttpUtility]::HtmlEncode($text)
        $encoded | Should -Match '&quot;'
    }
}

Describe 'AST Analyzer Tests' {
    It 'Should detect Set-ExecutionPolicy Bypass' {
        $code = 'Set-ExecutionPolicy -ExecutionPolicy Bypass'
        $analyzer = [AstAnalyzer]::new($code)
        $results = $analyzer.FindExecutionPolicyBypass()
        $results.Count | Should -Be 1
    }
    
    It 'Should NOT detect Bypass in comments' {
        $code = '# Set-ExecutionPolicy -ExecutionPolicy Bypass'
        $analyzer = [AstAnalyzer]::new($code)
        $results = $analyzer.FindExecutionPolicyBypass()
        $results.Count | Should -Be 0
    }
    
    It 'Should detect hardcoded passwords' {
        $code = '$password = "SecretPass123"'
        $analyzer = [AstAnalyzer]::new($code)
        $results = $analyzer.FindCredentialAssignments()
        $results.Count | Should -BeGreaterThan 0
    }
    
    It 'Should detect -ErrorAction SilentlyContinue' {
        $code = 'Get-ChildItem -Path C:\ -ErrorAction SilentlyContinue'
        $analyzer = [AstAnalyzer]::new($code)
        $results = $analyzer.FindSilentErrorSuppression()
        $results.Count | Should -BeGreaterThan 0
    }
    
    It 'Should find function definitions' {
        $code = 'function MyTest { Write-Host "test" }'
        $analyzer = [AstAnalyzer]::new($code)
        $result = $analyzer.HasFunction('MyTest')
        $result | Should -Be $true
    }
    
    It 'Should detect help documentation' {
        $code = '<#.SYNOPSIS`nTest#>`nfunction MyTest { }'
        $analyzer = [AstAnalyzer]::new($code)
        $result = $analyzer.HasCommentHelp()
        $result | Should -Be $true
    }
}

Describe 'AnalysisResult Container Tests' {
    It 'Should create result object' {
        $result = [AnalysisResult]::new()
        $result | Should -Not -BeNullOrEmpty
    }
    
    It 'Should add single issue' {
        $result = [AnalysisResult]::new()
        $result.AddIssue(@{Issue = 'Test'; Severity = 'HIGH'; File = 'test.ps1'})
        $result.GetIssueCount() | Should -Be 1
    }
    
    It 'Should add multiple issues' {
        $result = [AnalysisResult]::new()
        $result.AddIssues(@(
            @{Issue = 'Test1'; Severity = 'HIGH'; File = 'test.ps1'},
            @{Issue = 'Test2'; Severity = 'MEDIUM'; File = 'test.ps1'}
        ))
        $result.GetIssueCount() | Should -Be 2
    }
    
    It 'Should filter by severity' {
        $result = [AnalysisResult]::new()
        $result.AddIssue(@{Issue = 'Critical'; Severity = 'CRITICAL'; File = 'test.ps1'})
        $result.AddIssue(@{Issue = 'High'; Severity = 'HIGH'; File = 'test.ps1'})
        $result.AddIssue(@{Issue = 'Medium'; Severity = 'MEDIUM'; File = 'test.ps1'})
        
        $critical = $result.GetIssueCountBySeverity('CRITICAL')
        $critical | Should -Be 1
    }
    
    It 'Should track duration' {
        $result = [AnalysisResult]::new()
        Start-Sleep -Milliseconds 50
        $result.Complete()
        $duration = $result.GetDurationSeconds()
        $duration | Should -BeGreaterThan 0
    }
    
    It 'Should generate summary' {
        $result = [AnalysisResult]::new()
        $result.AddIssue(@{Issue = 'Test'; Severity = 'HIGH'; File = 'test.ps1'})
        $result.ScriptsAnalyzed = 1
        $result.Complete()
        
        $summary = $result.GetSummary()
        $summary.TotalIssues | Should -Be 1
        $summary.ScriptsAnalyzed | Should -Be 1
    }
}

Describe 'Path Traversal Prevention' {
    It 'Should reject path traversal with forward slash' {
        try {
            Get-SafeLogPath -BaseDirectory 'C:\logs' -FileName '../evil.log'
            $false | Should -Be $true  # Should have thrown
        } catch {
            $_.Exception.Message | Should -Match 'path separator'
        }
    }
    
    It 'Should reject path traversal with backslash' {
        try {
            Get-SafeLogPath -BaseDirectory 'C:\logs' -FileName '..\..\evil.log'
            $false | Should -Be $true  # Should have thrown
        } catch {
            $_.Exception.Message | Should -Match 'path separator'
        }
    }
    
    It 'Should accept valid filenames' {
        $result = Get-SafeLogPath -BaseDirectory $env:TEMP -FileName 'test.log'
        $result | Should -Not -BeNullOrEmpty
        $result | Should -Match 'test\.log'
    }
}

Describe 'Error Handling' {
    Context 'Malformed Input' {
        It 'Should handle empty script content' {
            $analyzer = [AstAnalyzer]::new('')
            $analyzer | Should -Not -BeNullOrEmpty
        }
        
        It 'Should handle parse errors gracefully' {
            $content = 'if ($true { }  # Missing closing paren'
            { [AstAnalyzer]::new($content) } | Should -Throw
        }
    }
}
