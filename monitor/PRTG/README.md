- [EXE/Script sensors for NetApp E-Series (SANtricity OS) v11.80 and PRTG v20-23](#exescript-sensors-for-netapp-e-series-santricity-os-v1180-and-prtg-v20-23)
  - [What do these this script do](#what-do-these-this-script-do)
    - [Storage System (Get-ESeriesInfo.ps1)](#storage-system-get-eseriesinfops1)
    - [Volume (Get-ESeriesVolumeInfo.ps1)](#volume-get-eseriesvolumeinfops1)
    - [Pool (Get-ESeriesPoolInfo.ps1)](#pool-get-eseriespoolinfops1)
    - [Snapshot, clone and repository (Get-ESeriesSnapCloneRepoInfo.ps1)](#snapshot-clone-and-repository-get-eseriessnapclonerepoinfops1)
    - [Snapshot Consistency Group (Get-ESeriesCGInfo.ps1)](#snapshot-consistency-group-get-eseriescginfops1)
  - [How to use senor scripts](#how-to-use-senor-scripts)
    - [Storage system sensor](#storage-system-sensor)
    - [Volume\* performance sensor](#volume-performance-sensor)
    - [Pool sensor](#pool-sensor)
    - [Snapshot/Clone/Repo sensor](#snapshotclonerepo-sensor)
    - [Snapshot Consistency Group sensor](#snapshot-consistency-group-sensor)
  - [Known issues and workarounds](#known-issues-and-workarounds)
    - [Encryption](#encryption)
    - [Authentication and credentials](#authentication-and-credentials)
    - [Change in SANtricity storage object names require recreation of sensors that monitor by name](#change-in-santricity-storage-object-names-require-recreation-of-sensors-that-monitor-by-name)
    - [Accuracy of performance metrics](#accuracy-of-performance-metrics)
    - [Accuracy of capacity metrics](#accuracy-of-capacity-metrics)
    - [DDP resilience is different from volume resilience](#ddp-resilience-is-different-from-volume-resilience)
    - [Performance aggregates in Snapshot Consistency Group sensor](#performance-aggregates-in-snapshot-consistency-group-sensor)
  - [Metrics](#metrics)
    - [System and Volumes](#system-and-volumes)
    - [Pool](#pool)
    - [Snapshots, clones and reserve space](#snapshots-clones-and-reserve-space)
    - [Snapshot Consistency Group](#snapshot-consistency-group)
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

### Pool (Get-ESeriesPoolInfo.ps1)

Volumes on regular RAID disk groups usually consume the entire volume. There's no storage savings (compression, deduplication) or thin provisioning, so it's easy to reason about these.

DDP, on the other hand, can accommodate volumes with heterogeneous RAID levels (RAID-1 and RAID-6, in SANtricity 11.80), so being able to see the capacity used by each, as well as other less obvious metrics without much clicking around is useful. Additionally, in SAS-based E- and EF-Series arrays, thin provisioning is possible, making this sensor even more useful. (EF300 and EF600 are NVMe-based.)

### Snapshot, clone and repository (Get-ESeriesSnapCloneRepoInfo.ps1)

Primarily for space consumption (in repository volumes) by snapshots and writable clones.

### Snapshot Consistency Group (Get-ESeriesCGInfo.ps1)

Watches specific (snapshot) Consistency Group. 

The purpose of this sensor is not just to watch snapshots and clones, but also aggregate CG capacity, reserve volume utilization, and performance for the CG of interest.

The main use case for this is monitoring of symmetric scale-out workloads such as NOSQL databases, Kafka or MinIO.

## How to use senor scripts

EXE/Script sensors in PRTG v20-23 still mandates PowerShell 5.1 (x86), so that's what you must have.

Copy the script(s) to PRTG server's sub-sub-directory for EXEXML sensors:

![Script copied to PRTG server](/monitor/PRTG/prtg-script-on-server.png)

You can get SAN WWID from SANtricity or an SNMP walk, although any WWID will work since it's not required for correct functioning of the script (it's there to make such enforcement potentially possible, but neither SANtricity nor sensor scripts do any checks at this time).

- In SANtricity 11.80 go to Settings > System > iSCSI/iSER over InfiniBand settings > Target IQN: `iqn.1992-08.com.netapp:5700.600a098000f63714000000005eaaabbb`
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

### Pool sensor

Several pool sensors can share this script. Just specify a different `Pool` in the parameters of each sensor.

Example: `-ApiEp "192.168.1.0" -ApiPort "8443" -SanSysId "600a098000f63714000000005eaaabbb" -User "monitor" -Password "monitor123" -Pool "bigdata"`

### Snapshot/Clone/Repo sensor

This sensor is very simple. It's there to get people started. Users are encouraged to improve it and submit pull requests.

Several arrays share this sensor script. Just specify different parameters.

Example: `-ApiEp "192.168.1.0" -ApiPort "8443" -SanSysId "600a098000f63714000000005eaaabbb" -User "monitor" -Password "monitor123"`

This sensor gives limited metrics on purpose.

SANtricity has built-in alerts for snapshot and clone ("snapshot volume", as it's called) fullness, so it makes no sense to alert twice: you may configure SNMP Walk (for "Need Attention" indicator) or SNMP Trap Receiver sensor and receive alerts from E-Series in PRTG.

### Snapshot Consistency Group sensor

Just specify the CG with `-CG`:

```pwsh
.\Get-ESeriesCGInfo.ps1 -ApiEp "192.168.1.0" -ApiPort "8443" `
    -SanSysId "600a098000f63714000000005e79c17c" -Account "monitor" -Password "monitor123" `
    -CG "CG_ELK"
```

PRTG example: `-ApiEp "192.168.1.0" -ApiPort "8443" -SanSysId "600a098000f63714000000005eaaabbb" -User "monitor" -Password "monitor123" -CG "CG_ELK"`

Use multiple sensors for multiple CGs.

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

### Change in SANtricity storage object names require recreation of sensors that monitor by name

This was observed with pools, but probably applies to other sensors that monitor named objects: if a pool is renamed in SANtricity, the sensor that watches it fails and goes down.

Furthermore, simply pausing the sensor, changing the parameter value, and restarting the sensor does not help.

You need to delete the sensor and re-create it using the new parameter value. This doesn't seem to affect sensors that don't use names in parameter values. This looks like "PRTG behavior by design", so don't randomly rename pools, volumes and such without considering the possibility of causing alerts in PRTG.

### Accuracy of performance metrics

As the API methods' names say, these metrics are analyzed, i.e. pre-processed by SANtricity OS on E-Series. That can be noticed when IO metrics remain stuck at 0 even after a workload has been initiated on an idle system.

SANtricity needs some time to get several samples in order to create *analyzed* metrics.

As the exact way that analysis and processing are done is not documented, we can't know how correct they are. Generally they seem to flatten spikes, so they're "roughly" correct or "advisory".

SANtricity has other API calls that can gather live statistics over a period such as 10 seconds, but if metrics are gathered once every 5 minutes averaged metrics will likely be more accurate than one random sample for a 10 second from the same period. This is why I find analyzed metrics acceptable despite their not necessarily being accurate at any point in time. 

### Accuracy of capacity metrics

Certain metrics may be off by a small(ish) amount because they were received as such.

Sometimes an "orphaned" repo volume may be not showing in SANtricity Web UI, but it's being accounted for in the API and Snap/Clone/Repo sensor. Normally SANtricity should alert you and ask you to reclaim unused space (i.e. delete the orphaned repo file(s)), but until you do a discrepancy between SANtricity Web UI and Snap/Clone/Repo sensor will exist. 

I came across this problem with an orphaned repo that I could not delete, so I "solved" it by excluding it from the total repo capacity calculation just to be able to visually verify sensor output vs. SANtricity Web UI. But the posted senor now includes capacity from all repository volumes. If you see a discrepancy due to orphaned repository volumes, contact NetApp Support to reclaimed orphaned repository volumes.

Of course, there may be other reasons such as conversion or other bugs in sensor code as well.

### DDP resilience is different from volume resilience

This DDP sensor may how "Reserve risk count for reconstruction" of 2 or more, and that applies to the pool. Just don't mistake that for concurrent disk loss tolerance of DDP RAID1 volumes.

A DDP may lose one two drives at the same time without failing catastrophically. DDP-based RAID 6 volumes behave the same way, but RAID 1 volumes do not.

Two simultaneously failed disks in a DDP pool with RAID 1-style volumes will cause RAID 1 volume data loss, while leaving RAID 6 volumes and DDP itself whole.

See the [NetApp TR-4652](https://www.netapp.com/media/12421-tr4652.pdf) for more on DDP.

### Performance aggregates in Snapshot Consistency Group sensor

As mentioned above, aggregate performance metrics use "analyzed" volume performance metrics which are averages obtained from the constituent volumes, which means they're (a) delayed and take time to react, and (b) they show average values. 

The numbers seem accurately computed - as far as I can tell - by adding averages from the member volumes, but if there's server-side caching or workload isn't constant, it may be difficult to to reconcile server- and client-side figures.

The SANtricity API has volume performance metrics, but those point-in-time numbers would also be difficult to use because each sample taken every 5 minutes could range from 0 to the controller maximum.

## Metrics

### System and Volumes

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
- Drive count (system only)
- Used pool space (system only)
- Unconfigured space (system only)
- Free pool pace (system only)
- Hot spare count in standby (system only)

A few other were dropped because I didn't find them useful. Check "analysed-system-statistics" in the SANtricity API to find out more.

*Volume* metrics follow the same pattern and largely match analyzed system metrics included above. There's no average CPU utilization for volumes, that's true, but as long as a matching metric is available in selected "analysed-volume-statistics", it is also included in this sensor's output.

### Pool

- Reserve disk count for reconstruction 
- Allocation granularity on pool level 
- Minimum drive count 
- Disk sector size recommended 
- Used space 
- Total RAID space 
- Total extent capacity (R6) 
- Total extent capacity (R1) 
- Largest free extent size 
- Free space

### Snapshots, clones and reserve space

As explained earlier these indicators exist merely to show you how much capacity (GiB) is being used by these features. Think of it is as a cost indicator of snapshot and clone usage.

- Total snapshot reserve space
- Total clone (aka "snapshot volume") reserve space
- Total snapshot and clone reserve space

### Snapshot Consistency Group

I use "clone" instead of "snapshot volume" because it's shorter (and PRTG recommends short metric names) and less annoying.

- Member volumes
- Read throughput
- Write throughput 
- Read IOPS
- Write IOPS
- Clone repo capacity used
- RO clone volumes
- RW clone volumes
- Volume clones
- Clone sets
- Clone sets in optimal state
- Snapshot limit
- Snapshots used
- Snapshots available
- Unique cache settings
- Age of newest snapshot
- Age of newest RO clone
- Age of newest RW clone
- Active snapshot schedule
- Capacity

## Additional information

Some related information can be found [here](https://scaleoutsean.github.io/2023/09/25/monitoring-netapp-eseries-with-prtg.html#security-in-shell-scripts).

## Change log

- 2023/10/30
  - Get-ESeriesCGInfo.ps1 - initial 1.0.0 release for Consistency Group monitoring
- 2023/10/12
  - Get-ESeriesSnapCloneRepoInfo.ps1 - initial 1.0.1 with snapshot and clone reserve capacity metrics
  - Get-ESeriesInfo.ps1 - 1.2.0 release with system capacity and drive count metric
- 2023/10/02
  - Get-ESeriesPoolInfo.ps1 - 1.0.0 release with username/password authentication
- 2023/10/01
  - Get-ESeriesInfo.ps1 - 1.1.0 release with username/password authentication
  - Get-ESeriesVolumeInfo.ps1 - initial 1.0.0 release with username/password authentication
- 2023/09/29
  - Get-ESeriesInfo.ps1 - initial 1.0.0 release with JWT authentication
