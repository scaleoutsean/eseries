#!/usr/bin/env pwsh

###########################################################################
# 
# Name: Password change script for local accounts on NetApp E-Series
# 
# Author: @scaleoutSean (https://github.com/scaleoutsean)
#
# Requirements: Microsoft PowerShell >=7.1, NetApp SANtricity >=11.60
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
#Requires -Version 7.1

<#
.SYNOPSIS
  This script uses the SANtricity API and requires admin credentials to set, and optinally validate, a new user password for a specified user account.
  It was tested on Linux with PowerShell 7.2.3 and 7.3.1 and SANtricity 11.74. It should work on Linux and Windows with PowerShell 7.1-7.3.
  Self-service password change (i.e. using admin account to change own password) works, but not been extensively tested so exercise caution.
.DESCRIPTION
  Script require three inputs: SANtricity API endpoint(s) (IPv4), admin credentials, user account name, and new user password to set.
  Admin credentials are used to access the SANtricity API and set a new password for the user account. 
  If two controllers are provided, the first is used by default and the second only if the first cannot be reached.
  TLS validation is automatically disabled because the script uses IP addresses.
.PARAMETER ApiEp
  SANtricity API endpoint(s) in IPv4 format. Examples: "8.4.4.3","3.4.4.8" (two controllers) or "8.4.4.3". Default: none
.PARAMETER ApiEpPort
  SANtricity API endpoint port. Default: 8443
.PARAMETER SanSysId
  SANtricity System ID. Example: "600A098000F63714000000005E79C17C"
.PARAMETER AdminAcc
  SANtricity account that can set password for other accounts. Example: admin. Default: none
.PARAMETER AdminPass
  SANtricity admin account's password (quote in single quotes if special characters are used). 8-30 characters.
.PARAMETER UserAcc
  SANtricity user account whose password is to be updated. Example: monitor. Default: none
.PARAMETER UserPass
  SANtricity user's new password (quote in single quotes if special characters are used). 8-30 characters. Default: none
.PARAMETER ValidateNewUserPass
  Switch that specifies whether to login and log out using the user account and new user password.
.PARAMETER CreateTranscript
  Switch that specifies whether to append script transcript (it will not log accounts or passwords) to change-password.log in the current directory.
.INPUTS
  None
.OUTPUTS 
  Version v1.1.0 of this script can optionally create a script transcript
.NOTES
  Version:        1.1.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2022/12/21
  Change: Small improvements and validation and transcript switches
