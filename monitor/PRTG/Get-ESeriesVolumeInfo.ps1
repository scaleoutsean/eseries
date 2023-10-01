#!/usr/bin/env pwsh

###########################################################################
# 
# Name: Get-ESeriesVolumeInfo.ps1
# 
# Desc: EXE/Script sensor for volumes on NetApp E-Series v11 w/ PRTG v20-23
# 
# Author: @scaleoutSean (https://github.com/scaleoutsean)
#
# Requirements: Microsoft PowerShell 5.1 (x86), NetApp SANtricity >=11.60
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

#Requires -Version 5.1

<#
.SYNOPSIS
  Gets a subset of analyzed metrics for specified volume and send them as JSON to PRTG.
.DESCRIPTION
  This script requires just one controller. It defaults to 8443/TCP to access the SANtriity API.
  It uses username/password authentication, preferrably the read-only monitor role.
  Configure ping or HTTPS sensor for the controllers to detect a failed controller.
  It is recommended to use the low-priveleged SANtricity monitor account.
.PARAMETER ApiEp
  SANtricity API endpoint as IPv4 address or FQDN. Example: "8.4.4.3". Default: none
.PARAMETER ApiPort
  SANtricity API port. Default: 8443
.PARAMETER SanSysId
  SANtricity's System ID. Default: "600A098000F63714000000005E79C17C"
.PARAMETER Account
  Monitor account. Default: monitor
.PARAMETER Password
  Password for the monitor account. Default: none
.PARAMETER Vol
  SANtricity volume name to monitor. Example: "pgdata". Default: none
.INPUTS
  None
.OUTPUTS 
  Stdout (JSON) for PRTG EXE/Script sensor
.NOTES
  Version:        1.0.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2023/10/01
  Change:         Initial release
.EXAMPLE
  Get-ESeriesVolumeInfo.ps1 -ApiEp "192.168.1.0" -ApiPort "8443" `
    -SanSysId "600a098000f63714000000005e79c17c" -Account "monitor" -Password "monitor123" `
    -Vol "pgdata"
#>

#---------------------------------------------------------[Parameters and Declarations]------------------------------------

Param (

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API endpoint as IPv4 addresses or FQDN. Example: 8.4.4.3. Default: none')]
    [ValidateNotNullOrEmpty()]
    [string]$ApiEp,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API port. Default: 8443')]
    [ValidateNotNullOrEmpty()]
    [string]$ApiPort,

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'SANtricity System ID (World-Wide Name). Example: 600A098000F63714000021115E79C17C')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(32, 32)]
    [string]$SanSysId = '600A098000F63714000021115E79C17C',

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'SANtricty monitor account. Default: monitor')]
    [ValidateNotNullOrEmpty()]
    [string]$Account = 'monitor',

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricty password for monitor account')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(8, 50)]
    [string]$Password,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity volume name to monitor. Default: none')]
    [ValidateNotNullOrEmpty()]
    [string]$Vol
)

$ErrorActionPreference = 'SilentlyContinue'

$Global:headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
$headers.Add('Accept', 'application/json')
$headers.Add('Content-Type', 'application/json')
$Global:esession = (New-Object Microsoft.PowerShell.Commands.WebRequestSession)

#---------------------------------------------------------[Ignore Self-Signed TLS Certificate]-----------------------------

# SO - ignore self-signed TLS certificate
# https://stackoverflow.com/questions/36456104/invoke-restmethod-ignore-self-signed-certs

if (-not("dummy" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Dummy {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Dummy.ReturnTrue);
    }
}
"@
}

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()

#---------------------------------------------------------[Ignore Self-Signed TLS Certificate]-----------------------------

#---------------------------------------------------------[Functions]------------------------------------------------------

