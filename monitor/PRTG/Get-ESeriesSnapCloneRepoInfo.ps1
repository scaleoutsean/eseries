#!/usr/bin/env pwsh

###########################################################################
# 
# Name: Get-ESeriesSnapCloneRepoInfo.ps1
# 
# Desc: EXE/Script sensor for Snap/Clone Repos on NetApp E-Series v11 w/ PRTG v20-23
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
  Gets snaphot and clone repository sizes and sends them as JSON to PRTG.
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
.INPUTS
  None
.OUTPUTS 
  Stdout (JSON) for PRTG EXE/Script sensor
.NOTES
  Version:        1.0.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2023/10/12
  Change:         Initial release
.EXAMPLE
  Get-ESeriesSnapCloneRepoInfo.ps1 -ApiEp "192.168.1.0" -ApiPort 8443 `
    -SanSysId "600a098000f63714000000005e79c17c" -Account "monitor" -Password "monitor123"
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
    [string]$Password

)


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
            Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiEp="10.113.1.158",

        [Parameter(
            Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiPort="8443",

        [Parameter(
            Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Account="monitor",

        [Parameter(
            Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Password="monitor123"
    
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


# Function to return system information
Function SantricityGetSystemInfo {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems"
        $systemInfo = Invoke-RestMethod -Uri $ApiEpUri -Method 'GET' -Headers $headers -WebSession $Global:esession
        Return $systemInfo
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


# Function to get SANtricity snapshot groups
# GET /storage-systems/{system-id}/snapshot-groups
# curl -X GET "https://127.0.0.1:8443/devmgr/v2/storage-systems/600A098000F63714000000005E79C17C/snapshot-groups"
Function SantricityGetSnapshotGroups {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/snapshot-groups"
        $snapshotgroups = Invoke-RestMethod -Uri $ApiEpUri -Method 'GET' -Headers $headers -WebSession $Global:esession
        return $snapshotgroups
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


# Function to get repository utilization for snapshots
# GET /storage-systems/{system-id}/snapshot-groups/repository-utilization
# curl -X GET "https://127.0.0.1/devmgr/v2/storage-systems/7F0000011E1E1E1E1E1E1E1E1E1E1E1E/snapshot-groups/repository-utilization"
Function SantricityGetSnapshotGroupsRepositoryUtilization {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/snapshot-groups/repository-utilization"
        $sru = Invoke-RestMethod -Uri $ApiEpUri -Method 'GET' -Headers $headers -WebSession $Global:esession
        return $sru
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


# Function to get repository utilization for clones (="snapshot volumes")
# GET /storage-systems/{system-id}/snapshot-volumes/repository-utilization
# curl -X GET "https://127.0.0.1/devmgr/v2/storage-systems/7F0000011E1E1E1E1E1E1E1E1E1E1E1E/snapshot-volumes/repository-utilization"
Function SantricityGetSnaphotVolumesRepositoryUtilization {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/snapshot-volumes/repository-utilization"
        $cru = Invoke-RestMethod -Uri $ApiEpUri -Method 'GET' -Headers $headers -WebSession $Global:esession
        Return $cru
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


# Function to get all volumes to get repo volume list
# GET /storage-systems/{system-id}/volumes
# curl -X GET "https://127.0.0.1/devmgr/v2/storage-systems/7F0000011E1E1E1E1E1E1E1E1E1E1E1E/volumes"
Function SantricityGetVolumes {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/volumes"
        $volumes = Invoke-RestMethod -Uri $ApiEpUri -Method 'GET' -Headers $headers -WebSession $Global:esession
        Return $volumes
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


# Function that filters volumes to only include volumes with "repos_" in the name and where volumeUse="concatVolume"
function SANtricityGetRepoVolumes {
    param (
        [Parameter(Mandatory = $true)]
        [array]$responseList
    )
    
    $i = 0
    $filteredList = @()
    while ($i -lt ($responseList.count)) {        
        if ($responseList[$i].name -match "\brepos_[0-9][0-9][0-9][0-9]\b" -and $responseList[$i].volumeUse -eq "concatVolume" -and $responseList[$i].name -notmatch "repos_0000") {
            $filteredList = $filteredList + $responseList[$i]
        }
        $i++
    }
    return $filteredList
}


# Function that calculates snapshot reserve utilization components
function SantricityGetSnapReserveUtilization {
    param (
        [Parameter(Mandatory = $true)]
        [array]$sru
    )
    $srbu,$srba = $null,$null
    foreach ($s in $sru) { 
        $srbu += [int64]$s.pitGroupBytesUsed
        $srba += [int64]$s.pitGroupBytesAvailable
    $SRUsed = [System.Math]::round($srbu,4)
    $SRAvail = [System.Math]::round($srba,4)
    $SRFullPct = [System.Math]::round(($srbu/($srba+$srbu))*100,3)
    return ($SRUsed, $SRAvail, $SRFullPct)
    }
}


# function to calculate total repository size for snapshots using information from snapshot groups
function SantricityGetTotalSnapRepoSize {
    param (
        [Parameter(Mandatory = $true)]
        [array]$snapshotGroups
    )    
    [int64]$TotalSnapRepoSize = ($snapshotGroups.repositoryCapacity | Measure-Object -Sum).Sum
    return ($TotalSnapRepoSize)
}


# Calculate aggregate ratio of pitGroupBytesAvailable vs pitGroupBytesAvailable + pitGroupBytesUsed for all clones
# This doesn't tell us anything about space available to any clone, it only tells us overall utilization 
function SantricityGetCloneReserveUtilization {
    param (
        [Parameter(Mandatory = $true)]
        [array]$cru
    )
    $cabu,$caba = $null,$null
    foreach ($c in $cru) {
        $cabu += [int64]$c.viewBytesUsed
        $caba += [int64]$c.viewBytesAvailable
    }
    $CRUsed = [System.Math]::round($cabu,4)
    $CRAvail = [System.Math]::round($caba,4)
    $CRFullPct = [System.Math]::round(($cabu/($caba+$cabu))*100,3)
    return ($CRUsed, $CRAvail, $CRFullPct)
}


# Function singles out the snapshot reserve with highest criticality and utilization
# Snapshot reserves that delete old snapshots are ignored; only snapshot reserves that stop IO on base volume are considered
function GetTopSnapshotRepo {
    param (
        [Parameter(Mandatory = $true)]
        [array]$sru
    )
    [array]$fullness = @()
    foreach ($snap in $sru) {         
        $fullness = 100*([int64]$snap.pitGroupBytesUsed/([int64]$snap.pitGroupBytesAvailable+[int64]$snap.pitGroupBytesUsed))
        $TopSnapRepoUtilization += $fullness
    }
    $TopSnapRepoUtilization = [System.Math]::round(($TopSnapRepoUtilization | Sort-Object -Descending | Select-Object -First 1), 2)
    return ($TopSnapRepoUtilization)
}

function PRTGDataRecord {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SystemName,
        [Parameter(Mandatory = $true)]
        [string]$RepoCap,
        [Parameter(Mandatory = $true)]
        [string]$SnapRepoCap,
        [Parameter(Mandatory = $true)]
        [string]$CloneRepoCap
  
    )
    $record = $null
    $record = @(
        @{
            "channel"     = "Snap and clone repo capacity ($SystemName)";
            "value"       = $RepoCap;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Clone repo capacity ($SystemName)";
            "value"       = $CloneRepoCap;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        };
        @{
            "channel"     = "Snap repo capacity ($SystemName)";
            "value"       = $SnapRepoCap;
            "unit"        = "BytesDisk";
            "VolumeSize"  = "Giga";
            "float"       = 0;
            "DecimalMode" = 0
        }
    ) 
    return ($record)
}

#---------------------------------------------------------[Execution]------------------------------------------------------

SantricityLogin -ApiEp $ApiEp -ApiPort $ApiPort -Account $Account -Password $Password

$systemInfo = SantricityGetSystemInfo -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
$SystemName = $systemInfo.name

$sgs = SantricityGetSnapshotGroups -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
$sru = SantricityGetSnapshotGroupsRepositoryUtilization -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
$snapRepoCap = SantricityGetTotalSnapRepoSize -snapshotGroups $sgs
$cru = SantricityGetSnaphotVolumesRepositoryUtilization -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
$SnapReserveStats = SantricityGetSnapReserveUtilization -sru $sru 

$CloneReserveStats = SantricityGetCloneReserveUtilization -cru $cru 
$cloneRepoCap = $cloneReserveStats[1]

$responseList = SantricityGetVolumes -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
$repoVolumeList = SANtricityGetRepoVolumes -responseList $responseList
$repoCap = [int64](($repoVolumeList.totalSizeInBytes | Measure-Object -Sum).Sum)

$PrtgData = @{"prtg" = @{"result" = @() } }
$PrtgData.prtg.result = PRTGDataRecord -SystemName $SystemName -RepoCap $repoCap -SnapRepoCap $snapRepoCap -CloneRepoCap $cloneRepoCap
$PrtgData | ConvertTo-Json -Depth 3

$Global:esession = $null 
$Global:headers = $null
$PrtgData = $null 
$systemInfo = $null
