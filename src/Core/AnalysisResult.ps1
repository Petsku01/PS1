<#
.SYNOPSIS
    Analysis result container - replaces global $script:Issues variable

.DESCRIPTION
    Type-safe container for analysis results with metrics and aggregation
#>

class AnalysisResult {
    [System.Collections.Concurrent.ConcurrentBag[object]]$Issues
    [datetime]$StartTime
    [datetime]$EndTime
    [int]$ScriptsAnalyzed = 0
    [hashtable]$Metadata = @{}
    
    # Constructor
    AnalysisResult() {
        $this.Issues = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        $this.StartTime = Get-Date
    }
    
    # Add a single issue (thread-safe)
    [void]AddIssue([object]$Issue) {
        if ($null -eq $Issue) {
            throw "Issue cannot be null"
        }
        $this.Issues.Add($Issue)
    }
    
    # Add multiple issues (thread-safe)
    [void]AddIssues([array]$Issues) {
        if ($null -eq $Issues) { return }
        
        foreach ($issue in $Issues) {
            if ($null -ne $issue) {
                $this.Issues.Add($issue)
            }
        }
    }
    
    # Get total issue count
    [int]GetIssueCount() {
        return $this.Issues.Count
    }
    
    # Get count by severity
    [int]GetIssueCountBySeverity([string]$Severity) {
        return @($this.Issues | Where-Object { $_.Severity -eq $Severity }).Count
    }
    
    # Get count by category
    [int]GetIssueCountByCategory([string]$Category) {
        return @($this.Issues | Where-Object { $_.Category -eq $Category }).Count
    }
    
    # Get issues by severity
    [array]GetIssuesBySeverity([string]$Severity) {
        return @($this.Issues | Where-Object { $_.Severity -eq $Severity })
    }
    
    # Get issues by category
    [array]GetIssuesByCategory([string]$Category) {
        return @($this.Issues | Where-Object { $_.Category -eq $Category })
    }
    
    # Mark analysis as complete
    [void]Complete() {
        $this.EndTime = Get-Date
    }
    
    # Get duration
    [double]GetDurationSeconds() {
        if ($null -eq $this.EndTime) {
            return (Get-Date - $this.StartTime).TotalSeconds
        }
        return ($this.EndTime - $this.StartTime).TotalSeconds
    }
    
    # Get summary statistics
    [hashtable]GetSummary() {
        return @{
            TotalIssues = $this.GetIssueCount()
            Critical = $this.GetIssueCountBySeverity('CRITICAL')
            High = $this.GetIssueCountBySeverity('HIGH')
            Medium = $this.GetIssueCountBySeverity('MEDIUM')
            Low = $this.GetIssueCountBySeverity('LOW')
            ScriptsAnalyzed = $this.ScriptsAnalyzed
            DurationSeconds = $this.GetDurationSeconds()
            StartTime = $this.StartTime
            EndTime = $this.EndTime
        }
    }
    
    # Export results as structured object
    [object]ToObject() {
        return [PSCustomObject]@{
            Summary = $this.GetSummary()
            Issues = $this.Issues
            Metadata = $this.Metadata
        }
    }
}

