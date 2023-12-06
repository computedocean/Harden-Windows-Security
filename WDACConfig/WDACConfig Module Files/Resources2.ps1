# Defining a custom object to store the signer information
class Signer {
    [System.String]$ID
    [System.String]$Name
    [System.String]$CertRoot
    [System.String]$CertPublisher
}

function Get-SignerInfo {
    <#
    .SYNOPSIS
        Function that takes an XML file path as input and returns an array of Signer objects
    .INPUTS
        System.IO.FileInfo
    .OUTPUTS
        Signer[]
    .PARAMETER XmlFilePath
        The XML file path that the user selected for WDAC simulation.
    #>
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$XmlFilePath
    )
    begin {
        # Load the XML file
        $Xml = [System.Xml.XmlDocument](Get-Content -Path $XmlFilePath)
    }
    process {
        # Select the Signer nodes
        [System.Object[]]$Signers = $Xml.SiPolicy.Signers.Signer

        # Create an empty array to store the output
        [Signer[]]$Output = @()

        # Loop through each Signer node and extract the information
        foreach ($Signer in $Signers) {
            # Create a new Signer object and assign the properties
            [Signer]$SignerObj = [Signer]::new()
            $SignerObj.ID = $Signer.ID
            $SignerObj.Name = $Signer.Name
            $SignerObj.CertRoot = $Signer.CertRoot.Value
            $SignerObj.CertPublisher = $Signer.CertPublisher.Value

            # Add the Signer object to the output array
            $Output += $SignerObj
        }
    }
    end {
        # Return the output array
        return $Output
    }
}

function Get-TBSCertificate {
    <#
    .SYNOPSIS
        Function to calculate the TBS of a certificate
    .INPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2
    .OUTPUTS
        System.String
    .PARAMETER Cert
        The certificate that is going to be used to retrieve its TBS value
    #>
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert
    )

    # Get the raw data of the certificate
    [System.Byte[]]$RawData = $Cert.RawData

    # Create an ASN.1 reader to parse the certificate
    [System.Formats.Asn1.AsnReader]$AsnReader = New-Object -TypeName System.Formats.Asn1.AsnReader -ArgumentList $RawData, ([System.Formats.Asn1.AsnEncodingRules]::DER)

    # Read the certificate sequence
    [System.Formats.Asn1.AsnReader]$Certificate = $AsnReader.ReadSequence()

    # Read the TBS (To be signed) value of the certificate
    $TbsCertificate = $Certificate.ReadEncodedValue()

    # Read the signature algorithm sequence
    [System.Formats.Asn1.AsnReader]$SignatureAlgorithm = $Certificate.ReadSequence()

    # Read the algorithm OID of the signature
    [System.String]$AlgorithmOid = $SignatureAlgorithm.ReadObjectIdentifier()

    # Define a hash function based on the algorithm OID
    switch ($AlgorithmOid) {
        '1.2.840.113549.1.1.4' { $HashFunction = [System.Security.Cryptography.MD5]::Create() ; break }
        '1.2.840.10040.4.3' { $HashFunction = [System.Security.Cryptography.SHA1]::Create() ; break }
        '2.16.840.1.101.3.4.3.2' { $HashFunction = [System.Security.Cryptography.SHA256]::Create() ; break }
        '2.16.840.1.101.3.4.3.3' { $HashFunction = [System.Security.Cryptography.SHA384]::Create() ; break }
        '2.16.840.1.101.3.4.3.4' { $HashFunction = [System.Security.Cryptography.SHA512]::Create() ; break }
        '1.2.840.10045.4.1' { $HashFunction = [System.Security.Cryptography.SHA1]::Create() ; break }
        '1.2.840.10045.4.3.2' { $HashFunction = [System.Security.Cryptography.SHA256]::Create() ; break }
        '1.2.840.10045.4.3.3' { $HashFunction = [System.Security.Cryptography.SHA384]::Create() ; break }
        '1.2.840.10045.4.3.4' { $HashFunction = [System.Security.Cryptography.SHA512]::Create() ; break }
        '1.2.840.113549.1.1.5' { $HashFunction = [System.Security.Cryptography.SHA1]::Create() ; break }
        '1.2.840.113549.1.1.11' { $HashFunction = [System.Security.Cryptography.SHA256]::Create() ; break }
        '1.2.840.113549.1.1.12' { $HashFunction = [System.Security.Cryptography.SHA384]::Create() ; break }
        '1.2.840.113549.1.1.13' { $HashFunction = [System.Security.Cryptography.SHA512]::Create() ; break }
        # sha-1WithRSAEncryption
        '1.3.14.3.2.29' { $HashFunction = [System.Security.Cryptography.SHA1]::Create() ; break }
        default { throw "No handler for algorithm $AlgorithmOid" }
    }

    # Compute the hash of the TBS value using the hash function
    [System.Byte[]]$Hash = $HashFunction.ComputeHash($TbsCertificate.ToArray())

    # Convert the hash to a hex string
    [System.String]$HexStringOutput = [System.BitConverter]::ToString($Hash) -replace '-', ''

    # Return the output
    return $HexStringOutput
}

