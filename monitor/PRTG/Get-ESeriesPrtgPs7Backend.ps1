#!/usr/bin/env pwsh

#Requires -Version 7.0

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('system', 'volume', 'pool', 'snaprepo', 'cg')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$ApiEp,

    [Parameter(Mandatory = $true)]
    [string]$ApiPort,

    [Parameter(Mandatory = $true)]
    [string]$SanSysId,

    [Parameter(Mandatory = $true)]
    [string]$Account,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [string]$Vol,
    [string]$Pool,
    [string]$CG,
    [string]$SantricityModulePath
)

$ErrorActionPreference = 'Stop'

function New-PrtgErrorJson {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    @{
        prtg = @{
            error = 1
            text  = $Message
        }
    } | ConvertTo-Json -Depth 5
}

function New-PrtgResultJson {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Result
    )

    @{
        prtg = @{
            result = $Result
        }
    } | ConvertTo-Json -Depth 8
}

function Import-SANtricityBackendModule {
    param (
        [string]$ModulePath
    )

    $candidatePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($ModulePath)) {
        $candidatePaths += [System.IO.Path]::GetFullPath($ModulePath)
    }

    $candidatePaths += [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../reference/santricity-powershell/santricity/santricity.psd1'))
    $candidatePaths += [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'santricity.psd1'))

    foreach ($candidate in $candidatePaths | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate) {
            Import-Module -Name $candidate -Force
            return
        }
    }

    Import-Module -Name 'santricity' -Force
}

function Connect-PrtgSantricity {
    $baseUrl = "https://${ApiEp}:$ApiPort"
    & {
        Connect-SANtricity -BaseUrl $baseUrl -Username $Account -Password $Password -StorageSystemId $SanSysId -SkipCertificateCheck | Out-Null
    } 6>$null
}

function Invoke-SanGet {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [bool]$UseSystemScope = $true
    )

    Invoke-SANtricityRequest -Method GET -Path $Path -UseSystemScope:$UseSystemScope
}

