# Elevation.ps1 - Admin/elevation check functions

function Test-IsElevated {
    <#
    .SYNOPSIS
        Checks if the current PowerShell session is running as Administrator.
    .OUTPUTS
        [bool] True if elevated, false otherwise.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
