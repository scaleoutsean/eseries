#!/usr/bin/env pwsh 

###########################################################################
# 
# Name: DdpCapacityDivider.ps1
# 
# Description: DDP Capacity Divider divides DDP among N equally sized volumes
# 
# Author: @scaleoutSean (https://github.com/scaleoutsean)
#
# Requirements: Microsoft PowerShell 5 or 7 (Windows, Linux, macOS)
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
  This script divides DDP capacity among N equally-sized volume in 4 GiB units.
.DESCRIPTION
  NetApp TR4652 describes how to divide DDP capacity among N equally-sized volumes.
  This script implements the formula described in TR4652.
.PARAMETER ddpCapacity
  DDP capacity in GiB
.PARAMETER numberOfVolumes
  Number of volume to equally divide DDP capacity among
.INPUTS
  None
.OUTPUTS 
  Output is the volume size in whole GiB
.NOTES
  Version:        1.0.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2023/10/02
  Change:         Initial release
.EXAMPLE
  ./DdpCapacityDivider.ps1 -ddpCapacity 161456 -numberOfVolumes 5
#>

#---------------------------------------------------------[Parameters and Declarations]------------------------------------

Param (
    [Parameter(
        Mandatory = $true,
        HelpMessage = 'DDP pool capacity in Gibibytes (GiB)')]
    [ValidateNotNullOrEmpty()]
    [int]$ddpCapacity,

    [Parameter(
        Mandatory = $true,
        HelpMessage = 'Number of volumes to divide DDP capacity among')]
    [ValidateNotNullOrEmpty()]
    [int]$numberOfVolumes

)

#---------------------------------------------------------[Constants]------------------------------------------------------
# D-stripe size is fixed, 4 GiB
$DStripeSize = 4 # GiB 

#---------------------------------------------------------[Functions]------------------------------------------------------

$DStripesPerPool = $ddpCapacity / $DStripeSize
Write-Host "D-stripes per pool:", $DStripesPerPool

# divide the number of D-stripes by the number of volumes to get the number of D-stripes per volume
[decimal]$DStripesPerVolume = $DStripesPerPool/$numberOfVolumes
Write-Host "D-stripes per volume:", $DStripesPerVolume

# round down D-stripes per volume to int GiB and multiply it by 4 GiB to get the volume size in GiB

$volumeSize = [math]::Floor($DStripesPerVolume)*4
Write-Host "Volume size in whole GiB based on rounded-down D-Stripes per  volume:", $volumeSize, "GiB"
