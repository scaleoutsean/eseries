- [EXE/Script sensors for NetApp E-Series (SANtricity OS) v11.80 and PRTG v20-23](#exescript-sensors-for-netapp-e-series-santricity-os-v1180-and-prtg-v20-23)
  - [What do these this script do](#what-do-these-this-script-do)
    - [Storage System](#storage-system)
    - [Volume](#volume)
    - [DDP](#ddp)
  - [How to use them](#how-to-use-them)
    - [Storage system sensor](#storage-system-sensor)
    - [Volume\* performance sensor](#volume-performance-sensor)
  - [Known issues and workarounds](#known-issues-and-workarounds)
    - [Encryption](#encryption)
    - [Authentication and credentials](#authentication-and-credentials)
    - [Accuracy](#accuracy)
  - [Metrics](#metrics)
  - [Additional information](#additional-information)
  - [Change log](#change-log)

# EXE/Script sensors for NetApp E-Series (SANtricity OS) v11.80 and PRTG v20-23

## What do these this script do

### Storage System (Get-ESeriesInfo.ps1)

This script makes one API call to the SANtricity API endpoint to get "analysed-system-statistics".

Then it takes most of the metrics and sends them to stdout (and PRTG, when PRTG runs it).

Some metrics I don't find useful are dropped. 

### Volume (Get-ESeriesVolumeInfo.ps1)

This script makes one API call to the SANtricity API endpoint to get "analysed-system-statistics".

Then it takes most of the metrics and sends them to stdout (and PRTG, when PRTG runs it).

It closely reflects metrics from Storage System sensor. Some metrics I don't find useful are dropped. 

### DDP

TODO

## How to use them

EXE/Script sensors in PRTG v20-23 still mandates PowerShell 5.1 (x86), so that's what you must have.

Copy the script(s) to PRTG server's sub-sub-directory for EXEXML sensors:

![Script copied to PRTG server](/monitor/PRTG/prtg-script-on-server.png)

You can get SAN WWID from SANtricity or an SNMP walk, although any WWID will work since it's not required for correct functioning of the script (it's there to make such enforcement potentially possible, but neither SANtricity nor sensor scripts do any checks at this time).

- In SANtricity 11.80 go to Settings > System > iSCSI/iSER over InfiniBand settings > Target IQN: `iqn.1992-08.com.netapp:5700.**600a098000f63714000000005eaaabbb**`
- Using SNMP walk output:

```raw
enterprises.789.1123.2.500.1.2.0 = STRING: "600a098000f63714000000005eaaabbb"
```

### Storage system sensor 

This script can be executed from PowerShell 5.1 (x86) like so:

```pwsh
.\Get-ESeriesInfo.ps1 -ApiEp "192.168.1.0" -ApiPort "8443" `
  -SanSysId "600a098000f63714000000005e79c17c" -Account "monitor" -Password "monitor$123"
```

If that works fine (JSON output shows some performance metrics), you can create this EXE/Script sensor and configure it as any other.

From PRTG pass parameters on like this, escaping special characters (`\$`) where necessary: `-ApiEp "192.168.1.0" -ApiPort "8443" -SanSysId "600a098000f63714000000005eaaabbb" -User "monitor" -Password "monitor\$123"`.

### Volume* performance sensor

This script can be used for more than one volume; just create multiple sensors and make them all use the same script. Then name each sensor differently and pass the unique SANtricity volume name in sensor's parameters field.

Example: `-ApiEp "192.168.1.0" -ApiPort "8443" -SanSysId "600a098000f63714000000005eaaabbb" -User "monitor" -Password "monitor\$123" -Vol "pgsql"`

![Configuring SANtricity volume sensor](/monitor/PRTG/prtg-script-sensor-parameters.png)

It is suggested to monitor just a handful of critical volumes in PRTG and use dedicated performance monitoring solution for more advanced scenarios.

## Known issues and workarounds 

There are too many possible combination of various settings, environments, preferences and approaches. 

Rather than try to write a 2000 line script that works in 95% of circumstances, I took an opinionated approach with some seemingly reasonable compromises. 

(I don't even use PRTG or these scripts - all this is purely meant to help E-Series owners who use PRTG.)

### Encryption

The script has no switch to ignore self-signed TLS certificates; they are ignored by default. 

If you use valid TLS certificates that PRTG systems running sensors can recognize, remove the section of sensor code that ignore self-signed TLS certificates.

### Authentication and credentials

By default these scripts requires that SANtricity credentials be passed to sensor as variables. Alternatively you may hard-code them in to the script.

Ideally we'd like to use JWT for the SANtricity monitor account. But we cannot due to a limitation in SANtricity 11.80 (JWT tokens can't be created for the monitor account because that account isn't a security admin that may create credentials), so it is a compromise to use a low-privileged account/password.

Beware that if you enable logging, all parameter passed onto these sensor scripts will be logged. Disable logging or come up with a better approach if this isn't acceptable.

![Logged username and password in PRTG sensor log](/monitor/PRTG/prtg-script-log-if-enabled.png)

### Accuracy

As the API methods' names say, these metrics are analyzed, i.e. pre-processed by SANtricity OS on E-Series. That can be noticed when IO metrics remain stuck at 0 even after a workload has been initiated on an idle system.

SANtricity needs some time to get several samples in order to create *analyzed* metrics.

As the exact way that analysis and processing are done is not documented, we can't know how correct they are. Generally they seem to flatten spikes, so they're "roughly" correct or "advisory".

SANtricity has other API calls that can gather live statistics over a period such as 10 seconds, but if metrics are gathered once every 5 minutes averaged metrics will likely be more accurate than one random sample for a 10 second from the same period. This is why I find analyzed metrics acceptable despite their not necessarily being accurate at any point in time. 

## Metrics

These *system* metrics are currently sent to PRTG. 

- Average CPU utilization 
- Maximum CPU utilization 
- Read IOps 
- Write IOps 
- Other IOps 
- Combined IOps 
- Read throughput 
- Write throughput 
- Combined throughput 
- Read response time 
- Write response time 
- Combined response time 
- Read response time variation 
- Write response time variation 
- Combined response time variation 
- Cache hit rate 
- RAID0 IO percentage 
- RAID1 IO percentage 
- RAID5 IO percentage 
- RAID6 IO percentage 
- DDP IO percentage 
- Read hit response time 
- Write hit response time 

A few other were dropped because I didn't find them useful. Check "analysed-system-statistics" in the SANtricity API to find out more.

*Volume* metrics follow the same pattern and largely match analyzed system metrics included above. There's no average CPU utilization for volumes, that's true, but as long as a matching metric is available in selected "analysed-volume-statistics", it is also included in this sensor's output.

## Additional information

Some related information can be found [here](https://scaleoutsean.github.io/2023/09/25/monitoring-netapp-eseries-with-prtg.html#security-in-shell-scripts).

## Change log

- 2023/10/01
  - Get-ESeriesInfo.ps1 - 1.1.0 release with username/password authentication
  - Get-ESeriesVolumeInfo.ps1 - initial 1.0.0 release with username/password authentication
- 2023/09/29
  - Get-ESeriesInfo.ps1 - initial 1.0.0 release with JWT authentication
