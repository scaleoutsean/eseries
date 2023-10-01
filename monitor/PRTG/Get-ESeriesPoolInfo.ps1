#!/usr/bin/env pwsh

###########################################################################
# 
# Name: Get-ESeriesPoolInfo.ps1
# 
# Desc: EXE/Script sensor for pools on NetApp E-Series v11 w/ PRTG v20-23
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
  Gets a subset of analyzed metrics for specified DDP and send them as JSON to PRTG.
.DESCRIPTION
  Script requires just one controller. It defaults to 8443/TCP to access the SANtricity API.
  It uses username/password authentication, preferrably the read-only monitor role.
  Configure a PRTG ping or HTTPS sensor for to detect when a controller fails.  
.PARAMETER ApiEp
  SANtricity API endpoint as IPv4 or FQDN address. Example: "8.4.4.3". Default: none
.PARAMETER ApiPort
  SANtricity API port. Default: 8443
.PARAMETER SanSysId
  SANtricity's System ID. Default: "600A098000F63714000000005E79C17C"
.PARAMETER Account
  Monitor account. Default: monitor
.PARAMETER Password
  Password for the monitor account. Default: none
.PARAMETER Pool
  SANtricity DDP (pool) name to monitor. Example: "bkp2dsk". Default: none
.INPUTS
  None
.OUTPUTS 
  Stdout (JSON) for PRTG EXE/Script sensor
.NOTES
  Version:        1.0.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2023/10/02
  Change:         Initial release
.EXAMPLE
  Get-ESeriesPoolInfo.ps1 -ApiEp "192.168.1.0" -ApiPort 8443 `
    -SanSysId "600a098000f63714000000005e79c17c" -Account "monitor" -Password "monitor123" `
    -Pool "bkp2dsk"
#>

#---------------------------------------------------------[Parameters and Declarations]------------------------------------

Param (

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API endpoint as IPv4 addresses or FQDN. Example: 8.4.4.3. Default: none')]
    [ValidateNotNullOrEmpty()]
    [string]$ApiEp,

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'SANtricity API port. Default: 8443')]
    [ValidateNotNullOrEmpty()]
    [string]$ApiPort = '8443',

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
        Mandatory = $false,
        HelpMessage = 'SANtricty password for monitor account')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(8, 50)]
    [string]$Password,

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'SANtricity pool name to monitor. Default: none')]
    [ValidateNotNullOrEmpty()]
    [string]$Pool
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


# Function to return pool's statistics
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
        [string]$SanSysId
    )
        
    Try {
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/storage-pools"
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


# Filter DDPs
function FilterPools {
    param (
        [Parameter(Mandatory = $true)]
        [array]$responseList,
        [Parameter(Mandatory = $true)]
        [string]$Pool
    )
    
    $i = 0
    $filteredList = @()
    while ($i -lt ($responseList.count)) {        
        if ($responseList[$i].name -ne $Pool) {
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
$responseList = SantricityGetSubSystemMetrics -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
$responseList = FilterPools -ResponseList $responseList -Pool $Pool
$PrtgData = @{"prtg" = @{"result" = @() } }

foreach ($response in $responseList) {
    $PoolName = $response.name
    $raidDetails = $response.extents.ddpRAIDCapacities
    $i = 0
    $j = $response.extents.ddpRAIDCapacities.Length
    while ($i -ne $j) {
        if ($raidDetails[$i].ddpVolRAIDLevel -eq "raid6") {
            $R6UsableCapacity = $raidDetails[$i].usableCapacity
        }
        elseif ($raidDetails[$i].ddpVolRAIDLevel -eq "raid1") {
            $R1UsableCapacity = $raidDetails[$i].usableCapacity
        } else {
            # Unknown RAID level that doesn't currently exist. Ignore for now.
        }
        $i++
    }
    $record = $null
    $record = @(
        @{
            "channel"     = "Reserve disk count for reconstruction ($PoolName)";
            "value"       = $response.volumeGroupData.diskPoolData.reconstructionReservedDriveCount;
            "unit"        = "Custom";
            "customunit"  = "disk";
            "float"       = 0;
            "DecimalMode" = 0                      
        };
        @{
            "channel"     = "Allocation granularity on pool level ($PoolName)";
            "value"       = $response.volumeGroupData.diskPoolData.allocGranularity;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0                      
        };
        @{
            "channel"     = "Minimum drive count ($PoolName)";
            "value"       = $response.volumeGroupData.diskPoolData.minimumDriveCount;
            "unit"        = "Custom";
            "customunit"  = "disk";
            "float"       = 0;
            "DecimalMode" = 0                      
        };
        @{
            "channel"     = "Disk sector size recommended ($PoolName)";
            "value"       = $response.blkSizeRecommended;
            "unit"        = "Custom";
            "customunit"  = "bytes";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Used space ($PoolName)";
            "value"       = $response.usedSpace;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Total RAID space ($PoolName)";
            "value"       = $response.totalRaidedSpace;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Total extent capacity (R6) ($PoolName)";
            "value"       = $R6UsableCapacity;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Total extent capacity (R1) ($PoolName)";
            "value"       = $R1UsableCapacity;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Largest free extent size ($PoolName)";
            "value"       = $response.largestFreeExtentSize;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Free space ($PoolName)";
            "value"       = $response.freeSpace;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        }
    )
    $PrtgData.prtg.result += $record
}

$Global:esession = $null 
$Global:headers = $null
$responseList = $null
$PrtgData | ConvertTo-Json -Depth 3
