@{
    RootModule        = 'pt.EntraGraphUtils.psm1'
    ModuleVersion     = '1.0.1'
    ModuleVersion     = '1.0.1'
    GUID              = 'd8f5e6c3-a2b1-4e78-9d0f-2b3c4d5e6f7a'
    Author            = 'PowerShell.Today'
    CompanyName       = 'PowerShell.Today'
    Copyright         = '(c) 2026 PowerShell.Today. Licensed under the MIT License.'
    Copyright         = '(c) 2026 PowerShell.Today. Licensed under the MIT License.'
    Description       = 'PowerShell utilities for the Microsoft Graph REST API. Provides Invoke-ptGraphBatchRequest for high-performance JSON batch operations (up to 20 requests per HTTP call), Invoke-ptGraphRequest for individual API calls, and New-ptGraphRequestItem for building request objects. Features automatic retry handling, rate-limit backoff, auto-pagination, OData query parameter support, and multi-cloud (GCC, DoD, Germany, China) compatibility.'
    PowerShellVersion = '5.1'
    PowerShellVersion = '5.1'

    RequiredModules   = @('Microsoft.Graph.Authentication')

    FunctionsToExport = @(
        'Invoke-ptGraphBatchRequest',
        'Invoke-ptGraphRequest',
        'New-ptGraphRequestItem'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Prerelease   = 'RC2'
            Tags         = @('Entra', 'Graph', 'AzureAD', 'Microsoft365', 'EntraID', 'GraphAPI', 'Batch', 'JsonBatching', 'MicrosoftGraph', 'REST', 'PowerShellToday')
            LicenseUri   = 'https://github.com/PowerShellToday/pt.EntraGraphUtils/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/PowerShellToday/pt.EntraGraphUtils'
            ReleaseNotes = 'General-purpose Graph API functions: Invoke-ptGraphBatchRequest (JSON batch with auto-retry and pagination), Invoke-ptGraphRequest (individual requests), and New-ptGraphRequestItem (request object builder with OData parameter support).'
            ReleaseNotes = 'General-purpose Graph API functions: Invoke-ptGraphBatchRequest (JSON batch with auto-retry and pagination), Invoke-ptGraphRequest (individual requests), and New-ptGraphRequestItem (request object builder with OData parameter support).'
        }
    }
}