.EXAMPLE
  ./change-password.ps1 -ApiEp "1.2.3.4","5.6.7.8" -ApiEpPort 8443 `n
    -SanSysId "600A098000F63714000000005E79C17C" `n
    -AdminAcc "admin" -AdminPass '4dmin123dJ3234f8RF' `n
    -UserAcc "monitor" -UserPass "monitor123" -ValidateNewUserPass
#>

#---------------------------------------------------------[Parameters and Declarations]------------------------------------------------------

Param (
    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API endpoint(s) as IPv4 addresses. Examples: "8.4.4.3","3.4.4.8" or "1.2.3.4"')]
    [ValidateNotNullOrEmpty()]
    [array]$ApiEp,
    
    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API endpoint port number. Default: 8443')]
    [ValidateNotNullOrEmpty()]
    [uint16]$ApiEpPort = 8443,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity System ID (World-Wide Name). Example: "21000000600A098000F63714000021115E79C17C"')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(32, 32)]
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
    [switch]$ValidateNewUserPass,

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'Create transcript change-password.log')]
    [switch]$CreateTranscript
)

$ErrorActionPreference = 'SilentlyContinue'

$Global:esession = (New-Object Microsoft.PowerShell.Commands.WebRequestSession)
$Global:SantricityController = 0

$headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
$headers.Add('Accept', 'application/json')
$headers.Add('Content-Type', 'application/json')

Function SantricityEndpoint {
    if ($ApiEp.Length -eq 2 -and $Global:SantricityController -eq 0) {
        $Global:SantricityController = 1
    }
    elseif ($ApiEp.Length -eq 2 -and $Global:SantricityController -eq 1) {
        $Global:SantricityController = 0
    }
    else {
        $Global:SantricityController = 0
    }
    $Global:API_ENDPOINT = 'https://' + $ApiEp[$Global:SantricityController] + ':' + $ApiEpPort
    return ($Global:API_ENDPOINT)
}

#---------------------------------------------------------[Functions]------------------------------------------------------

Function SantricityLogin {
    Param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Account,
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password
    )

    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept', 'application/json')
    $headers.Add('Content-Type', 'application/json')
    
    $body = "{
        `n  `"userId`": `"$Account`",
        `n  `"password`": `"$Password`",
        `n  `"xsrfProtected`": false
        `n}"
    $retryCount = 0
    $maxRetry = 1
    $retryPause = 3
    $API_ENDPOINT_LOGIN = $Global:API_ENDPOINT + '/' + 'devmgr/utils/login'
    while ($null -ne $API_ENDPOINT_LOGIN) {
        $API_ENDPOINT_LOGIN = $Global:API_ENDPOINT + '/' + 'devmgr/utils/login'
        Try {
            $response = Invoke-RestMethod -Uri $API_ENDPOINT_LOGIN -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'POST' -Headers $headers -Body $body -MaximumRetryCount 1 -RetryIntervalSec 3 -SessionVariable Global:esession -StatusCodeVariable estatus
            $API_ENDPOINT_LOGIN = $null
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
                Write-Host 'Unable to login likely due to wrong username or password or lockout because of too many retries. Giving up...'
                $API_ENDPOINT_LOGIN = $null
                Exit 100
            }
            else {
                Write-Host 'Will retry after a pause...'
                Start-Sleep -Seconds $retryPause
                if ($ApiEp.Length -eq 2) {
                    $Global:API_ENDPOINT = SantricityEndpoint
                }
            }
        }
    }
}

Function SantricitySystemIdVerify {
    Param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SanSysId
    )

    $API_ENDPOINT_SYSTEM = $Global:API_ENDPOINT + '/' + 'devmgr/v2/storage-systems'
    Try {
        $response = Invoke-RestMethod -Uri "$API_ENDPOINT_SYSTEM" -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'GET' -Headers $headers -MaximumRetryCount 1 -RetryIntervalSec 5 -WebSession $Global:esession -StatusCodeVariable estatus
        $SanSysIdReported = $response.wwn
        Return ($SanSysIdReported)
        if ($estatus -eq 200 -and ($SanSysWwn -eq $SanSysId)) {
        }
        elseif ($estatus -eq 200 -and $response.wwn -ne $SanSysId) {
            Write-Error -ErrorId 200 -Message "SAN System ID mismatch. Please verify System ID (WWN) and try again."
            Exit 200
        }
        else {
            Write-Host -ForegroundColor Red -ErrorAction Stop -OutVariable 200
            Exit 201
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
        $API_ENDPOINT_LOGIN = $Global:API_ENDPOINT + '/' + 'devmgr/utils/login'
        Invoke-RestMethod -Uri "$API_ENDPOINT_LOGIN" -SkipCertificateCheck -SslProtocol @('Tls13', 'Tls12') -Method 'DELETE' -Headers $headers -MaximumRetryCount 1 -RetryIntervalSec 2 -WebSession $Global:esession
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

    $body = "{
        `n  `"currentAdminPassword`": `"$AdminPass`",
        `n  `"updates`": [
        `n    {
        `n      `"userName`": `"$UserAcc`",
        `n      `"newPassword`": `"$UserPass`"
        `n    }
        `n  ]
        `n}"
    
    $API_ENDPOINT_USER = $Global:API_ENDPOINT + '/devmgr/v2/storage-systems/' + $SanSysId + '/' + 'local-users'
    Try {
        Invoke-RestMethod -Uri $API_ENDPOINT_USER -SkipCertificateCheck -SslProtocol Tls12 -Method 'POST' -Body $body -Headers $headers -MaximumRetryCount 1 -RetryIntervalSec 2 -WebSession $Global:esession -StatusCodeVariable estatus
        return $estatus
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

function SantricityPassValidate {
    param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Account,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password
    )

    Try {
        SantricityLogin -Account $Account -Password $Password
        SantricityLogout
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

#---------------------------------------------------------[Execution]------------------------------------------------------

if ($CreateTranscript) {
    Start-Transcript -LiteralPath ($pwd.Path + [IO.Path]::DirectorySeparatorChar + "change-password.log") -Append -IncludeInvocationHeader
}

$Global:API_ENDPOINT = 'https://' + $ApiEp[$Global:SantricityController] + ':' + $ApiEpPort

SantricityLogin -Account $AdminAcc -Password $AdminPass

$SanSysIdReported = SantricitySystemIdVerify -SanSysId $SanSysId
if ($SanSysId -ne $SanSysIdReported) {
    Write-Error 'System ID mismatch. This System ID:', $SanSysIdReported 
    Exit 200
}

$estatus = SantricityPassUpdate -AdminPass $AdminPass -UserAcc $UserAcc -UserPass $UserPass
if ($estatus -eq 204) {
    SantricityLogout
    if ($ValidateNewUserPass -eq $true) {
        $Global:esession = (New-Object Microsoft.PowerShell.Commands.WebRequestSession)
        SantricityPassValidate -Account $UserAcc -Password $UserPass
        SantricityLogout
    }
    Write-Host 'Success!'
    Exit 0
}
else {
    Write-Error 'Change of password failed. Check API endpoints, their reachability, and admin credentials.'
    Exit 1
}

if ($CreateTranscript) {
    Stop-Transcript
}

