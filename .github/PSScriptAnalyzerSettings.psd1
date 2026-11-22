# Security-focused rules for SelfX. Scripts of SelfX Service can run as SYSTEM, so these rules fail the CI.
# Style rules are deliberately not enabled here (the code base has its own conventions).
@{
    IncludeRules = @(
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUsernameAndPasswordParams',
        'PSUsePSCredentialType',
        'PSAvoidUsingComputerNameHardcoded',
        'PSAvoidUsingBrokenHashAlgorithms',
        'PSAvoidUsingAllowUnencryptedAuthentication'
    )
}
