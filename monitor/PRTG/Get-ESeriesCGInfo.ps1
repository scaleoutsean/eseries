#!/usr/bin/env pwsh

###########################################################################
# 
# Name: Get-ESeriesCGInfo.ps1
# 
# Desc: EXE/Script sensor for Consistency Group on NetApp E-Series v11 w/ PRTG v20-23
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
  Gets a basic metrics for the specified Consistency Group and sends them as JSON to PRTG.
.DESCRIPTION
  This script requires just one controller. It defaults to 8443/TCP to access the SANtricity API.
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
.PARAMETER CG
  SANtricity consistency group name. Example: "CG_ELK". Default: none
.INPUTS
  None
.OUTPUTS 
  Stdout (JSON) for PRTG EXE/Script sensor
.NOTES
  Version:        1.0.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2023/10/30
  Change:         Initial release
.EXAMPLE
  Get-ESeriesCGInfo.ps1 -ApiEp "192.168.1.0" -ApiPort "8443" `
    -SanSysId "600a098000f63714000000005e79c17c" -Account "monitor" -Password "monitor123" `
    -CG "CG_ELK"
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
        HelpMessage = 'SANtricity CG name to monitor. Default: none. Example: CG_ELK_01')]
    [ValidateNotNullOrEmpty()]
    [string]$CG

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


