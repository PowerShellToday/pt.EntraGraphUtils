$PrivateFunctions = Get-ChildItem "$PSScriptRoot/private" -Filter *.ps1
$PublicFunctions  = Get-ChildItem "$PSScriptRoot/public"  -Filter *.ps1

foreach ($fn in $PrivateFunctions) { . $fn.FullName }
foreach ($fn in $PublicFunctions)  { . $fn.FullName }

Export-ModuleMember -Function ($PublicFunctions | Select-Object -ExpandProperty BaseName)