function Get-ObjectName {
    param (
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [string[]]$PropertyNames = @('storageSystemName', 'name')
    )

    foreach ($propertyName in $PropertyNames) {
        if ($InputObject.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$InputObject.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    return 'UNKNOWN'
}

function Get-AgeHours {
    param (
        [object]$Timestamp
    )

    if ($null -eq $Timestamp -or [string]::IsNullOrWhiteSpace([string]$Timestamp)) {
        return 0
    }

    $nowEpoch = [int64](Get-Date (Get-Date).ToUniversalTime() -UFormat %s)
    return [math]::Round((($nowEpoch - [int64]$Timestamp) / 3600), 2)
}

function Get-SystemResults {
    $systemStats = Invoke-SanGet -Path '/analysed-system-statistics'
    $systemInfo = Invoke-SanGet -Path "/storage-systems/$SanSysId" -UseSystemScope:$false

    $systemName = Get-ObjectName -InputObject $systemStats

    @(
        @{ channel = "Average CPU utilization ($systemName)"; value = [math]::Round([double]$systemStats.cpuAvgUtilization, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
        @{ channel = "Maximum CPU utilization ($systemName)"; value = [math]::Round([double]$systemStats.maxCpuUtilization, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1; ShowChart = 0 },
        @{ channel = "Read IOps ($systemName)"; value = [math]::Round([double]$systemStats.readIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
        @{ channel = "Write IOps ($systemName)"; value = [math]::Round([double]$systemStats.writeIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
        @{ channel = "Other IOps ($systemName)"; value = [math]::Round([double]$systemStats.otherIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
        @{ channel = "Combined IOps ($systemName)"; value = [math]::Round([double]$systemStats.combinedIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
        @{ channel = "Read throughput ($systemName)"; value = [math]::Round([double]$systemStats.readThroughput, 2); unit = 'Custom'; customunit = 'MB/s'; float = 1; DecimalMode = 1 },
        @{ channel = "Write throughput ($systemName)"; value = [math]::Round([double]$systemStats.writeThroughput, 2); unit = 'Custom'; customunit = 'MB/s'; float = 1; DecimalMode = 1 },
        @{ channel = "Combined throughput ($systemName)"; value = [math]::Round([double]$systemStats.combinedThroughput, 2); unit = 'Custom'; customunit = 'MB/s'; float = 1; DecimalMode = 1 },
        @{ channel = "Read response time ($systemName)"; value = [math]::Round([double]$systemStats.readResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
        @{ channel = "Write response time ($systemName)"; value = [math]::Round([double]$systemStats.writeResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
        @{ channel = "Combined response time ($systemName)"; value = [math]::Round([double]$systemStats.combinedResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
        @{ channel = "Read response time variation ($systemName)"; value = [math]::Round([double]$systemStats.readResponseTimeStdDev, 2); unit = 'Custom'; customunit = 'StdDev'; float = 1; DecimalMode = 1; ShowChart = 0 },
        @{ channel = "Write response time variation ($systemName)"; value = [math]::Round([double]$systemStats.writeResponseTimeStdDev, 2); unit = 'Custom'; customunit = 'StdDev'; float = 1; DecimalMode = 1; ShowChart = 0 },
        @{ channel = "Combined response time variation ($systemName)"; value = [math]::Round([double]$systemStats.combinedResponseTimeStdDev, 2); unit = 'Custom'; customunit = 'StdDev'; float = 1; DecimalMode = 1; ShowChart = 0 },
        @{ channel = "Cache hit rate ($systemName)"; value = [math]::Round([double]$systemStats.cacheHitBytesPercent, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
        @{ channel = "RAID0 IO percentage ($systemName)"; value = [math]::Round([double]$systemStats.raid0BytesPercent, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
        @{ channel = "RAID1 IO percentage ($systemName)"; value = [math]::Round([double]$systemStats.raid1BytesPercent, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
        @{ channel = "RAID5 IO percentage ($systemName)"; value = [math]::Round([double]$systemStats.raid5BytesPercent, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
        @{ channel = "RAID6 IO percentage ($systemName)"; value = [math]::Round([double]$systemStats.raid6BytesPercent, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
        @{ channel = "DDP IO percentage ($systemName)"; value = [math]::Round([double]$systemStats.ddpBytesPercent, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
        @{ channel = "Read hit response time ($systemName)"; value = [math]::Round([double]$systemStats.readHitResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
        @{ channel = "Write hit response time ($systemName)"; value = [math]::Round([double]$systemStats.writeHitResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
        @{ channel = "Drive count ($systemName)"; value = [int]$systemInfo.driveCount; unit = 'Count'; float = 0; DecimalMode = 0 },
        @{ channel = "Used pool space ($systemName)"; value = [int64]$systemInfo.usedPoolSpace; unit = 'BytesDisk'; customunit = 'TB'; float = 0; DecimalMode = 0 },
        @{ channel = "Unconfigured space ($systemName)"; value = [int64]$systemInfo.unconfiguredSpace; unit = 'BytesDisk'; customunit = 'TB'; float = 0; DecimalMode = 0 },
        @{ channel = "Free pool space ($systemName)"; value = [int64]$systemInfo.freePoolSpace; unit = 'BytesDisk'; customunit = 'TB'; float = 0; DecimalMode = 0 },
        @{ channel = "Hot spare count in standby ($systemName)"; value = [int]$systemInfo.hotSpareCountInStandby; unit = 'Count'; float = 0; DecimalMode = 0 }
    )
}

function Get-VolumeResults {
    if ([string]::IsNullOrWhiteSpace($Vol)) {
        throw 'Volume mode requires -Vol.'
    }

    $volumeStats = @(Invoke-SanGet -Path '/analysed-volume-statistics')
    $filteredStats = @($volumeStats | Where-Object { $_.volumeName -eq $Vol })
    if ($filteredStats.Count -eq 0) {
        throw "Volume '$Vol' was not found in analysed-volume-statistics"
    }

    $results = @()
    foreach ($volumeStat in $filteredStats) {
        $volumeName = $volumeStat.volumeName
        $results += @(
            @{ channel = "Read IOps ($volumeName)"; value = [math]::Round([double]$volumeStat.readIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
            @{ channel = "Write IOps ($volumeName)"; value = [math]::Round([double]$volumeStat.writeIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
            @{ channel = "Other IOps ($volumeName)"; value = [math]::Round([double]$volumeStat.otherIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
            @{ channel = "Combined IOps ($volumeName)"; value = [math]::Round([double]$volumeStat.combinedIOps, 2); unit = 'Custom'; customunit = 'IO/s'; float = 1; DecimalMode = 1 },
            @{ channel = "Read throughput ($volumeName)"; value = [math]::Round([double]$volumeStat.readThroughput, 2); unit = 'Custom'; customunit = 'MB/s'; float = 1; DecimalMode = 1 },
            @{ channel = "Write throughput ($volumeName)"; value = [math]::Round([double]$volumeStat.writeThroughput, 2); unit = 'Custom'; customunit = 'MB/s'; float = 1; DecimalMode = 1 },
            @{ channel = "Combined throughput ($volumeName)"; value = [math]::Round([double]$volumeStat.combinedThroughput, 2); unit = 'Custom'; customunit = 'MB/s'; float = 1; DecimalMode = 1 },
            @{ channel = "Read response time ($volumeName)"; value = [math]::Round([double]$volumeStat.readResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
            @{ channel = "Write response time ($volumeName)"; value = [math]::Round([double]$volumeStat.writeResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
            @{ channel = "Combined response time ($volumeName)"; value = [math]::Round([double]$volumeStat.combinedResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
            @{ channel = "Read response time variation ($volumeName)"; value = [math]::Round([double]$volumeStat.readResponseTimeStdDev, 2); unit = 'Custom'; customunit = 'StdDev'; float = 1; DecimalMode = 1; ShowChart = 0 },
            @{ channel = "Write response time variation ($volumeName)"; value = [math]::Round([double]$volumeStat.writeResponseTimeStdDev, 2); unit = 'Custom'; customunit = 'StdDev'; float = 1; DecimalMode = 1; ShowChart = 0 },
            @{ channel = "Combined response time variation ($volumeName)"; value = [math]::Round([double]$volumeStat.combinedResponseTimeStdDev, 2); unit = 'Custom'; customunit = 'StdDev'; float = 1; DecimalMode = 1; ShowChart = 0 },
            @{ channel = "Read hit response time ($volumeName)"; value = [math]::Round([double]$volumeStat.readHitResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
            @{ channel = "Write hit response time ($volumeName)"; value = [math]::Round([double]$volumeStat.writeHitResponseTime, 2); unit = 'Custom'; customunit = 'ms'; float = 1; DecimalMode = 1 },
            @{ channel = "Average read operation size ($volumeName)"; value = [math]::Round([double]$volumeStat.averageReadOpSize, 2); unit = 'Custom'; customunit = 'bytes'; float = 1; DecimalMode = 1 },
            @{ channel = "Full stripe writes percentage ($volumeName)"; value = [math]::Round([double]$volumeStat.fullStripeWritesBytesPercent, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 },
            @{ channel = "Flash cache hit percent ($volumeName)"; value = [math]::Round([double]$volumeStat.flashCacheHitPct, 2); unit = 'Custom'; customunit = '%'; float = 1; DecimalMode = 1 }
        )
    }

    $results
}

function Get-PoolResults {
    if ([string]::IsNullOrWhiteSpace($Pool)) {
        throw 'Pool mode requires -Pool.'
    }

    $pools = @(Invoke-SanGet -Path '/storage-pools')
    $poolInfo = @($pools | Where-Object { $_.name -eq $Pool }) | Select-Object -First 1
    if ($null -eq $poolInfo) {
        throw "Pool '$Pool' was not found in SANtricity storage-pools"
    }

    $r6UsableCapacity = 0
    $r1UsableCapacity = 0
    foreach ($raidDetail in @($poolInfo.extents.ddpRAIDCapacities)) {
        if ($raidDetail.ddpVolRAIDLevel -eq 'raid6') {
            $r6UsableCapacity = [int64]$raidDetail.usableCapacity
        }
        elseif ($raidDetail.ddpVolRAIDLevel -eq 'raid1') {
            $r1UsableCapacity = [int64]$raidDetail.usableCapacity
        }
    }

    @(
        @{ channel = "Reserve disk count for reconstruction ($Pool)"; value = [int]$poolInfo.volumeGroupData.diskPoolData.reconstructionReservedDriveCount; unit = 'Custom'; customunit = 'disk'; float = 0; DecimalMode = 0 },
        @{ channel = "Allocation granularity on pool level ($Pool)"; value = [int64]$poolInfo.volumeGroupData.diskPoolData.allocGranularity; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Minimum drive count ($Pool)"; value = [int]$poolInfo.volumeGroupData.diskPoolData.minimumDriveCount; unit = 'Custom'; customunit = 'disk'; float = 0; DecimalMode = 0 },
        @{ channel = "Disk sector size recommended ($Pool)"; value = [int]$poolInfo.blkSizeRecommended; unit = 'Custom'; customunit = 'bytes'; float = 0; DecimalMode = 0 },
        @{ channel = "Used space ($Pool)"; value = [int64]$poolInfo.usedSpace; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Total RAID space ($Pool)"; value = [int64]$poolInfo.totalRaidedSpace; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Total extent capacity (R6) ($Pool)"; value = $r6UsableCapacity; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Total extent capacity (R1) ($Pool)"; value = $r1UsableCapacity; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Largest free extent size ($Pool)"; value = [int64]$poolInfo.largestFreeExtentSize; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Free space ($Pool)"; value = [int64]$poolInfo.freeSpace; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 }
    )
}

function Get-SnapRepoResults {
    $systemInfo = Invoke-SanGet -Path "/storage-systems/$SanSysId" -UseSystemScope:$false
    $systemName = Get-ObjectName -InputObject $systemInfo -PropertyNames @('name', 'storageSystemName')

    $snapshotGroups = @(Invoke-SanGet -Path '/snapshot-groups')
    $cloneRepoUtilization = @(Invoke-SanGet -Path '/snapshot-volumes/repository-utilization')
    $volumes = @(Invoke-SanGet -Path '/volumes')

    $snapRepoCap = [int64](($snapshotGroups.repositoryCapacity | Measure-Object -Sum).Sum)
    $cloneRepoUsed = [int64](($cloneRepoUtilization.viewBytesUsed | Measure-Object -Sum).Sum)
    $cloneRepoAvailable = [int64](($cloneRepoUtilization.viewBytesAvailable | Measure-Object -Sum).Sum)
    $cloneRepoCap = $cloneRepoUsed + $cloneRepoAvailable
    $repoVolumeList = @($volumes | Where-Object { $_.name -match '\brepos_[0-9][0-9][0-9][0-9]\b' -and $_.volumeUse -eq 'concatVolume' })
    $repoCap = [int64](($repoVolumeList.totalSizeInBytes | Measure-Object -Sum).Sum)

    @(
        @{ channel = "Snap and clone repo capacity ($systemName)"; value = $repoCap; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Clone repo capacity ($systemName)"; value = $cloneRepoCap; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 },
        @{ channel = "Snap repo capacity ($systemName)"; value = $snapRepoCap; unit = 'BytesDisk'; VolumeSize = 'Giga'; float = 0; DecimalMode = 0 }
    )
}

function Get-CGResults {
    if ([string]::IsNullOrWhiteSpace($CG)) {
        throw 'Consistency Group mode requires -CG.'
    }

    $volumes = @(Invoke-SanGet -Path '/volumes')
    $volumeStats = @(Invoke-SanGet -Path '/analysed-volume-statistics')
    $consistencyGroups = @(Invoke-SanGet -Path '/consistency-groups')
    $consistencyGroup = @($consistencyGroups | Where-Object { $_.name -eq $CG }) | Select-Object -First 1
    if ($null -eq $consistencyGroup) {
        throw "Consistency Group '$CG' was not found in SANtricity"
    }

    $consistencyGroupId = $consistencyGroup.id
    $cgSnapshotsUsed = @($consistencyGroup.uniqueSequenceNumber).Count
    $cgMemberVolumes = @(Invoke-SanGet -Path "/consistency-groups/$consistencyGroupId/member-volumes")
    $cgSnapshots = @(Invoke-SanGet -Path "/consistency-groups/$consistencyGroupId/snapshots")
    $systemSnapshotVolumes = @(Invoke-SanGet -Path '/snapshot-volumes')
    $snapshotSchedules = @(Invoke-SanGet -Path '/snapshot-schedules')

    if ($cgSnapshots.Count -lt 1) {
        $cgSnapshotGroupCount = 0
        $cgLatestSnapshotAgeHrs = 0
    }
    else {
        $cgSnapshotGroupCount = @($cgSnapshots | Select-Object -ExpandProperty pitTimestamp | Group-Object).Count
        $latestPitTimestamp = ($cgSnapshots | Sort-Object -Descending -Property viewTime | Select-Object -First 1).pitTimestamp
        $cgLatestSnapshotAgeHrs = Get-AgeHours -Timestamp $latestPitTimestamp
    }

    $cgSnapshotVolumes = @($systemSnapshotVolumes | Where-Object { $_.consistencyGroupId -eq $consistencyGroupId })
    $cgRepositoryUtilizationBytes = [int64](($cgSnapshotVolumes.repositoryCapacity | Measure-Object -Sum).Sum)
    $cgAutoDeleteLimit = [int]$consistencyGroup.autoDeleteLimit
    if ($cgAutoDeleteLimit -eq 0) {
        $cgSnapshotUnusedCount = 32 - $cgSnapshotGroupCount
    }
    else {
        $cgSnapshotUnusedCount = $cgAutoDeleteLimit - $cgSnapshotGroupCount
    }

    $cgVolumeIds = @($cgMemberVolumes.volumeId)
    $vCacheSettings = New-Object System.Collections.ArrayList
    $cgCapacity = 0
    foreach ($volume in $volumes) {
        if ($cgVolumeIds -contains $volume.id) {
            $cgCapacity += [int64]$volume.totalSizeInBytes
            [void]$vCacheSettings.Add($volume.cache)
        }
    }
    $vCacheSettingsCount = @($vCacheSettings | Get-Unique).Length

    $cgReadThroughput = 0
    $cgWriteThroughput = 0
    $cgReadIops = 0
    $cgWriteIops = 0
    foreach ($volumeStat in $volumeStats) {
        if ($cgVolumeIds -contains $volumeStat.volumeId) {
            $cgReadThroughput += [double]$volumeStat.readThroughput
            $cgWriteThroughput += [double]$volumeStat.writeThroughput
            $cgReadIops += [double]$volumeStat.readIOps
            $cgWriteIops += [double]$volumeStat.writeIOps
        }
    }

    $cloneName = @()
    $cloneSubOptimalCount = 0
    foreach ($clone in $systemSnapshotVolumes) {
        if ($clone.boundToPIT -eq $true -and $clone.consistencyGroupId -eq $consistencyGroupId -and $clone.status -eq 'optimal') {
            $cloneName += (($clone.name).Split(':')[0])
        }
        elseif ($clone.consistencyGroupId -eq $consistencyGroupId) {
            $cloneSubOptimalCount += 1
        }
    }
    $cgCloneCount = @($cloneName | Get-Unique).Count
    $cgCloneOptimalCount = $cgCloneCount - $cloneSubOptimalCount

    $mos = $cgSnapshotVolumes
    $mosRo = @($mos | Where-Object { $_.accessMode -eq 'readOnly' })
    $mosRw = @($mos | Where-Object { $_.accessMode -eq 'readWrite' })
    $mosRoCount = $mosRo.Count
    $mosRwCount = $mosRw.Count
    $cgSnapshotRwAgeHrs = if ($mosRwCount -eq 0) { 0 } else { Get-AgeHours -Timestamp (($mosRw | Sort-Object -Descending -Property viewTime | Select-Object -First 1).viewTime) }
    $cgSnapshotRoAgeHrs = if ($mosRoCount -eq 0) { 0 } else { Get-AgeHours -Timestamp (($mosRo | Sort-Object -Descending -Property viewTime | Select-Object -First 1).viewTime) }

    $cgActiveSnapshotSchedule = 0
    foreach ($schedule in $snapshotSchedules) {
        if ($schedule.targetObject -eq $consistencyGroupId -and $schedule.scheduleStatus -eq 'active') {
            $cgActiveSnapshotSchedule = 1
            break
        }
    }

    @(
        @{ channel = "Member volumes ($CG)"; value = $cgMemberVolumes.Count; unit = 'Count'; float = 0 },
        @{ channel = "Read throughput ($CG)"; value = $cgReadThroughput; unit = 'Custom'; CustomUnit = 'MB/s'; float = 1 },
        @{ channel = "Write throughput ($CG)"; value = $cgWriteThroughput; unit = 'Custom'; CustomUnit = 'MB/s'; float = 1 },
        @{ channel = "Read IOPS ($CG)"; value = $cgReadIops; unit = 'Custom'; CustomUnit = 'IOPS'; float = 1 },
        @{ channel = "Write IOPS ($CG)"; value = $cgWriteIops; unit = 'Custom'; CustomUnit = 'IOPS'; float = 1 },
        @{ channel = "Clone repo capacity used ($CG)"; value = $cgRepositoryUtilizationBytes; unit = 'BytesDisk'; customunit = 'Byte'; SpeedSize = 'GigaByte'; float = 0; DecimalMode = 0 },
        @{ channel = "RO clone volumes ($CG)"; value = $mosRoCount; unit = 'Count'; float = 0 },
        @{ channel = "RW clone volumes ($CG)"; value = $mosRwCount; unit = 'Count'; float = 0 },
        @{ channel = "Volume clones ($CG)"; value = ($mosRwCount + $mosRoCount); unit = 'Count'; float = 0 },
        @{ channel = "Clone sets ($CG)"; value = $cgCloneCount; unit = 'Count'; float = 0 },
        @{ channel = "Clone sets in optimal state ($CG)"; value = $cgCloneOptimalCount; unit = 'Count'; float = 0 },
        @{ channel = "Snapshot limit ($CG)"; value = $cgAutoDeleteLimit; unit = 'Count'; float = 0 },
        @{ channel = "Snapshots used ($CG)"; value = $cgSnapshotsUsed; unit = 'Count'; float = 0 },
        @{ channel = "Snapshots available ($CG)"; value = $cgSnapshotUnusedCount; unit = 'Count'; float = 0 },
        @{ channel = "Unique cache settings ($CG)"; value = $vCacheSettingsCount; unit = 'Count'; float = 0 },
        @{ channel = "Age of newest snapshot ($CG)"; value = $cgLatestSnapshotAgeHrs; unit = 'Count'; CustomUnit = 'hrs'; float = 1; DecimalMode = 1 },
        @{ channel = "Age of newest RO clone ($CG)"; value = $cgSnapshotRoAgeHrs; unit = 'Count'; CustomUnit = 'hrs'; float = 1; DecimalMode = 1 },
        @{ channel = "Age of newest RW clone ($CG)"; value = $cgSnapshotRwAgeHrs; unit = 'Count'; CustomUnit = 'hrs'; float = 1; DecimalMode = 1 },
        @{ channel = "Active snapshot schedule ($CG)"; value = $cgActiveSnapshotSchedule; unit = 'Count'; CustomUnit = 'hrs'; float = 1; DecimalMode = 1 },
        @{ channel = "Capacity ($CG)"; value = $cgCapacity; unit = 'BytesDisk'; customunit = 'Byte'; SpeedSize = 'GigaByte'; float = 0; DecimalMode = 0 }
    )
}

try {
    Import-SANtricityBackendModule -ModulePath $SantricityModulePath
    Connect-PrtgSantricity

    $result = switch ($Mode) {
        'system'   { Get-SystemResults }
        'volume'   { Get-VolumeResults }
        'pool'     { Get-PoolResults }
        'snaprepo' { Get-SnapRepoResults }
        'cg'       { Get-CGResults }
    }

    Write-Output (New-PrtgResultJson -Result $result)
    exit 0
}
catch {
    $message = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    Write-Output (New-PrtgErrorJson -Message $message)
    exit 1
}