
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Verbose','Info','Warning','Error')]
        [string]$Level = 'Info'
    )

    switch ($Level) {
        'Verbose' { Write-Verbose $Message }
        'Info'    { Write-Host $Message }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message }
    }
}
