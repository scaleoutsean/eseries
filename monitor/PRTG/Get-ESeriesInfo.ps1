#!/usr/bin/env pwsh

###########################################################################
# 
# Name: Get-ESeriesInfo.ps1
# 
# Description: EXE/Script sensor for NetApp E-Series v11 & PRTG v20-23
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
  Gets useful metrics from SANtricity's "analysed-system-statistics" method and sends them as JSON to PRTG.
.DESCRIPTION
  Script requires just one controller because it gets the metrics from the entire system.
  It uses port 8443/TCP to access the SANtriity API.
  Configure ping or HTTPS probe for the controllers to detect a failed controller.
  Long-lived JWT token can be hardcoded in the script or passed from PRTG. Short-lived Beaerer Token may be passed from PRTG.
.PARAMETER ApiEp
  SANtricity API endpoint in IPv4 format. Examples: "8.4.4.3". Default: none
.PARAMETER SanSysId
  SANtricity System ID. Example: "600A098000F63714000000005E79C17C". Default: "600A098000F63714000000005E79C17C"
.PARAMETER Token
  Short-lived Bearer token for any SANtricity account, or long-lived JWT token for an admin account. Default: none
.INPUTS
  None
.OUTPUTS 
  Stdout (JSON) for PRTG EXE/Script sensor
