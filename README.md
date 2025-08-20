# Various NetApp E-Series stuff


## ansible

- Sample Ansible files for E-Series SANtricity OS

## change-password

- change-password.ps1 - sets new password for user account on NetApp E-Series (PowerShell 7, Windows or Linux)

## monitor

- Various scripts related to monitoring (currently only PRTG)

## Comparison of E-Series in terms of shelves and disks

NetApp is unable to provide this unless you're spend some time digging around various search engines, so here goes:


| Model | Controller / base shelf | Max NL-SAS HDDs | Max SAS SSDs | Max NVMe SSDs | Expansion | Max exp DE212C | Max exp DE224C | Max exp DE460C |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| EF300 | NE224 (NVMe controller shelf) | 240 | 96 | 24 | Yes | 8 | 4 | 4 |
| EF600 | NE224 (NVMe controller shelf) | 420 | 96 | 24 | Yes | 8 | 7 | 7 |
| EF300C | NE224 (NVMe QLC controller shelf) | - | - | 24 (QLC only, DDP 11-24) | No | - | - | - |
| EF600C | NE224 (NVMe QLC controller shelf) | - | - | 24 (QLC only, DDP 11-24) | No | - | - | - |
| E4012 | DE212C (SAS controller shelf) | 300 | 96 | - | Yes | 7 | - | 4 |
| E4060 | DE460C (SAS controller shelf) | 300 | 120 | - | Yes | 7 | - | 4 |

Reference TRs with TR mentioned separately for easy search when they break links again:

- E4000: TR-5001 currently at https://www.netapp.com/media/116236-tr-5001-intro-to-netapp-e4000-arrays-with-santricity.pdf
- EF300: TR-4877 currently at https://www.netapp.com/media/21363-tr-4877.pdf 
- EF600: TR-4800 currently at https://www.netapp.com/media/17009-tr4800.pdf

Shelves with 3.5" disk drive slots (DE212C, DE460C) also support 2.5" disks with an adapter. Maximum number of drives assumes no shelf mixing. For example, both types of expansion shelves are attached to an E4060 at the same time, you could have 6 expansion shelves but would be limited by the number or type (SAS SSD, for example) of drives.

EF600C and EF300C are the same shelves and controllers as non-C versions, with the limitations noted in the table. E4024 does not exist and E4000 don't support DE224C shelves.

