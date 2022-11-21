#!/usr/bin/env pwsh

###########################################################################
# 
# Name: Password Change Script for NetApp E-Series non-Admin accounts
# 
# Author: @scaleoutSean (https://github.com/scaleoutsean/)
#
# Requirements: Microsoft PowerShell 7.1, NetApp SANtricity 11
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
###########################################################################

<#
.SYNOPSIS
  Script uses SANtricity API, administrator credentials and a user account to set a new user password for user account.
  It was tested on Linux with PowerShell 7.2.3 and SANtricity 11.74, but should work on Windows with PowerShell 7.1 or 7.2.
  Self-service password change (i.e. using admin account to change own password) should work, but not been tested out of caution because the array I tested with was remote.
.DESCRIPTION
  Script takes inputs (E-Series SANtricity API endpoint(s), admin credentials, user account name, and new user password to set new user password.
  Admin credentials are used to access the SANtricity API and set a new password for the user account. 
  Although two controllers can be specified, only the first is used. Retries and optional validation are implemented, but retries happen against the first controller provided.
  An enahnced version could introduce controller rotation, but for now failed calls should output errors or get caught during steps such as password validation.
  TLS validation is automatically disabled because the script works with IP addresses. 
  TLS would require FQDNs, valid TLS certificates and DNS resolution (and error handling for all three), so it is not a part of the initial release.
.PARAMETER ApiEp
  SANtricity API endpoint(s) in IPv4 format. Examples: @("8.4.4.3","3.4.4.8") or @("1.2.3.4"). Default: none
.PARAMETER ApiEpPort
  SANtricity API endpoint port. Default: 8443
.PARAMETER SanSysId
  SANtricity System ID. Example: "21000000600A098000F63714000021115E79C17C"
.PARAMETER AdminAcc
  SANtricity admin account who can set password for other accounts. Example: admin. Default: none
.PARAMETER AdminPass
  SANtricity admin account's password (quote in single quotes if special characters are used). 8-30 characters.
.PARAMETER UserAcc
  SANtricity user account whose password is to be updated. Example: monitor. Default: none
.PARAMETER UserPass
  SANtricity user's new password (quote in single quotes if special characters are used). 8-30 characters. Default: none
.PARAMETER ValidateNewUserPass
  Whether to attempt to login and log out using the user account and new user password. Exits silently if no error. Example: $true. Default: $false
.INPUTS
  None.
.OUTPUTS 
  Version v1.0.0 of this script has no log file
.NOTES
  Version:        1.0.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2022/11/21
  Purpose/Change: Initial script version
.EXAMPLE
  ./change-password.ps1 -ApiEp @("1.2.3.4", "5.6.7.8") -ApiEpPort 8443 `n
    -SanSysId "21000000600A098000F63714000021115E79C17C" `n
    -AdminAcc "admin" -AdminPass '4dmin123dJ3234f8RF' `n
    -UserAcc "monitor" -UserPass "monitor123" -ValidateNewUserPass $false
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------


Param (
    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API endpoint(s) in IPv4 format. Examples: @("8.4.4.3","3.4.4.8") or @("1.2.3.4")')]
    [ValidateNotNullOrEmpty()]
    [array]$ApiEp,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API endpoint port. Default: 8443')]
    [ValidateNotNullOrEmpty()]
    [uint16]$ApiEpPort = 8443,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity System ID. Example: "21000000600A098000F63714000021115E79C17C"')]
    [ValidateNotNullOrEmpty()]
    [string]$SanSysId,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'Administrator account')]
    [ValidateNotNullOrEmpty()]
    [string]$AdminAcc = 'admin',

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'Password of administrator account')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(8, 30)]
    [string]$AdminPass,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'User account to update')]
    [string]$UserAcc,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'User password to be set for user account')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(8, 30)]
    [string]$UserPass,

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'Validate new password for user account by executing test login')]
    [bool]$ValidateNewUserPass = $false
)

$ErrorActionPreference = 'SilentlyContinue'

$headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
$headers.Add('Accept', 'application/json')
$headers.Add('Content-Type', 'application/json')
$Global:esession = (New-Object Microsoft.PowerShell.Commands.WebRequestSession)
$Global:SantricityController = 0

Function SantricityEndpoint {    
    if ($ApiEp.Length -eq 2) {
        $Global:SantricityController = 0
        $API_ENDPOINT = 'https://' + $ApiEp[$Global:SantricityController] + ':' + $ApiEpPort
    }
    else {
        $API_ENDPOINT = 'https://' + $ApiEp[$Global:SantricityController] + ':' + $ApiEpPort
    }
    return ($API_ENDPOINT)
}

Function SantricityLogin {
    Param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $AdminAcc,
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $AdminPass
    )

    $retryCount = 0
    $maxRetry = 2
    $retryPause = 2

    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept', 'application/json')
    $headers.Add('Content-Type', 'application/json')

    $body = "{
        `n  `"userId`": `"$AdminAcc`",
        `n  `"password`": `"$AdminPass`",
        `n  `"xsrfProtected`": false
        `n}"

    $API_ENDPOINT = SantricityEndpoint
    $API_ENDPOINT_LOGIN = $API_ENDPOINT + '/' + 'devmgr/utils/login'

    Try {
        Invoke-RestMethod -Uri $API_ENDPOINT_LOGIN -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'POST' -Headers $headers -Body $body -MaximumRetryCount 3 -RetryIntervalSec 10 -SessionVariable Global:esession -StatusCodeVariable estatus
    }
    Catch {
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message
        }
        else {
            Write-Host $_
        }
        $retryCount += 1
        if ($retryCount -ge $maxRetry) {
            Write-Host 'Unable to login. Giving up...'
            $API_ENDPOINT_LOGIN = $null
        }
        else {
            Write-Host 'Will retry after a pause...'
            Start-Sleep -Seconds $retryPause
        }
    }
}

Function SantricitySystemIdVerify {

    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept', 'application/json')
    $headers.Add('Content-Type', 'application/json')

    $API_ENDPOINT = SantricityEndpoint
    $API_ENDPOINT_SYSTEM = $API_ENDPOINT + '/' + 'devmgr/v2/storage-systems'

    Try {
        $response = Invoke-RestMethod -Uri $API_ENDPOINT_SYSTEM -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'GET' -Headers $headers -MaximumRetryCount 2 -RetryIntervalSec 5 -WebSession $Global:esession -StatusCodeVariable estatus
        if ($estatus -eq 200 -and $response.accessVolume.id -eq $SanSysId) {
            return 
        }
        else {
        }
    }
    Catch {
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message
        }
        else {
            Write-Host $_
        }
    }
}

Function SantricityLogout {
    Try {
        $API_ENDPOINT = SantricityEndpoint
        $API_ENDPOINT_LOGIN = $API_ENDPOINT + '/' + 'devmgr/utils/login'
        Invoke-RestMethod -Uri "$API_ENDPOINT_LOGIN" -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'DELETE' -Headers $headers -MaximumRetryCount 2 -RetryIntervalSec 3 -WebSession $Global:esession
    } 
    Catch {
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message
        }
        else {
            Write-Host $_
        }
    }
}

Function SantricityPassUpdate {
    Param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AdminAcc,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AdminPass,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserAcc,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPass
    )

    $retryCount = 0
    $maxRetry = 4
    $retryPause = 4

    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept', 'application/json')
    $headers.Add('Content-Type', 'application/json')

    $body = "{
        `n  `"userId`": `"$AdminAcc`",
        `n  `"password`": `"$AdminPass`",
        `n  `"xsrfProtected`": false
        `n}"

    $API_ENDPOINT = SantricityEndpoint
    $API_ENDPOINT_LOGIN = $API_ENDPOINT + '/' + 'devmgr/utils/login'

    Try {
        $response = Invoke-RestMethod -Uri $API_ENDPOINT_LOGIN -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'POST' -Headers $headers -Body $body -MaximumRetryCount 5 -RetryIntervalSec 5 -SessionVariable Global:esession -StatusCodeVariable estatus
        if ($estatus -eq 200 -and $null -ne $response.userId) {
        }
    }
    Catch {
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message
        }
        else {
            Write-Host $_
        }
        $retryCount += 1
        if ($retryCount -ge $maxRetry) {
            Write-Host 'Failed to update password (does this usuer account exist?). Giving up...'
            $API_ENDPOINT_LOGIN = $null
        }
        else {
            Write-Host 'Will retry after a pause...'
            Start-Sleep -Seconds $retryPause
        }
    }

    $retryCount = 0
    $maxRetry = 2
    $retryPause = 2

    $body = "{
        `n  `"currentAdminPassword`": `"$AdminPass`",
        `n  `"updates`": [
        `n    {
        `n      `"userName`": `"$UserAcc`",
        `n      `"newPassword`": `"$UserPass`"
        `n    }
        `n  ]
        `n}"

    $API_ENDPOINT = SantricityEndpoint
    $API_ENDPOINT_SYSTEM = $API_ENDPOINT + '/' + 'devmgr/v2/storage-systems'
    $API_ENDPOINT_USER = $API_ENDPOINT_SYSTEM + '/' + $SanSysId + '/' + 'local-users'

    while ($null -ne $API_ENDPOINT_USER) {
        $API_ENDPOINT = SantricityEndpoint
        $API_ENDPOINT_SYSTEM = $API_ENDPOINT + '/' + 'devmgr/v2/storage-systems'
        $API_ENDPOINT_USER = $API_ENDPOINT_SYSTEM + '/' + $SanSysId + '/' + 'local-users'    
        Try {
            Invoke-RestMethod -Uri $API_ENDPOINT_USER -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'POST' -Headers $headers -Body $body -MaximumRetryCount 2 -RetryIntervalSec 5 -WebSession $Global:esession -StatusCodeVariable estatus
            if ($estatus -eq 204) {
                $API_ENDPOINT_USER = $null
                return($estatus)
            }
        }
        Catch {
            if ($_.ErrorDetails.Message) {
                Write-Host $_.ErrorDetails.Message
            }
            else {
                Write-Host $_
            }
            $retryCount += 1
            if ($retryCount -ge $maxRetry) {
                Write-Host 'Giving up...'
                $API_ENDPOINT_USER = $null
            }
            else {
                Write-Host 'Retrying after a break...'
                Start-Sleep -Seconds $retryPause
            }
        }
    }
}

function SantricityLoginTest {
    param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserAcc,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPass
    )

    Try {
        SantricityLogin -AdminAcc $UserAcc -AdminPass $UserPass
        SantricityLogout
        return $true
    } 
    Catch {
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message
        }
        else {
            Write-Host $_
        }
    }
} 

if ($esession) {
    $estatus = SantricityPassUpdate -AdminAcc $AdminAcc -AdminPass $AdminPass -UserAcc $UserAcc -UserPass $UserPass    
    if ($estatus -eq 204) {
        $log = ((Get-Date).ToString() + ' response OK')
        $log | Out-File -Append success.txt
        if ($ValidateNewUserPass -eq $true) {
            SantricityLoginTest -UserAcc $UserAcc -UserPass $UserPass
        }
        else {
        }  
    }
    else {
        Write-Error 'Change of password failed. Check API endpoints, accounts, passwords and reachability.'
        $log = ((Get-Date).ToString() + ' response NG')
        $log | Out-File -Append failure.txt    
    }
    SantricityLogout
}
else {
    Write-Host 'Failed to establish connection with E-Series SANtricity API.'
    Write-Error 'Change of password probably failed. Check API endpoints, accounts, passwords and network status.'
}