function Get-AuthenticodeSignatureEx {
    <#
    .SYNOPSIS
        Helps to get the 2nd aka nested signer/signature of the dual signed files
    .NOTES
        This function is used in a very minimum capacity by the WDACConfig module
    .LINK
        https://www.sysadmins.lv/blog-en/reading-multiple-signatures-from-signed-file-with-powershell.aspx
        https://www.sysadmins.lv/disclaimer.aspx
    .PARAMETER FilePath
        The path of the file(s) to get the signature of
    .INPUTS
        System.String[]
    .OUTPUTS
        System.Management.Automation.Signature
    #>

    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [System.String[]]$FilePath
    )

    begin {

        # Define the signature of the Crypt32.dll library functions to use
        [System.String]$Signature = @'
    [DllImport("crypt32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool CryptQueryObject(
        int dwObjectType,
        [MarshalAs(UnmanagedType.LPWStr)]
        string pvObject,
        int dwExpectedContentTypeFlags,
        int dwExpectedFormatTypeFlags,
        int dwFlags,
        ref int pdwMsgAndCertEncodingType,
        ref int pdwContentType,
        ref int pdwFormatType,
        ref IntPtr phCertStore,
        ref IntPtr phMsg,
        ref IntPtr ppvContext
    );
    [DllImport("crypt32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool CryptMsgGetParam(
        IntPtr hCryptMsg,
        int dwParamType,
        int dwIndex,
        byte[] pvData,
        ref int pcbData
    );
    [DllImport("crypt32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool CryptMsgClose(
        IntPtr hCryptMsg
    );
    [DllImport("crypt32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool CertCloseStore(
        IntPtr hCertStore,
        int dwFlags
    );
'@

        # Load the System.Security assembly to use the SignedCms class
        Add-Type -AssemblyName 'System.Security' -ErrorAction SilentlyContinue -Verbose:$false
        # Add the Crypt32.dll library functions as a type
        Add-Type -MemberDefinition $Signature -Namespace 'PKI' -Name 'Crypt32' -ErrorAction SilentlyContinue -Verbose:$false
                
        # Define some constants for the CryptQueryObject function parameters
        [System.Int16]$CERT_QUERY_OBJECT_FILE = 0x1
        [System.Int32]$CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED = 0x400
        [System.Int16]$CERT_QUERY_FORMAT_FLAG_BINARY = 0x2

        # Define a helper function to get the timestamps of the countersigners
        function Get-TimeStamps {
            param (
                $SignerInfo
            )

            [System.Object[]]$RetValue = @()
            
            foreach ($CounterSignerInfos in $Infos.CounterSignerInfos) {
                # Get the signing time attribute from the countersigner info object
                $STime = ($CounterSignerInfos.SignedAttributes | Where-Object -FilterScript { $_.Oid.Value -eq '1.2.840.113549.1.9.5' }).Values | `
                    Where-Object -FilterScript { $null -ne $_.SigningTime }
                # Create a custom object with the countersigner certificate and signing time properties
                $TsObject = New-Object psobject -Property @{
                    Certificate = $CounterSignerInfos.Certificate
                    SigningTime = $STime.SigningTime.ToLocalTime()
                }
                # Add the custom object to the return value array
                $RetValue += $TsObject
            }
            # Return the array of custom objects with countersigner info
            $RetValue

        }
    }
    process {
        # For each file path, get the authenticode signature using the built-in cmdlet
        Get-AuthenticodeSignature $FilePath | ForEach-Object -Process {

            # Store the output object in a variable
            [System.Management.Automation.Signature]$Output = $_
           
            if ($null -ne $Output.SignerCertificate) {

                # If the output object has a signer certificate property
                # Initialize some variables to store the output parameters of the CryptQueryObject function
                [System.Int64]$PdwMsgAndCertEncodingType = 0
                [System.Int64]$PdwContentType = 0
                [System.Int64]$PdwFormatType = 0
                [System.IntPtr]$PhCertStore = [System.IntPtr]::Zero
                [System.IntPtr]$PhMsg = [System.IntPtr]::Zero
                [System.IntPtr]$PpvContext = [System.IntPtr]::Zero
                
                # Call the CryptQueryObject function to get the handle of the PKCS #7 message from the file path
                $Return = [PKI.Crypt32]::CryptQueryObject(
                    $CERT_QUERY_OBJECT_FILE,
                    $Output.Path,
                    $CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
                    $CERT_QUERY_FORMAT_FLAG_BINARY,
                    0,
                    [ref]$pdwMsgAndCertEncodingType,
                    [ref]$pdwContentType,
                    [ref]$pdwFormatType,
                    [ref]$phCertStore,
                    [ref]$phMsg,
                    [ref]$ppvContext
                )
                # If the function fails, return nothing
                if (!$Return) { return } 
                                
                # Initialize a variable to store the size of the PKCS #7 message data
                [System.Int64]$PcbData = 0 
                
                # Call the CryptMsgGetParam function to get the size of the PKCS #7 message data
                $Return = [PKI.Crypt32]::CryptMsgGetParam($phMsg, 29, 0, $null, [ref]$pcbData)
               
                # If the function fails, return nothing
                if (!$Return) { return }

                # Create a byte array to store the PKCS #7 message data
                $pvData = New-Object -TypeName 'System.Byte[]' -ArgumentList $pcbData 
                
                # Call the CryptMsgGetParam function again to get the PKCS #7 message data
                $Return = [PKI.Crypt32]::CryptMsgGetParam($PhMsg, 29, 0, $PvData, [System.Management.Automation.PSReference]$PcbData)
               
                # Create a SignedCms object to decode the PKCS #7 message data
                [System.Security.Cryptography.Pkcs.SignedCms]$SignedCms = New-Object -TypeName 'Security.Cryptography.Pkcs.SignedCms' 
                
                # Decode the PKCS #7 message data and populate the SignedCms object properties
                $SignedCms.Decode($PvData) 
                
                # Get the first signer info object from the SignedCms object
                $Infos = $SignedCms.SignerInfos[0]
                
                # Add some properties to the output object, such as TimeStamps, DigestAlgorithm and NestedSignature
                $Output | Add-Member -MemberType NoteProperty -Name TimeStamps -Value $null
                $Output | Add-Member -MemberType NoteProperty -Name DigestAlgorithm -Value $Infos.DigestAlgorithm.FriendlyName
                
                # Call the helper function to get the timestamps of the countersigners and assign it to the TimeStamps property
                $Output.TimeStamps = Get-TimeStamps -SignerInfo $Infos
                
                # Check if there is a nested signature attribute in the signer info object by looking for the OID 1.3.6.1.4.1.311.2.4.1
                $second = $Infos.UnsignedAttributes | Where-Object -FilterScript { $_.Oid.Value -eq '1.3.6.1.4.1.311.2.4.1' }
                
                if ($Second) {

                    # If there is a nested signature attribute                    
                    # Get the value of the nested signature attribute as a raw data byte array
                    $value = $Second.Values | Where-Object -FilterScript { $_.Oid.Value -eq '1.3.6.1.4.1.311.2.4.1' }
                    
                    # Create another SignedCms object to decode the nested signature data
                    [System.Security.Cryptography.Pkcs.SignedCms]$SignedCms2 = New-Object -TypeName 'Security.Cryptography.Pkcs.SignedCms' 

                    # Decode the nested signature data and populate the SignedCms object properties
                    $SignedCms2.Decode($value.RawData) 
                    $Output | Add-Member -MemberType NoteProperty -Name NestedSignature -Value $null
                    
                    # Get the first signer info object from the nested signature SignedCms object
                    $Infos = $SignedCms2.SignerInfos[0]
                    
                    # Create a custom object with some properties of the nested signature, such as signer certificate, digest algorithm and timestamps
                    $Nested = New-Object -TypeName 'psobject' -Property @{
                        SignerCertificate = $Infos.Certificate
                        DigestAlgorithm   = $Infos.DigestAlgorithm.FriendlyName
                        TimeStamps        = Get-TimeStamps -SignerInfo $Infos
                    }
                    # Assign the custom object to the NestedSignature property of the output object
                    $Output.NestedSignature = $Nested
                }
                # Return the output object with the added properties
                $Output

                # Close the handles of the PKCS #7 message and the certificate store
                [void][PKI.Crypt32]::CryptMsgClose($PhMsg)
                [void][PKI.Crypt32]::CertCloseStore($PhCertStore, 0)
            }
            else {
                # If the output object does not have a signer certificate property
                # Return the output object as it is
                $Output
            }
        }
    }
    end {}
}

function Get-SignedFileCertificates {
    <#
    .SYNOPSIS
        A function to get all the certificates from a signed file or a certificate object and output a Collection
    .PARAMETER FilePath
        Optional parameter, the function will get all the certificates from this file if this parameter is used
    .PARAMETER X509Certificate2
        Optional parameter, the function will get all the certificates from this certificate object if this parameter is used
    .INPUTS
        System.String
        System.Security.Cryptography.X509Certificates.X509Certificate2
    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    #>
    param (
        [Parameter()]
        [System.String]$FilePath,
        [Parameter(ValueFromPipeline = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$X509Certificate2
    )

    begin {
        # Create an X509Certificate2Collection object
        [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]$CertCollection = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    }

    process {
        # Check which parameter set is used
        if ($FilePath) {
            # If the FilePath parameter is used, import all the certificates from the file
            $CertCollection.Import($FilePath, $null, 'DefaultKeySet')
        }
        elseif ($X509Certificate2) {
            # If the CertObject parameter is used, add the certificate object to the collection
            $CertCollection.Add($X509Certificate2)
        }
    }

    end {
        # Return the collection
        return $CertCollection
    }
}

function Get-CertificateDetails {
    <#
    .SYNOPSIS
        A function to detect Root, Intermediate and Leaf certificates
    .INPUTS
        System.String
        System.Management.Automation.SwitchParameter
    .OUTPUTS
        System.Object[]
    #>
    param (
        [Parameter(ParameterSetName = 'Based on File Path', Mandatory = $true)]
        [System.String]$FilePath,

        [Parameter(ParameterSetName = 'Based on Certificate', Mandatory = $true)]
        $X509Certificate2,

        [Parameter(ParameterSetName = 'Based on Certificate')]
        [System.String]$LeafCNOfTheNestedCertificate, # This is used only for when -X509Certificate2 parameter is used, so that we can filter out the Leaf certificate and only get the Intermediate certificates at the end of this function

        [Parameter(ParameterSetName = 'Based on File Path')]
        [Parameter(ParameterSetName = 'Based on Certificate')]
        [System.Management.Automation.SwitchParameter]$IntermediateOnly,

        [Parameter(ParameterSetName = 'Based on File Path')]
        [Parameter(ParameterSetName = 'Based on Certificate')]
        [System.Management.Automation.SwitchParameter]$LeafCertificate
    )

    # An array to hold objects
    [System.Object[]]$Obj = @()

    if ($FilePath) {
        # Get all the certificates from the file path using the Get-SignedFileCertificates function
        $CertCollection = Get-SignedFileCertificates -FilePath $FilePath | Where-Object -FilterScript { $_.EnhancedKeyUsageList.FriendlyName -ne 'Time Stamping' }
    }
    else {
        # The "| Where-Object -FilterScript {$_ -ne 0}" part is used to filter the output coming from Get-AuthenticodeSignatureEx function that gets nested certificate
        $CertCollection = Get-SignedFileCertificates -X509Certificate2 $X509Certificate2 | Where-Object -FilterScript { $_.EnhancedKeyUsageList.FriendlyName -ne 'Time Stamping' } | Where-Object -FilterScript { $_ -ne 0 }
    }

    # Loop through each certificate in the collection and call this function recursively with the certificate object as an input
    foreach ($Cert in $CertCollection) {

        # Build the certificate chain
        [System.Security.Cryptography.X509Certificates.X509Chain]$Chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain

        # Set the chain policy properties
        $chain.ChainPolicy.RevocationMode = 'NoCheck'
        $chain.ChainPolicy.RevocationFlag = 'EndCertificateOnly'
        $chain.ChainPolicy.VerificationFlags = 'NoFlag'

        [void]$Chain.Build($Cert)

        # If AllCertificates is present, loop through all chain elements and display all certificates
        foreach ($Element in $Chain.ChainElements) {
            # Create a custom object with the certificate properties

            # Extract the data after CN= in the subject and issuer properties
            # When a common name contains a comma ',' then it will automatically be wrapped around double quotes. E.g., "Skylum Software USA, Inc."
            # The methods below are conditional regex. Different patterns are used based on the availability of at least one double quote in the CN field, indicating that it had comma in it so it had been enclosed with double quotes by system

            $Element.Certificate.Subject -match 'CN=(?<InitialRegexTest2>.*?),.*' | Out-Null
            [System.String]$SubjectCN = $matches['InitialRegexTest2'] -like '*"*' ? ($Element.Certificate.Subject -split 'CN="(.+?)"')[1] : $matches['InitialRegexTest2']

            $Element.Certificate.Issuer -match 'CN=(?<InitialRegexTest3>.*?),.*' | Out-Null
            [System.String]$IssuerCN = $matches['InitialRegexTest3'] -like '*"*' ? ($Element.Certificate.Issuer -split 'CN="(.+?)"')[1] : $matches['InitialRegexTest3']

            # Get the TBS value of the certificate using the Get-TBSCertificate function
            [System.String]$TbsValue = Get-TBSCertificate -cert $Element.Certificate
            # Create a custom object with the extracted properties and the TBS value
            $Obj += [pscustomobject]@{
                SubjectCN = $SubjectCN
                IssuerCN  = $IssuerCN
                NotAfter  = $element.Certificate.NotAfter
                TBSValue  = $TbsValue
            }
        }
    }

    if ($FilePath) {

        # The reason the commented code below is not used is because some files such as C:\Windows\System32\xcopy.exe or d3dcompiler_47.dll that are signed by Microsoft report a different Leaf certificate common name when queried using Get-AuthenticodeSignature
        # (Get-AuthenticodeSignature -FilePath $FilePath).SignerCertificate.Subject -match 'CN=(?<InitialRegexTest4>.*?),.*' | Out-Null

        [System.Security.Cryptography.X509Certificates.X509Certificate]$CertificateUsingAlternativeMethod = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($FilePath)
        $CertificateUsingAlternativeMethod.Subject -match 'CN=(?<InitialRegexTest4>.*?),.*' | Out-Null

        [System.String]$TestAgainst = $matches['InitialRegexTest4'] -like '*"*' ? ((Get-AuthenticodeSignature -FilePath $FilePath).SignerCertificate.Subject -split 'CN="(.+?)"')[1] : $matches['InitialRegexTest4']

        if ($IntermediateOnly) {

            $FinalObj = $Obj |
            Where-Object -FilterScript { $_.SubjectCN -ne $_.IssuerCN } | # To omit Root certificate from the result
            Where-Object -FilterScript { $_.SubjectCN -ne $TestAgainst } | # To omit the Leaf certificate
            Group-Object -Property TBSValue | ForEach-Object -Process { $_.Group[0] } # To make sure the output values are unique based on TBSValue property

            return [System.Object[]]$FinalObj

        }
        elseif ($LeafCertificate) {

            $FinalObj = $Obj |
            Where-Object -FilterScript { $_.SubjectCN -ne $_.IssuerCN } | # To omit Root certificate from the result
            Where-Object -FilterScript { $_.SubjectCN -eq $TestAgainst } | # To get the Leaf certificate
            Group-Object -Property TBSValue | ForEach-Object -Process { $_.Group[0] } # To make sure the output values are unique based on TBSValue property

            return [System.Object[]]$FinalObj
        }

    }
    # If nested certificate is being processed and X509Certificate2 object is passed
    elseif ($X509Certificate2) {

        if ($IntermediateOnly) {

            $FinalObj = $Obj |
            Where-Object -FilterScript { $_.SubjectCN -ne $_.IssuerCN } | # To omit Root certificate from the result
            Where-Object -FilterScript { $_.SubjectCN -ne $LeafCNOfTheNestedCertificate } | # To omit the Leaf certificate
            Group-Object -Property TBSValue | ForEach-Object -Process { $_.Group[0] } # To make sure the output values are unique based on TBSValue property

            return [System.Object[]]$FinalObj

        }
        elseif ($LeafCertificate) {

            $FinalObj = $Obj |
            Where-Object -FilterScript { $_.SubjectCN -ne $_.IssuerCN } | # To omit Root certificate from the result
            Where-Object -FilterScript { $_.SubjectCN -eq $LeafCNOfTheNestedCertificate } | # To get the Leaf certificate
            Group-Object -Property TBSValue | ForEach-Object -Process { $_.Group[0] } # To make sure the output values are unique based on TBSValue property

            return [System.Object[]]$FinalObj
        }
    }
}

function Compare-SignerAndCertificate {
    <#
    .SYNOPSIS
        a function that takes WDAC XML policy file path and a Signed file path as inputs and compares the output of the Get-SignerInfo and Get-CertificateDetails functions
    .INPUTS
        System.String
    .OUTPUTS
        System.Object[]
    #>
    param(
        [Parameter(Mandatory = $true)][System.String]$XmlFilePath,
        [Parameter(Mandatory = $true)][System.String]$SignedFilePath
    )

    # Get the signer information from the XML file path using the Get-SignerInfo function
    [Signer[]]$SignerInfo = Get-SignerInfo -XmlFilePath $XmlFilePath

    # An array to store the details of the Primary certificate's Intermediate certificate(s) of the signed file
    [System.Object[]]$PrimaryCertificateIntermediateDetails = @()

    # An array to store the details of the Nested certificate of the signed file
    [System.Object[]]$NestedCertificateDetails = @()

    # An array to store the final comparison results of this function
    [System.Object[]]$ComparisonResults = @()

    # Get the intermediate certificate(s) details of the Primary certficiate from the signed file using the Get-CertificateDetails function
    [System.Object[]]$PrimaryCertificateIntermediateDetails = Get-CertificateDetails -IntermediateOnly -FilePath $SignedFilePath

    # Get the Nested (Secondary) certificate of the signed file, if any
    [System.Management.Automation.Signature]$ExtraCertificateDetails = Get-AuthenticodeSignatureEx -FilePath $SignedFilePath

    # Extract the Nested (Secondary) certificate from the nested property
    $NestedCertificate = ($ExtraCertificateDetails).NestedSignature.SignerCertificate

    if ($null -ne $NestedCertificate) {

        # First get the CN of the leaf certificate of the nested Certificate
        $NestedCertificate.Subject -match 'CN=(?<InitialRegexTest1>.*?),.*' | Out-Null
        $LeafCNOfTheNestedCertificate = $matches['InitialRegexTest1'] -like '*"*' ? ($NestedCertificate.Subject -split 'CN="(.+?)"')[1] : $matches['InitialRegexTest1']

        # Send the nested certificate along with its Leaf certificate's CN to the Get-CertificateDetails function with -IntermediateOnly parameter in order to only get the intermediate certificates of the Nested certificate
        $NestedCertificateDetails = Get-CertificateDetails -IntermediateOnly -X509Certificate2 $NestedCertificate -LeafCNOfTheNestedCertificate $LeafCNOfTheNestedCertificate
    }

    # Get the leaf certificate details of the Main Certificate from the signed file path
    [System.Object]$LeafCertificateDetails = Get-CertificateDetails -LeafCertificate -FilePath $SignedFilePath

    # Get the leaf certificate details of the Nested Certificate from the signed file path, if it exists
    if ($null -ne $NestedCertificate) {
        # append an X509Certificate2 object to the array
        $NestedLeafCertificateDetails = Get-CertificateDetails -LeafCertificate -X509Certificate2 $NestedCertificate -LeafCNOfTheNestedCertificate $LeafCNOfTheNestedCertificate
    }

    # Loop through each signer in the signer information array
    foreach ($Signer in $SignerInfo) {
        # Create a custom object to store the comparison result for this signer
        $ComparisonResult = [pscustomobject]@{
            SignerID            = $Signer.ID
            SignerName          = $Signer.Name
            SignerCertRoot      = $Signer.CertRoot
            SignerCertPublisher = $Signer.CertPublisher
            CertSubjectCN       = $null
            CertIssuerCN        = $null
            CertNotAfter        = $null
            CertTBSValue        = $null
            CertRootMatch       = $false
            CertNameMatch       = $false
            CertPublisherMatch  = $false
            FilePath            = $SignedFilePath # Add the file path to the object
        }

        # Loop through each certificate in the certificate details array of the Main Cert
        foreach ($Certificate in $PrimaryCertificateIntermediateDetails) {

            # Check if the signer's CertRoot (referring to the TBS value in the xml file which belongs to an intermediate cert of the file)...
            # ...matches the TBSValue of the file's certificate (TBS values of one of the intermediate certificates of the file since -IntermediateOnly parameter is used earlier and that's what FilePublisher level uses)
            # So this checks to see if the Signer's TBS value in xml matches any of the TBS value(s) of the file's intermediate certificate(s), if it does, that means that file is allowed to run by the WDAC engine
            
            # Or if the Signer's CertRoot matches the TBS value of the file's primary certificate's Leaf Certificate
            # This can happen with other rules than FilePublisher etc.
            if (($Signer.CertRoot -eq $Certificate.TBSValue) -or ($Signer.CertRoot -eq $LeafCertificateDetails.TBSValue)) {

                # Assign the certificate properties to the comparison result object and set the CertRootMatch to true based on further conditions
                $ComparisonResult.CertSubjectCN = $Certificate.SubjectCN
                $ComparisonResult.CertIssuerCN = $Certificate.IssuerCN
                $ComparisonResult.CertNotAfter = $Certificate.NotAfter
                $ComparisonResult.CertTBSValue = $Certificate.TBSValue

                # if the signed file has nested certificate, only set a flag instead of setting the entire CertRootMatch property to true
                if ($null -ne $NestedCertificate) {
                    $CertRootMatchPart1 = $true
                }
                else {
                    # meaning one of the TBS values of the file's intermediate certs or File's Primary Leaf Certificate's TBS value is in the xml file signers' TBS values
                    $ComparisonResult.CertRootMatch = $true
                }

                # Check if the signer's name (Referring to the one in the XML file) matches the Intermediate certificate's SubjectCN or Leaf Certificate's SubjectCN
                if (($Signer.Name -eq $Certificate.SubjectCN) -or ($Signer.Name -eq $LeafCertificateDetails.SubjectCN)) {
                    # Set the CertNameMatch to true
                    $ComparisonResult.CertNameMatch = $true # this should naturally be always true like the CertRootMatch because this is the CN of the same cert that has its TBS value in the xml file in signers
                }

                # Check if the signer's CertPublisher (aka Leaf Certificate's CN used in the xml policy) matches the leaf certificate's SubjectCN (of the file)
                if ($Signer.CertPublisher -eq $LeafCertificateDetails.SubjectCN) {

                    # if the signed file has nested certificate, only set a flag instead of setting the entire CertPublisherMatch property to true
                    if ($null -ne $NestedCertificate) {
                        $CertPublisherMatchPart1 = $true
                    }
                    else {
                        $ComparisonResult.CertPublisherMatch = $true
                    }
                }

                # Break out of the inner loop whether we found a match for this signer or not
                break
            }
        }

        # Nested Certificate TBS processing, if it exists
        if ($null -ne $NestedCertificate) {

            # Loop through each certificate in the NESTED certificate details array
            foreach ($Certificate in $NestedCertificateDetails) {

                # Check if the signer's CertRoot (referring to the TBS value in the xml file which belongs to an intermediate cert of the file)...
                # ...matches the TBSValue of the file's certificate (TBS values of one of the intermediate certificates of the file since -IntermediateOnly parameter is used earlier and that's what FilePublisher level uses)
                # So this checks to see if the Signer's TBS value in xml matches any of the TBS value(s) of the file's intermediate certificate(s), if yes, that means that file is allowed to run by WDAC engine
                if ($Signer.CertRoot -eq $Certificate.TBSValue) {

                    # Assign the certificate properties to the comparison result object and set the CertRootMatch to true
                    $ComparisonResult.CertSubjectCN = $Certificate.SubjectCN
                    $ComparisonResult.CertIssuerCN = $Certificate.IssuerCN
                    $ComparisonResult.CertNotAfter = $Certificate.NotAfter
                    $ComparisonResult.CertTBSValue = $Certificate.TBSValue

                    # When file has nested signature, only set a flag instead of setting the entire property to true
                    $CertRootMatchPart2 = $true

                    # Check if the signer's Name matches the Intermediate certificate's SubjectCN
                    if ($Signer.Name -eq $Certificate.SubjectCN) {
                        # Set the CertNameMatch to true
                        $ComparisonResult.CertNameMatch = $true # this should naturally be always true like the CertRootMatch because this is the CN of the same cert that has its TBS value in the xml file in signers
                    }

                    # Check if the signer's CertPublisher (aka Leaf Certificate's CN used in the xml policy) matches the leaf certificate's SubjectCN (of the file)
                    if ($Signer.CertPublisher -eq $LeafCNOfTheNestedCertificate) {
                        # If yes, set the CertPublisherMatch to true for this comparison result object
                        $CertPublisherMatchPart2 = $true
                    }

                    # Break out of the inner loop whether we found a match for this signer or not
                    break
                }
            }
        }

        # if the signed file has nested certificate
        if ($null -ne $NestedCertificate) {

            # check if both of the file's certificates (Nested and Main) are available in the Signers in xml policy
            if (($CertRootMatchPart1 -eq $true) -and ($CertRootMatchPart2 -eq $true)) {
                $ComparisonResult.CertRootMatch = $true # meaning all of the TBS values of the double signed file's intermediate certificates exists in the xml file's signers' TBS values
            }
            else {
                $ComparisonResult.CertRootMatch = $false
            }

            # check if Lean certificate CN of both of the file's certificates (Nested and Main) are available in the Signers in xml policy
            if (($CertPublisherMatchPart1 -eq $true) -and ($CertPublisherMatchPart2 -eq $true)) {
                $ComparisonResult.CertPublisherMatch = $true
            }
            else {
                $ComparisonResult.CertPublisherMatch = $false
            }
        }

        # Add the comparison result object to the comparison results array
        [System.Object[]]$ComparisonResults += $ComparisonResult
    }

    # Return the comparison results array
    return $ComparisonResults
}

function Get-FileRuleOutput {
    <#
    .SYNOPSIS
        a function to load an xml file and create an output array of custom objects that contain the file rules that are based on file hashes
    .PARAMETER XmlPath
        Path to the XML file that user selected for WDAC simulation
    .INPUTS
        System.IO.FileInfo
    .OUTPUTS
        System.Object[]
    #>
    param(
        [parameter(Mandatory = $true)]
        [System.IO.FileInfo]$XmlPath
    )

    # Load the xml file into a variable
    $Xml = [System.Xml.XmlDocument](Get-Content -Path $XmlPath)

    # Create an empty array to store the output
    [System.Object[]]$OutputHashInfoProcessing = @()

    # Loop through each file rule in the xml file
    foreach ($FileRule in $Xml.SiPolicy.FileRules.Allow) {

        # Extract the hash value from the Hash attribute
        [System.String]$Hashvalue = $FileRule.Hash

        # Extract the hash type from the FriendlyName attribute using regex
        [System.String]$HashType = $FileRule.FriendlyName -replace '.* (Hash (Sha1|Sha256|Page Sha1|Page Sha256|Authenticode SIP Sha256))$', '$1'

        # Extract the file path from the FriendlyName attribute using regex
        [System.IO.FileInfo]$FilePathForHash = $FileRule.FriendlyName -replace ' (Hash (Sha1|Sha256|Page Sha1|Page Sha256|Authenticode SIP Sha256))$', ''

        # Create a custom object with the three properties
        $Object = [PSCustomObject]@{
            HashValue       = $Hashvalue
            HashType        = $HashType
            FilePathForHash = $FilePathForHash
        }

        # Add the object to the output array if it is not a duplicate hash value
        if ($OutputHashInfoProcessing.HashValue -notcontains $Hashvalue) {
            $OutputHashInfoProcessing += $Object
        }
    }

    # Only show the Authenticode Hash SHA256
    [System.Object[]]$OutputHashInfoProcessing = $OutputHashInfoProcessing | Where-Object -FilterScript { $_.hashtype -eq 'Hash Sha256' }

    # Return the output array
    return $OutputHashInfoProcessing
}
