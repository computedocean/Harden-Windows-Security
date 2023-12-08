Function Confirm-CertCN {
    <#
    .SYNOPSIS
         Function to check Certificate Common name - used mostly to validate values in UserConfigurations.json
    .INPUTS
        System.String
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    param (
        [System.String]$CN
    )
    [System.String[]]$Certificates = foreach ($cert in (Get-ChildItem -Path 'Cert:\CurrentUser\my')) {
        (($cert.Subject -split ',' | Select-Object -First 1) -replace 'CN=', '').Trim()
    }
    return [System.Boolean]($Certificates -contains $CN ? $true : $false)
}

# Export external facing functions only, prevent internal functions from getting exported
Export-ModuleMember -Function 'Confirm-CertCN' -Verbose:$false
