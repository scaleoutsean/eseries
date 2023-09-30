- [EXE/Script sensor for NetApp E-Series (SANtricity) v11.80 and PRTG v20-23](#exescript-sensor-for-netapp-e-series-santricity-v1180-and-prtg-v20-23)
  - [What does this script do](#what-does-this-script-do)
  - [How to use it](#how-to-use-it)
  - [Known shortcomings](#known-shortcomings)
  - [Metrics](#metrics)

# EXE/Script sensor for NetApp E-Series (SANtricity) v11.80 and PRTG v20-23

## What does this script do

This script makes one API call to the SANtricity API endpoint to get "analysed-system-statistics".

Then it takes most of the metrics and sends them to stdout (and PRTG, when PRTG runs it).

Some metrics I don't find useful are dropped. 

## How to use it

PRTG v20-23 still mandates PowerShell 5.1 (x86), so that's what you must have.

Copy the script to PRTG server:

![Script copied to PRTG server](/monitor/PRTG/prtg-script-on-server.png)

Create a JWT token and run the script from the CLI using your own parameters.

You can get SAN WWID from SANtricity or SNMP walk:
```raw
enterprises.789.1123.2.500.1.2.0 = STRING: "600a098000f63714000000005eaabbccc"
```

From PowerShell 5.1 (x86):

```pwsh
.\Get-ESeriesInfo.ps1 -ApiEp "192.168.1.0" `
    -SanSysId "600a098000f63714000000005e79c17c" -Token "33feq...dsA02"
```

If that works fine (JSON output shows some performance metrics), you can create this EXE/Script sensor and configure it as any other.

You may hard-code JWT into the script, or pass it from PRTG and CLI (`-Token`). 

Some other ideas can be found [here](https://scaleoutsean.github.io/2023/09/25/monitoring-netapp-eseries-with-prtg.html#security-in-shell-scripts).

## Known shortcomings

It would be better to be able to pass username/password instead of Token, but you may edit the script on your own to do that.

Originally the script was like that, but removed username/password in favor of tokens thinking it will be simpler better for security. 

However, due to a limitation in SANtricity 11.80 - JWT tokens can't be created for the monitor account - now the approach with tokens is not more secure, but is less convenient. 

Ideally we'd like to use JWT for the monitor account and if that's not possible, then username/password for the monitor account.

## Metrics

These metrics are currently sent to PRTG. 

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

Few other are dropped because I didn't find them useful. Check "analysed-system-metrics" in the SANtricity API to find out more.
