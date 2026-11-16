@{
    RootModule = 'Jev.psm1'
    ModuleVersion = '0.2.2'
    GUID = 'e394878f-3472-42df-a193-cc77454f3e96'
    Author = 'Jev PowerShell contributors'
    Description = 'Pipeline-friendly typed decisions using TypeSafe Jev, OpenRouter, or a compatible local endpoint.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @('New-JevObject','Set-JevConnection','Copy-JevObject','Set-JevState','New-JevQuestion','Add-JevQuestion','Invoke-JevDecision','Get-JevAnswer')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @('Invoke-JevResponse')
    FormatsToProcess = @('Jev.format.ps1xml')
    PrivateData = @{ PSData = @{ Tags = @('Jev','TypeSafe','OpenRouter','Decisions','AI') } }
}