# Function to return all CGs from the system
Function SantricityGetCGs {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/consistency-groups"
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


# Function to return all CG member volumes from the system
Function SantricityGetCGMemberVolumes {
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
        [string]$CGId
    )
            
    Try {
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/consistency-groups/" + $CGId + "/member-volumes"
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


# Function to return CG's snapshots for a given CG ID
Function SantricityGetCGSnapshots {
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
        [string]$CGId

    )
            
    Try {
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/consistency-groups/" + $CGId + "/snapshots"
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


# Function to return *all* snapshot groups on the system
Function SantricityGetSystemSnapshotGroups {
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


# Function to return all snapshot volumes (clones) on the system
Function SantricityGetSystemSnapshotVolumes {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/snapshot-volumes"
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


# Function to return all volumes' averaged performance metrics on the system
Function SantricityGetSubSystemVolumeMetrics {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/analysed-volume-statistics"
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


# Function to return a list of all volumes on the system
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


# Function to return all snapshot schedules on the system
Function SantricityGetSnapshotSchedules {
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
        $ApiEpUri = "https://" + $ApiEp + ":" + $ApiPort + "/devmgr/v2/storage-systems/" + $SanSysId + "/snapshot-schedules"
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

#---------------------------------------------------------[Execution]------------------------------------------------------

# login to SANtricity
SantricityLogin -ApiEp $ApiEp -ApiPort $ApiPort -Account $Account -Password $Password

# get all volumes on the system
$SanVolumes = SantricityGetVolumes -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId

# get perfomance metrics for all volumes
$SanVolumeStats = SantricityGetSubSystemVolumeMetrics -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId

# get list of Consistency Groups from the system
$SanConsistencyGroups = SantricityGetCGs -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId 

# name of CG we're looking for
$Global:consistencyGroupId = ($SanConsistencyGroups | Where-Object -Property name -EQ $CG).id

# get number of CG snapshots used on the system
$CGSnapshotsUsed = (($SanConsistencyGroups | Where-Object -Property name -EQ $CG).uniqueSequenceNumber).Length

# get list of CG member volumes (it can be 0)
$SanCGMemberVolumes = SantricityGetCGMemberVolumes -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId -CGId $consistencyGroupId
$SanCGMemberVolumesCount = $SanCGMemberVolumes.Count

# get list of CG snapshots for our CG
$SanCGSnapshots = SantricityGetCGSnapshots -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId -CGId $consistencyGroupId
if ($SanCGSnapshots.Count -lt 1) {
    $SanCGSnapshotImageCount = 0
    $SanCGSnapshotGroupCount = 0
}
else {
    $SanCGSnapshotImageCount = ($SanCGSnapshots | Select-Object -Property pitTimestamp).Count
    $SanCGSnapshotGroupCount = ($SanCGSnapshots | Select-Object -Property pitTimestamp | Group-Object -Property pitTimestamp).Count
}

# age of latest CG snapshot
$CGLatestSnapshotPitTimestamp = ($SanCGSnapshots  | Sort-Object -Descending -Property viewTime | Get-Unique | Select-Object -First 1).pitTimestamp
$CgLatestSnapshotAgeHrs = [math]::round((((Get-Date (Get-Date).ToUniversalTime() -UFormat %s) - $CGLatestSnapshotPitTimestamp) / 3600), 2) 

# get list of all clones ("snapshot volumes") on the system and count those that belong to our CG
$SanSystemSnapshotVolumes = SantricityGetSystemSnapshotVolumes -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
$CGSnapshotVolumes = ($SanSystemSnapshotVolumes | Where-Object -Property consistencyGroupId -EQ $consistencyGroupId)
if (($CGSnapshotVolumes).Count -gt 0) {
    $SanCGSnapshotVolumeCount = $CGSnapshotVolumes.Count
} else { 
    $SanCGSnapshotVolumeCount = 0
}

# get repository utilization by CG clones 
$CGRepositoryUtilizationBytes = 0
foreach ($vol in $CGSnapshotVolumes) {
    $CGRepositoryUtilizationBytes += $vol.repositoryCapacity
}

# find autoDelete limit for CG snapshots and calculate used and available
# max number of snapshots per CG is 32 (https://www.netapp.com/media/17120-tr4724.pdf)
$SanCGAutoDeleteLimit = ($SanConsistencyGroups | Where-Object -Property id -EQ $consistencyGroupId).autoDeleteLimit
if ($SanCGAutoDeleteLimit -eq 0) { 
    # If autodelete limit isn't set the API returns 0, so we use the default, 32
    $CgSnapshotUnusedCount = (32 - $SanCGSnapshotGroupCount)
} else {
    $CgSnapshotUnusedCount = $SanCGAutoDeleteLimit - $SanCGSnapshotGroupCount
}

# first build list of volumes in CG, then loop through them and check if cache settings are consistent across CG members
$CGBaseVolumeNames = @()
foreach ($baseVolName in $SanCGMemberVolumes) {
    $CGBaseVolumeNames += $baseVolName.baseVolumeName 
}
$CGVolumes = $SanCGMemberVolumes.volumeId
[System.Collections.ArrayList]$vCacheSettings = @()
[int]$vCacheSettingsCount = 0
$CGCapacity = 0
foreach ($v in $SanVolumes) {
    if ($CGVolumes -contains $v.id) {
        $CGCapacity += [int64]$v.totalSizeInBytes
        null = $vCacheSettings.Add($v.cache)
    }
}
$vCacheSettingsCount = @($vCacheSettings | Get-Unique).Length

# get performance for each volume from CG
[System.Collections.ArrayList]$CGPerfMetrics = @()
foreach ($v in $SanVolumeStats) {
    if ($CGvolumes -contains $v.volumeId) {
        $vPerfData = ($v.volumeName, $v.readThroughput, $v.writeThroughput, $v.readIOps, $v.writeIOps)
        $null = $CGPerfMetrics.Add($vPerfData)
    }
}
foreach ($vStats in $CGPerfMetrics) {
    $CGReadThroughput = $CGReadThroughput + [float]$vStats[1]
    $CGWriteThroughput = $CGWriteThroughput + [float]$vStats[2]
    $CGReadIOps = $CGReadIOps + [float]$vStats[3]
    $CGWriteIOps = $CGWriteIOps + [float]$vStats[4]
}

# get list of all clone ("snapshot volume") names for our CG
$cloneName = @()
$cloneSubOptimalCount = 0
foreach ($clone in $SanSystemSnapshotVolumes) {
    if ($clone.boundToPIT -eq $True -and $clone.consistencyGroupId -eq $consistencyGroupId -and $clone.status -eq "optimal") {
        $cloneName += (($clone.name).Split(":")[0])
    } elseif ($clone.consistencyGroupId -eq $consistencyGroupId) {
        $cloneSubOptimalCount += 1
    }
}
$CGCloneCount = ($cloneName | Get-Unique).Count
$CGCloneOptimalCount = $CGCloneCount - $cloneSubOptimalCount

# get list of all snapshot volumes (clones) for the CG
$MOS = ($CGSnapshotVolumes | Where-Object -Property consistencyGroupId -EQ $consistencyGroupId)
$MOSRO = ($MOS | Where-Object -Property accessMode -EQ "readOnly")
$MOSROCount = ($MOSRO).Count
$MOSRW = ($MOS | Where-Object -Property accessMode -EQ "readWrite")
$MOSRWCount = ($MOSRW).Count

# find the most recent clones by accessType and calculate clone age in hours
if ($MOSRWCount -eq 0) {
    $CgSnapshotRWAgeHrs = 0
} else {    
    $SRWS = ($MOSRW | Sort-Object -Descending -Property viewTime | Get-Unique | Select-Object -First 1).viewTime
    $CgSnapshotRWAgeHrs = [math]::round((((Get-Date (Get-Date).ToUniversalTime() -UFormat %s) - $SRWS) / 3600), 2)
}
if ($MOSROCount -eq 0) {
    $CgSnapshotROAgeHrs = 0
} else {
    $SROS = ($MOSRO | Sort-Object -Descending -Property viewTime | Get-Unique | Select-Object -First 1).viewTime
    $CgSnapshotROAgeHrs = [math]::round((((Get-Date (Get-Date).ToUniversalTime() -UFormat %s) - $SROS) / 3600), 2) 
}

# get all snapshot schedules on the system and check if our CG has one
$SanSnapshotSchedules = SantricityGetSnapshotSchedules -ApiEp $ApiEp -ApiPort $ApiPort -SanSysId $SanSysId
if ($SanSnapshotSchedules.Count -gt 0)  {
    foreach ($schedule in $SanSnapshotSchedules) {
        if ($schedule.targetObject -eq $consistencyGroupId -and $schedule.scheduleStatus -eq "active") {
            $CGActiveSnapshotSchedule = 1
        }
    }
}

# https://www.paessler.com/manuals/prtg/custom_sensors#command_line
$PrtgData = @{"prtg" = @{"result" = @() } }
$record = @(
    @{
        "channel" = "Member volumes ($CG)";
        "value"   = $SanCGMemberVolumesCount;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Read throughput ($CG)";
        "value"   = $CGReadThroughput;
        "unit"    = "Custom";
        "CustomUnit"  = "MB/s";
        "float"   = 1
    };
    @{
        "channel" = "Write throughput ($CG)";
        "value"   = $CGWriteThroughput;
        "unit"    = "Custom";
        "CustomUnit"  = "MB/s";
        "float"   = 1
    };
    @{
        "channel" = "Read IOPS ($CG)";
        "value"   = $CGReadIOPs;
        "unit"    = "Custom";
        "CustomUnit"  = "IOPS";
        "float"   = 1
    };
    @{
        "channel" = "Write IOPS ($CG)";
        "value"   = $CGWriteIOPs;
        "unit"    = "Custom";
        "CustomUnit"  = "IOPS";
        "float"   = 1
    };
    @{
        "channel" = "Clone repo capacity used ($CG)";
        "value"   = $CGRepositoryUtilizationBytes;
        "unit"        = "BytesDisk";
        "customunit"  = "Byte";
        "SpeedSize"   = "GigaByte";
        "float"       = 0;
        "DecimalMode" = 0
    };
    @{
        "channel" = "RO clone volumes ($CG)";
        "value"   = $MOSROCount;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "RW clone volumes ($CG)";
        "value"   = $MOSRWCount;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Volume clones ($CG)";
        "value"   = ($MOSRW.count + $MOSRO.count);
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Clone sets ($CG)";
        "value"   = $CGCloneCount;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Clone sets in optimal state ($CG)";
        "value"   = $CGCloneOptimalCount;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Snapshot limit ($CG)";
        "value"   = $SanCGAutoDeleteLimit;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Snapshots used ($CG)";
        "value"   = $CGSnapshotsUsed;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Snapshots available ($CG)";
        "value"   = $CgSnapshotUnusedCount;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel" = "Unique cache settings ($CG)";
        "value"   = $vCacheSettingsCount;
        "unit"    = "Count";
        "float"   = 0
    };
    @{
        "channel"     = "Age of newest snapshot ($CG)";
        "value"       = $CgLatestSnapshotAgeHrs;
        "unit"        = "Count";
        "CustomUnit"  = "hrs";
        "float"       = 1;
        "DecimalMode" = 1
    };
    @{
        "channel"     = "Age of newest RO clone ($CG)";
        "value"       = $CgSnapshotROAgeHrs;
        "unit"        = "Count";
        "CustomUnit"  = "hrs";
        "float"       = 1;
        "DecimalMode" = 1
    };
    @{
        "channel"     = "Age of newest RW clone ($CG)";
        "value"       = $CgSnapshotRWAgeHrs;
        "unit"        = "Count";
        "CustomUnit"  = "hrs";
        "float"       = 1;
        "DecimalMode" = 1
    };
    @{
        "channel"     = "Active snapshot schedule ($CG)";
        "value"       = $CGActiveSnapshotSchedule;
        "unit"        = "Count";
        "CustomUnit"  = "hrs";
        "float"       = 1;
        "DecimalMode" = 1
    };
    @{
        "channel"     = "Capacity ($CG)";
        "value"       = $CGCapacity;
        "unit"        = "BytesDisk";
        "customunit"  = "Byte";
        "SpeedSize"   = "GigaByte";
        "float"       = 0;
        "DecimalMode" = 0
    }
)

$PrtgData.prtg.result += $record
$PrtgData | ConvertTo-Json -Depth 3
$Global:esession = $null 
$Global:headers = $null
$record = $null