# Function to login to SANtricity
Function SantricityLogin {
    Param (

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiEp,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiPort,

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

    $API_ENDPOINT_LOGIN = 'https://' + $ApiEp + ':' + $ApiPort + '/' + 'devmgr/utils/login'
    Try {
        $null = Invoke-RestMethod -Uri $API_ENDPOINT_LOGIN -Method 'POST' -Headers $headers -Body $body -SessionVariable Global:esession
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


# Function to return volumes' statistics
Function SantricityGetSubSystemMetrics {
    Param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiEp,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiPort,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SanSysId,
        
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubSystem
    )
        
    Try {
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/analysed-" + $SubSystem + "-statistics"
        $responseList = Invoke-RestMethod -Uri $ApiEpUri -Method 'GET' -Headers $headers -WebSession $Global:esession 
        Return $responseList
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


# Filter volumes
function FilterVolumes {
    param (
        [Parameter(Mandatory = $true)]
        [array]$responseList,
        [Parameter(Mandatory = $true)]
        [string]$Vol
    )
    
    $i = 0
    $filteredList = @()
    while ($i -lt ($responseList.count)) {        
        if ($responseList[$i].VolumeName -ne $Vol) {
        }
        else {
            $filteredList = $filteredList + $responseList[$i]
        }
        $i++
    }
    return($filteredList)
}

#---------------------------------------------------------[Execution]------------------------------------------------------

$responseList = $null
SantricityLogin -ApiEp $ApiEp -ApiPort $ApiPort -Account $Account -Password $Password
$responseList = SantricityGetSubSystemMetrics -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId -SubSystem 'volume'
$responseList = FilterVolumes -ResponseList $responseList -Vol $Vol
$PrtgData = @{"prtg" = @{"result" = @() } }

foreach ($response in $responseList) {
    $VolumeName = $response.volumeName
    $record = $null
    $record = @(
        @{
            "channel"     = "Read IOps ($VolumeName)";
            "value"       = [math]::round(($response.readIOps), 2);
            "unit"        = "Custom";
            "customunit"  = "IO/s";
            "float"       = 1;
            "DecimalMode" = 1
                            
        };
        @{
            "channel"     = "Write IOps ($VolumeName)";
            "value"       = [math]::round(($response.writeIOps), 2);
            "unit"        = "Custom";
            "customunit"  = "IO/s";
            "float"       = 1;
            "DecimalMode" = 1
                            
        };
        @{
            "channel"     = "Other IOps ($VolumeName)";
            "value"       = [math]::round(($response.otherIOps), 2);
            "unit"        = "Custom";
            "customunit"  = "IO/s";
            "float"       = 1;
            "DecimalMode" = 1
                            
        };
        @{
            "channel"     = "Combined IOps ($VolumeName)";
            "value"       = [math]::round(($response.combinedIOps), 2);
            "unit"        = "Custom";
            "customunit"  = "IO/s";
            "float"       = 1;
            "DecimalMode" = 1
                            
        };
        @{
            "channel"     = "Read throughput ($VolumeName)";
            "value"       = [math]::round(($response.readThroughput), 2);
            "unit"        = "Custom";
            "customunit"  = "MB/s";
            "float"       = 1;
            "DecimalMode" = 1
                            
        };
        @{
            "channel"     = "Write throughput ($VolumeName)";
            "value"       = [math]::round(($response.writeThroughput), 2);
            "unit"        = "Custom";
            "customunit"  = "MB/s";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Combined throughput ($VolumeName)";
            "value"       = [math]::round(($response.combinedThroughput), 2);
            "unit"        = "Custom";
            "customunit"  = "MB/s";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Read response time ($VolumeName)";
            "value"       = [math]::round(($response.readResponseTime), 2);
            "unit"        = "Custom";
            "customunit"  = "ms";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Write response time ($VolumeName)";
            "value"       = [math]::round(($response.writeResponseTime), 2);
            "unit"        = "Custom";
            "customunit"  = "ms";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Combined response time ($VolumeName)";
            "value"       = [math]::round(($response.combinedResponseTime), 2);
            "unit"        = "Custom";
            "customunit"  = "ms";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Read response time variation ($VolumeName)";
            "value"       = [math]::round(($response.readResponseTimeStdDev), 2);
            "unit"        = "Custom";
            "customunit"  = "StdDev";
            "float"       = 1;
            "DecimalMode" = 1;
            "ShowChart"   = 0
        };
        @{
            "channel"     = "Write response time variation ($VolumeName)";
            "value"       = [math]::round(($response.writeResponseTimeStdDev), 2);
            "unit"        = "Custom";
            "customunit"  = "StdDev";
            "float"       = 1;
            "DecimalMode" = 1;
            "ShowChart"   = 0
        };
        @{
            "channel"     = "Combined response time variation ($VolumeName)";
            "value"       = [math]::round(($response.combinedResponseTimeStdDev), 2);
            "unit"        = "Custom";
            "customunit"  = "StdDev";
            "float"       = 1;
            "DecimalMode" = 1;
            "ShowChart"   = 0
        };
        @{
            "channel"     = "Read hit response time ($VolumeName)";
            "value"       = [math]::round(($response.readHitResponseTime), 2);
            "unit"        = "Custom";
            "customunit"  = "ms";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Write hit response time ($VolumeName)";
            "value"       = [math]::round(($response.writeHitResponseTime), 2);
            "unit"        = "Custom";
            "customunit"  = "ms";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Average read operation size ($VolumeName)";
            "value"       = [math]::round(($response.averageReadOpSize), 2);
            "unit"        = "Custom";
            "customunit"  = "bytes";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Full stripe writes percentage ($VolumeName)";
            "value"       = [math]::round(($response.fullStripeWritesBytesPercent), 2);
            "unit"        = "Custom";
            "customunit"  = "%";
            "float"       = 1;
            "DecimalMode" = 1
        };
        @{
            "channel"     = "Flash cache hit percent ($VolumeName)";
            "value"       = [math]::round(($response.flashCacheHitPct), 2);
            "unit"        = "Custom";
            "customunit"  = "%";
            "float"       = 1;
            "DecimalMode" = 1
        };
    )
    $PrtgData.prtg.result += $record
}

$Global:esession = $null 
$Global:headers = $null
$responseList = $null
$PrtgData | ConvertTo-Json -Depth 3
