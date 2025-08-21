# Various NetApp E-Series stuff


## ansible

- Sample Ansible files for E-Series SANtricity OS

## change-password

- change-password.ps1 - sets new password for user account on NetApp E-Series (PowerShell 7, Windows or Linux)

## monitor

- Various scripts related to monitoring (currently only PRTG)

## Comparison of E-Series in terms of shelves and disks

NetApp is unable to provide this unless you're willing to spend some time digging around various search engines. [This](https://docs.netapp.com/us-en/e-series/getting-started/learn-hardware-concept.html) is as good as it gets.


| Model | Controller / base shelf | Max NL-SAS HDDs | Max SAS SSDs | Max NVMe SSDs | Expansion | Max exp DE212C | Max exp DE224C | Max exp DE460C |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| EF300 | NE224 (NVMe shelf) | 240 | 96 | 24 | Yes | 8 | 4 | 4 |
| EF600 | NE224 (NVMe shelf) | 420 | 96 | 24 | Yes | 8 | 7 | 7 |
| EF300C | NE224 (NVMe shelf) | - | - | 24 (QLC only, DDP 11-24) | No | - | - | - |
| EF600C | NE224 (NVMe shelf) | - | - | 24 (QLC only, DDP 11-24) | No | - | - | - |
| E4012 | DE212C (SAS shelf) | 252 | 96 | - | Yes | 7 | - | 4 |
| E4060 | DE460C (SAS shelf) | 300 | 120 | - | Yes | 7 | - | 4 |

Reference TRs with TR mentioned separately for easy search when they break links again:

- E4000: TR-5001 currently at https://www.netapp.com/media/116236-tr-5001-intro-to-netapp-e4000-arrays-with-santricity.pdf
- EF300: TR-4877 currently at https://www.netapp.com/media/21363-tr-4877.pdf 
- EF600: TR-4800 currently at https://www.netapp.com/media/17009-tr4800.pdf

Shelves with 3.5" disk drive slots (DE212C, DE460C) also support 2.5" disks with an adapter.

Example for E4000 with 3.5" NL-SAS so that you don't have to open : 

- the first limit is the model limit, 300 NL-SAS
- both types of expansion shelves can be attached to E4060 or E4012 at the same time but not more than 5 shelves, with an exception of DE212C (7 of which can be attached)
- E4012 (DE212C-based) can have an additional 7 DE212C, and so the maximum number of NL-SAS disks in this configuration is 8 x 12 = 96. Otherwise up to 5 shelves (controller + expansion) all together in any combination (e.g. 1 controller + 2 DE460C + 2 DE212C = 5). If 4 x DE460C is attached, that maxes out stack size of 5 shelves for non-DE212C only scenarios and the maximum NL-SAS disk count for mixed shelves becomes 12 + (4 x 60) = 252
- E4060: the maximum stack size is 5 shelves and given that the controller shelf is DE460C-based, that equals the maximum number of disk drive slots as well and is the maximum number of NL-SAS for an E4000 configuration: (1 x 60) + (4 x 60) = 300 NL-SAS slots
- E4024 does not exist and E4000 don't support DE224C shelves unless in head upgrade scenarios. The E4012 currently has a minimum of 6 and E4060 of 20 disks in the initial controller enclosure

EF600C and EF300C are the same shelves and controllers as non-C versions, with the limitations noted in the table. 

