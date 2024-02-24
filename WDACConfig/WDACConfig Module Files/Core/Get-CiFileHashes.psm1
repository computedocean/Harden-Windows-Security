Function Get-CiFileHashes {
    [CmdletBinding()]
    [OutputType([ordered])]
    param (
        [Parameter(Mandatory = $true, Position = 0, valueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [System.IO.FileInfo]$FilePath,

        [Parameter(Mandatory = $false)][System.Management.Automation.SwitchParameter]$SkipVersionCheck
    )
    Begin {
        # Detecting if Verbose switch is used
        $PSBoundParameters.Verbose.IsPresent ? ([System.Boolean]$Verbose = $true) : ([System.Boolean]$Verbose = $false) | Out-Null

        # Importing the $PSDefaultParameterValues to the current session, prior to everything else
        . "$ModuleRootPath\CoreExt\PSDefaultParameterValues.ps1"

        # Importing the required sub-modules
        Write-Verbose -Message 'Importing the required sub-modules'
        Import-Module -FullyQualifiedName "$ModuleRootPath\Shared\Update-self.psm1" -Force

        # if -SkipVersionCheck wasn't passed, run the updater
        if (-NOT $SkipVersionCheck) { Update-self -InvocationStatement $MyInvocation.Statement }

        # Defining the WinTrust class from the WDACConfig Namespace if it doesn't already exist
        if (-NOT ('WDACConfig.WinTrust' -as [System.Type]) ) {
            Add-Type -Path "$ModuleRootPath\C#\AuthenticodeHashCalc.cs"
        }

        # Defining the PageHashCalculator class from the WDACConfig Namespace if it doesn't already exist
        if (-NOT ('WDACConfig.PageHashCalculator' -as [System.Type]) ) {
            Add-Type -Path "$ModuleRootPath\C#\PageHashCalc.cs"
        }

        # Defining an ordered hashtable to store the output
        $OutputHashes = [ordered]@{
            SHA1Page           = ''
            SHA256Page         = ''
            SHa1Authenticode   = ''
            SHA256Authenticode = ''
        }

        function Get-AuthenticodeHash {
            <#
            .SYNOPSIS
               This is a nested function that calculates the authenticode hash of a file using a specified hash algorithm
            .PARAMETER FilePath
                The path to the file for which the hash is to be calculated
            .PARAMETER HashAlgorithm
                The hash algorithm to be used. It can be either 'SHA1' or 'SHA256'
            .INPUTS
                System.IO.FileInfo
                System.String
            .OUTPUTS
                System.String
            #>
            param (
                [parameter(Mandatory = $true)]
                [System.IO.FileInfo]$FilePath,

                [parameter(Mandatory = $true)]
                [System.String]$HashAlgorithm
            )
            Begin {
                # Creating a StringBuilder object to store the hash value as a hexadecimal string
                [System.Text.StringBuilder]$HashString = New-Object -TypeName System.Text.StringBuilder(64)

                # Initializing a pointer to zero, which will be used to store the handle of the CryptCATAdmin context
                [System.IntPtr]$ContextHandle = [System.IntPtr]::Zero

                # Initializing a pointer to zero, which will be used to store the handle of the file stream
                [System.IntPtr]$FileStreamHandle = [System.IntPtr]::Zero

                Function Get-FlatFileHash {
                    <#
                    .SYNOPSIS
                        This is a nested function that calculates the flat hash of a file using a specified hash algorithm
                        This only runs as a fallback method when normal Authenticode hashes cannot be calculated because the file is Non-conformant
                    .NOTES
                        This function acts as a 2nd fallback.
                        The first fallback is defined and handled by the AuthenticodeHashCalc.cs
                    .PARAMETER FilePath
                        The path to the file for which the hash is to be calculated
                    .PARAMETER Algorithm
                        The hash algorithm to be used
                    .INPUTS
                        System.IO.FileInfo
                        System.String
                    .OUTPUTS
                        System.String
                    #>
                    param(
                        [parameter(Mandatory = $true)]
                        [System.IO.FileInfo]$FilePath,

                        [parameter(Mandatory = $true)]
                        [System.String]$Algorithm
                    )
                    Return [System.String](Get-FileHash -Algorithm $Algorithm -Path $FilePath).Hash
                }
            }

            Process {

                try {
                    # Old code - handle could not be properly closed
                    # $VoidPtr = [System.IO.File]::OpenRead($FilePath).SafeFileHandle.DangerousGetHandle()

                    # Opening a read-only file stream for the given file path
                    [System.IO.FileStream]$FileStream = [System.IO.File]::OpenRead($FilePath)

                    # Getting the handle of the file stream
                    [System.IntPtr]$FileStreamHandle = $FileStream.SafeFileHandle.DangerousGetHandle()

                    # Checking if the handle is valid
                    if ($FileStreamHandle -eq [System.IntPtr]::Zero) {
                        # Returning null if the handle is invalid
                        return $null
                    }

                    # Acquiring a CryptCATAdmin context for the specified hash algorithm
                    # This is a wrapper for the native CryptCATAdminAcquireContext2 function
                    # See https://learn.microsoft.com/en-us/windows/win32/api/mscat/nf-mscat-cryptcatadminacquirecontext2
                    if (-NOT ([WDACConfig.WinTrust]::CryptCATAdminAcquireContext2([ref]$ContextHandle, [System.IntPtr]::Zero, $HashAlgorithm, [System.IntPtr]::Zero, 0))) {
                        # Throwing an exception if the context could not be acquired
                        #   throw "Could not acquire context for $HashAlgorithm"

                        Write-Verbose -Message "Could not acquire context for $HashAlgorithm"

                        Return [System.String](Get-FlatFileHash -FilePath $FilePath -Algorithm $HashAlgorithm)
                    }

                    # Initializing a variable to store the size of the hash in bytes
                    [System.Int64]$HashSize = 0

                    # Calculating the hash of the file using the CryptCATAdmin context
                    # This is a wrapper for the native CryptCATAdminCalcHashFromFileHandle3 function
                    if (-NOT ([WDACConfig.WinTrust]::CryptCATAdminCalcHashFromFileHandle3($ContextHandle, $FileStreamHandle, [ref]$HashSize, [System.IntPtr]::Zero, [WDACConfig.WinTrust]::CryptcatadminCalchashFlagNonconformantFilesFallbackFlat))) {
                        # Throwing an exception if the hash could not be calculated
                        #  throw "Could not hash $FilePath using $HashAlgorithm"

                        Write-Verbose -Message "Could not hash $FilePath using $HashAlgorithm"

                        Return [System.String](Get-FlatFileHash -FilePath $FilePath -Algorithm $HashAlgorithm)
                    }

                    # Initializing a pointer to zero, which will be used to store the hash value
                    [System.IntPtr]$HashValue = [System.IntPtr]::Zero

                    try {
                        # Allocating memory for the hash value using the size obtained from the previous call
                        [System.IntPtr]$HashValue = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($HashSize)

                        # Calculating the hash of the file again using the CryptCATAdmin context and storing it in the allocated memory
                        if (-NOT ([WDACConfig.WinTrust]::CryptCATAdminCalcHashFromFileHandle3($ContextHandle, $FileStreamHandle, [ref]$HashSize, $HashValue, [WDACConfig.WinTrust]::CryptcatadminCalchashFlagNonconformantFilesFallbackFlat))) {
                            # Throwing an exception if the hash could not be calculated
                            # throw "Could not hash $FilePath using $HashAlgorithm"

                            Write-Verbose -Message "Could not hash $FilePath using $HashAlgorithm"

                            Return [System.String](Get-FlatFileHash -FilePath $FilePath -Algorithm $HashAlgorithm)
                        }

                        # Looping through the hash value byte by byte
                        for ($Offset = 0; $Offset -lt $HashSize; $Offset++) {

                            # Reading a byte from the allocated memory using the offset
                            [System.Byte]$Byte = [System.Runtime.InteropServices.Marshal]::ReadByte($HashValue, $Offset)

                            # Appending the byte to the StringBuilder object as a hexadecimal string
                            $HashString.Append($Byte.ToString('X2')) | Out-Null
                        }
                    }
                    finally {
                        # Freeing the allocated memory if it is not zero
                        if ($HashValue -ne [System.IntPtr]::Zero) {
                            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($HashValue)
                        }

                        # Closing the file stream
                        $FileStream.Close()
                    }
                }
                finally {
                    # Releasing the CryptCATAdmin context if it is not zero
                    if ($ContextHandle -ne [System.IntPtr]::Zero) {
                        [WDACConfig.WinTrust]::CryptCATAdminReleaseContext($ContextHandle, 0) | Out-Null # Hide the boolean output
                    }
                }
            }
            End {
                # Returning the hash value as a hexadecimal string
                return [System.String]$HashString.ToString()
            }
        }
    }
    process {
        # Calling the GetPageHash method of the PageHashCalculator class to calculate the SHA1 and SHA256 page hashes of the file
        # This method uses the native GetFileInformationByHandleEx function to get the page hash
        # https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getfileinformationbyhandleex
        [System.String]$OutputHashes.SHA1Page = [WDACConfig.PageHashCalculator]::GetPageHash('SHA1', $FilePath)
        [System.String]$OutputHashes.SHA256Page = [WDACConfig.PageHashCalculator]::GetPageHash('SHA256', $FilePath)

        # Calling the GetAuthenticodeHash function to calculate the SHA1 and SHA256 authenticode hashes of the file
        [System.String]$OutputHashes.SHA1Authenticode = Get-AuthenticodeHash -FilePath $FilePath -HashAlgorithm 'SHA1'
        [System.String]$OutputHashes.SHA256Authenticode = Get-AuthenticodeHash -FilePath $FilePath -HashAlgorithm 'SHA256'
    }
    End {
        # Returning the output ordered hashtable
        Return $OutputHashes
    }
    <#
.SYNOPSIS
    Calculates the Authenticode hash and first page hash of the PEs with SHA1 and SHA256 algorithms.
    The hashes are compliant wih the Windows Defender Application Control (WDAC) policy.
    For more information please visit: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/design/select-types-of-rules-to-create#more-information-about-hashes
.LINK
    https://github.com/HotCakeX/Harden-Windows-Security/wiki/Get-CiFileHashes
.PARAMETER Path
    The path to the file for which the hashes are to be calculated.
.PARAMETER SkipVersionCheck
    Can be used with any parameter to bypass the online version check - only to be used in rare cases
.INPUTS
    System.IO.FileInfo
.OUTPUTS
    [ordered]
    The output is an ordered hashtable with the following keys:
    - SHA1Page: The SHA1 hash of the first page of the PE file.
    - SHA256Page: The SHA256 hash of the first page of the PE file.
    - SHA1Authenticode: The SHA1 hash of the Authenticode signature of the PE file.
    - SHA256Authenticode: The SHA256 hash of the Authenticode signature of the PE file.
.NOTES
    If the is non-conformant, the function will calculate the flat hash of the file using the specified hash algorithm
    And return them as the Authenticode hashes. This is compliant with how the WDAC engine in Windows works.
#>
}
# Importing argument completer ScriptBlocks
. "$ModuleRootPath\Resources\ArgumentCompleters.ps1"

Register-ArgumentCompleter -CommandName 'Get-CiFileHashes' -ParameterName 'FilePath' -ScriptBlock $ArgumentCompleterAnyFilePathsPicker

# SIG # Begin signature block
# MIILkgYJKoZIhvcNAQcCoIILgzCCC38CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBXmh2vPAbaEcyw
# yf8k5evB9keTrV+C9AZV5KGICMItl6CCB9AwggfMMIIFtKADAgECAhMeAAAABI80
# LDQz/68TAAAAAAAEMA0GCSqGSIb3DQEBDQUAME8xEzARBgoJkiaJk/IsZAEZFgNj
# b20xIjAgBgoJkiaJk/IsZAEZFhJIT1RDQUtFWC1DQS1Eb21haW4xFDASBgNVBAMT
# C0hPVENBS0VYLUNBMCAXDTIzMTIyNzExMjkyOVoYDzIyMDgxMTEyMTEyOTI5WjB5
# MQswCQYDVQQGEwJVSzEeMBwGA1UEAxMVSG90Q2FrZVggQ29kZSBTaWduaW5nMSMw
# IQYJKoZIhvcNAQkBFhRob3RjYWtleEBvdXRsb29rLmNvbTElMCMGCSqGSIb3DQEJ
# ARYWU3B5bmV0Z2lybEBvdXRsb29rLmNvbTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAKb1BJzTrpu1ERiwr7ivp0UuJ1GmNmmZ65eckLpGSF+2r22+7Tgm
# pEifj9NhPw0X60F9HhdSM+2XeuikmaNMvq8XRDUFoenv9P1ZU1wli5WTKHJ5ayDW
# k2NP22G9IPRnIpizkHkQnCwctx0AFJx1qvvd+EFlG6ihM0fKGG+DwMaFqsKCGh+M
# rb1bKKtY7UEnEVAsVi7KYGkkH+ukhyFUAdUbh/3ZjO0xWPYpkf/1ldvGes6pjK6P
# US2PHbe6ukiupqYYG3I5Ad0e20uQfZbz9vMSTiwslLhmsST0XAesEvi+SJYz2xAQ
# x2O4n/PxMRxZ3m5Q0WQxLTGFGjB2Bl+B+QPBzbpwb9JC77zgA8J2ncP2biEguSRJ
# e56Ezx6YpSoRv4d1jS3tpRL+ZFm8yv6We+hodE++0tLsfpUq42Guy3MrGQ2kTIRo
# 7TGLOLpayR8tYmnF0XEHaBiVl7u/Szr7kmOe/CfRG8IZl6UX+/66OqZeyJ12Q3m2
# fe7ZWnpWT5sVp2sJmiuGb3atFXBWKcwNumNuy4JecjQE+7NF8rfIv94NxbBV/WSM
# pKf6Yv9OgzkjY1nRdIS1FBHa88RR55+7Ikh4FIGPBTAibiCEJMc79+b8cdsQGOo4
# ymgbKjGeoRNjtegZ7XE/3TUywBBFMf8NfcjF8REs/HIl7u2RHwRaUTJdAgMBAAGj
# ggJzMIICbzA8BgkrBgEEAYI3FQcELzAtBiUrBgEEAYI3FQiG7sUghM++I4HxhQSF
# hqV1htyhDXuG5sF2wOlDAgFkAgEIMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA4GA1Ud
# DwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYB
# BQUHAwMwHQYDVR0OBBYEFOlnnQDHNUpYoPqECFP6JAqGDFM6MB8GA1UdIwQYMBaA
# FICT0Mhz5MfqMIi7Xax90DRKYJLSMIHUBgNVHR8EgcwwgckwgcaggcOggcCGgb1s
# ZGFwOi8vL0NOPUhPVENBS0VYLUNBLENOPUhvdENha2VYLENOPUNEUCxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPU5vbkV4aXN0ZW50RG9tYWluLERDPWNvbT9jZXJ0aWZpY2F0ZVJldm9jYXRp
# b25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwgccG
# CCsGAQUFBwEBBIG6MIG3MIG0BggrBgEFBQcwAoaBp2xkYXA6Ly8vQ049SE9UQ0FL
# RVgtQ0EsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZp
# Y2VzLENOPUNvbmZpZ3VyYXRpb24sREM9Tm9uRXhpc3RlbnREb21haW4sREM9Y29t
# P2NBQ2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0
# aG9yaXR5MA0GCSqGSIb3DQEBDQUAA4ICAQA7JI76Ixy113wNjiJmJmPKfnn7brVI
# IyA3ZudXCheqWTYPyYnwzhCSzKJLejGNAsMlXwoYgXQBBmMiSI4Zv4UhTNc4Umqx
# pZSpqV+3FRFQHOG/X6NMHuFa2z7T2pdj+QJuH5TgPayKAJc+Kbg4C7edL6YoePRu
# HoEhoRffiabEP/yDtZWMa6WFqBsfgiLMlo7DfuhRJ0eRqvJ6+czOVU2bxvESMQVo
# bvFTNDlEcUzBM7QxbnsDyGpoJZTx6M3cUkEazuliPAw3IW1vJn8SR1jFBukKcjWn
# aau+/BE9w77GFz1RbIfH3hJ/CUA0wCavxWcbAHz1YoPTAz6EKjIc5PcHpDO+n8Fh
# t3ULwVjWPMoZzU589IXi+2Ol0IUWAdoQJr/Llhub3SNKZ3LlMUPNt+tXAs/vcUl0
# 7+Dp5FpUARE2gMYA/XxfU9T6Q3pX3/NRP/ojO9m0JrKv/KMc9sCGmV9sDygCOosU
# 5yGS4Ze/DJw6QR7xT9lMiWsfgL96Qcw4lfu1+5iLr0dnDFsGowGTKPGI0EvzK7H+
# DuFRg+Fyhn40dOUl8fVDqYHuZJRoWJxCsyobVkrX4rA6xUTswl7xYPYWz88WZDoY
# gI8AwuRkzJyUEA07IYtsbFCYrcUzIHME4uf8jsJhCmb0va1G2WrWuyasv3K/G8Nn
# f60MsDbDH1mLtzGCAxgwggMUAgEBMGYwTzETMBEGCgmSJomT8ixkARkWA2NvbTEi
# MCAGCgmSJomT8ixkARkWEkhPVENBS0VYLUNBLURvbWFpbjEUMBIGA1UEAxMLSE9U
# Q0FLRVgtQ0ECEx4AAAAEjzQsNDP/rxMAAAAAAAQwDQYJYIZIAWUDBAIBBQCggYQw
# GAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGC
# NwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQx
# IgQgNIWui26fmCs2qNiWFbHatpbAYnN9ang62+pxi8V+v3YwDQYJKoZIhvcNAQEB
# BQAEggIAeG/EKdFhHNkD7toDhP1v9EF5EEnAq+G0qXKzZ8bvvVRgTYe6jGLf58hV
# vGeVEby7wI12jZ89+L1QBXySJ+6/KsObl1H142FxZ/E94tix376pxV8iUNjySl/B
# KnWXtZIT9AY9Yrpqve+HZqWwyZhy7hBTapqsY2lBH5QDxBG/PX7pKS87hVklYnwj
# wwWFinOBoXmx5hP9e2SE+fSey7qQ6DPrRwp9cC9N2tHkycfx2+t7Z7NRbkWqajEg
# 7UqKpynLTT8zY6PrOqStUkNTu0zVJ65/BzoVVnDesIQhVXFWLXRr7GgRtEXoitRR
# gWCc9K6ofrCB1kp3bzoQ5b2QqdgdKLms0OIqJrb61EHg7Q81LkFOil56S1wmx3Sp
# LQtxrwS0wV1uYeMConF1PSLMukG+dTQCbAweqceWinxrOl3bWEWEWlUCrHp9Kazz
# /g3BcpJe0NQLttcof8lw8snFqSktJLfJhBjf5cDKi0rwqspcCE/xrz9OMbgbn2IO
# GMFNBBQOKlf2lTzHee6OQly87IQ8tMflNq7rNyfx93jg9gvQhFfFylgdJJBeVF0e
# xFA2gGH1cadhDl1a6T5+hCf5vf6Jxp0gFvKWgLDUxVdjb26Mm1ANxtA3oWad/4Fh
# wPkrydr1nidWLfC+Fr2zbAWMj3AwCZWa/mDroBif6V4GxU9glXM=
# SIG # End signature block