.NOTES
  Version:        1.0.0
  Author:         scaleoutSean (https://github.com/scaleoutsean)
  Creation Date:  2023/09/30
  Change:         Initial release
.EXAMPLE
  .\Get-ESeriesInfo.ps1 -ApiEp "192.168.1.0" `
    -SanSysId "600a098000f63714000000005e79c17c" -Token "33feq...dsA02"
#>

#---------------------------------------------------------[Parameters and Declarations]------------------------------------------------------

Param (
    [Parameter(
        Mandatory = $true,
        HelpMessage = 'SANtricity API endpoint (Controller IP) as IPv4 addresses. Example: "8.4.4.3"')]
    [ValidateNotNullOrEmpty()]
    [array]$ApiEp,

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'SANtricity System ID (World-Wide Name). Example: "600A098000F63714000021115E79C17C"')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(32, 32)]
    [string]$SanSysId = '600A098000F63714000021115E79C17C',

    [Parameter(
        Mandatory = $false,
        HelpMessage = 'Bearer Token for SANtricity account')]
    [ValidateNotNullOrEmpty()]
    [string]$Token
)

$ErrorActionPreference = 'SilentlyContinue'

$Global:headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
$headers.Add('Accept', 'application/json')
$headers.Add('Content-Type', 'application/json')
$headers.Add('Authorization', "Bearer $Token")

# SO - this section is to ignore self-signed TLS certificate if you have one
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

#---------------------------------------------------------[Functions]------------------------------------------------------

# Function to return subsystem statistics for a controller 
Function SantricityGetMetrics {
    Param (
        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ControllerIp,

        [Parameter(
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ESeriesWwid,
        
        [Parameter(
            Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SubSystem = 'system'
    )
       
    Try {
        $ApiEpUri = "https://" + $ControllerIp + ":8443/devmgr/v2/storage-systems/" + $ESeriesWwid + "/analysed-" + $SubSystem + "-statistics"
        $response = Invoke-RestMethod -Uri $ApiEpUri -Method 'GET' -Headers $headers
        return($response)
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

# https://www.paessler.com/manuals/prtg/custom_sensors#advanced_sensors

$response = SantricityGetMetrics -ControllerIp $ApiEp[0] -ESeriesWwid $SanSysId -SubSystem "system"
$SystemName = $response.storageSystemName

@{
    "prtg" = @{
        "result" = @(
            @{
                "channel"     = "Average CPU utilization ($SystemName)";
                "value"       = [math]::round(($response.cpuAvgUtilization), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Maximum CPU utilization ($SystemName)";
                "value"       = [math]::round(($response.maxCpuUtilization), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1;
                "ShowChart"   = 0
                        
            };
            @{
                "channel"     = "Read IOps ($SystemName)";
                "value"       = [math]::round(($response.readIOps), 2);
                "unit"        = "Custom";
                "customunit"  = "IO/s";
                "float"       = 1;
                "DecimalMode" = 1
                        
            };
            @{
                "channel"     = "Write IOps ($SystemName)";
                "value"       = [math]::round(($response.writeIOps), 2);
                "unit"        = "Custom";
                "customunit"  = "IO/s";
                "float"       = 1;
                "DecimalMode" = 1
                        
            };
            @{
                "channel"     = "Other IOps ($SystemName)";
                "value"       = [math]::round(($response.otherIOps), 2);
                "unit"        = "Custom";
                "customunit"  = "IO/s";
                "float"       = 1;
                "DecimalMode" = 1
                        
            };
            @{
                "channel"     = "Combined IOps ($SystemName)";
                "value"       = [math]::round(($response.combinedIOps), 2);
                "unit"        = "Custom";
                "customunit"  = "IO/s";
                "float"       = 1;
                "DecimalMode" = 1
                        
            };
            @{
                "channel"     = "Read throughput ($SystemName)";
                "value"       = [math]::round(($response.readThroughput), 2);
                "unit"        = "Custom";
                "customunit"  = "MB/s";
                "float"       = 1;
                "DecimalMode" = 1
                        
            };
            @{
                "channel"     = "Write throughput ($SystemName)";
                "value"       = [math]::round(($response.writeThroughput), 2);
                "unit"        = "Custom";
                "customunit"  = "MB/s";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Combined throughput ($SystemName)";
                "value"       = [math]::round(($response.combinedThroughput), 2);
                "unit"        = "Custom";
                "customunit"  = "MB/s";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Read response time ($SystemName)";
                "value"       = [math]::round(($response.readResponseTime), 2);
                "unit"        = "Custom";
                "customunit"  = "ms";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Write response time ($SystemName)";
                "value"       = [math]::round(($response.writeResponseTime), 2);
                "unit"        = "Custom";
                "customunit"  = "ms";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Combined response time ($SystemName)";
                "value"       = [math]::round(($response.combinedResponseTime), 2);
                "unit"        = "Custom";
                "customunit"  = "ms";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Read response time variation ($SystemName)";
                "value"       = [math]::round(($response.readResponseTimeStdDev), 2);
                "unit"        = "Custom";
                "customunit"  = "StdDev";
                "float"       = 1;
                "DecimalMode" = 1;
                "ShowChart"   = 0
            };
            @{
                "channel"     = "Write response time variation ($SystemName)";
                "value"       = [math]::round(($response.writeResponseTimeStdDev), 2);
                "unit"        = "Custom";
                "customunit"  = "StdDev";
                "float"       = 1;
                "DecimalMode" = 1;
                "ShowChart"   = 0
            };
            @{
                "channel"     = "Combined response time variation ($SystemName)";
                "value"       = [math]::round(($response.combinedResponseTimeStdDev), 2);
                "unit"        = "Custom";
                "customunit"  = "StdDev";
                "float"       = 1;
                "DecimalMode" = 1;
                "ShowChart"   = 0
            };
            @{
                "channel"     = "Cache hit rate ($SystemName)";
                "value"       = [math]::round(($response.cacheHitBytesPercent), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "RAID0 IO percentage ($SystemName)";
                "value"       = [math]::round(($response.raid0BytesPercent), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "RAID1 IO percentage ($SystemName)";
                "value"       = [math]::round(($response.raid1BytesPercent), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "RAID5 IO percentage ($SystemName)";
                "value"       = [math]::round(($response.raid5BytesPercent), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "RAID6 IO percentage ($SystemName)";
                "value"       = [math]::round(($response.raid6BytesPercent), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "DDP IO percentage ($SystemName)";
                "value"       = [math]::round(($response.ddpBytesPercent), 2);
                "unit"        = "Custom";
                "customunit"  = "%";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Read hit response time ($SystemName)";
                "value"       = [math]::round(($response.readHitResponseTime), 2);
                "unit"        = "Custom";
                "customunit"  = "ms";
                "float"       = 1;
                "DecimalMode" = 1
            };
            @{
                "channel"     = "Write hit response time ($SystemName)";
                "value"       = [math]::round(($response.writeHitResponseTime), 2);
                "unit"        = "Custom";
                "customunit"  = "ms";
                "float"       = 1;
                "DecimalMode" = 1
            }
        ) 
    }
} | ConvertTo-Json -Depth 3

