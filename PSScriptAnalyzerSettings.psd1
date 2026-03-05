@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidGlobalVars',
        'PSUseSingularNouns',
        'PSReviewUnusedParameter',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSShouldProcess',
        'PSAvoidOverwritingBuiltInCmdlets',
        'PSUseProcessBlockForPipelineCommand'
    )
}
