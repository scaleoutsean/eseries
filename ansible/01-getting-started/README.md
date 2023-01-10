# Getting started with Ansible and NetApp E-Series

This content was extracted from the NetApp [TR-4574](https://www.netapp.com/media/17237-tr4574.pdf) and improved by removing smart quotes.

- Ansible working directory with inventory might look like this:

```raw
host.yml
  group_vars/
    all.yml
    servers.yml
    eseries_arrays.yml
  host_vars/
    database.yml
    metadata.yml
    storage.yml
    webserver.yml
playbook.yml    
```

- Example inventory file with variables:

```yml
all:
  hosts:
  children:
    servers:
      webserver:
        ansible_host: 192.168.1.100
        ansible_ssh_user: admin
        ansible_become_pass: admin_pass
      database:
        ansible_host: 192.168.1.200
        ansible_ssh_user: admin
        ansible_become_pass: admin_pass
    eseries_arrays:
      hosts:
        metadata:
          eseries_system_serial: "012345678901"
          eseries_system_password: admin_password
          eseries_proxy_api_url: https://192.168.1.100:8443/devmgr/v2/
          eseries_proxy_api_password: admin_password
        storage:
          eseries_system_api_url: https://192.168.1.200:8443/devmgr/v2/
          eseries_system_password: admin_password
```

- Example playbook with E-Series modules that creates a R6 volume group using 10 drives and in it one 100Gi volume with write caching disabled:

```
- host: eseries_arrays
  gather_facts: false # Forces Ansible not to collect facts about target nodes
  connection: local   # Forces Ansible to execute commands from the localhost
  collections:
  - netapp_eseries.santricity
tasks:
- name: Create a RAID6 volume group
  na_santricity_storagepool:
    ssid: "{{ eseries_ssid }}"
    api_url: "{{ eseries_api_url }}"
    api_username: "{{ eseries_api_username }}"
    api_password: "{{ eseries_api_password }}"
    validate_certs: false
    state: present
    name: example_volume_group
    raid_level: raid6
    criteria_drive_count: 10
- name: Create volume in volume group
  na_santricity_volume:
    ssid: "{{ eseries_ssid }}"
    api_url: "{{ eseries_api_url }}"
    api_username: "{{ eseries_api_username }}"
    api_password: "{{ eseries_api_password }}"
    validate_certs: false
    state: present
    name: example_volume
    storage_pool_name: example_volume_group
    size: 100
    size_unit: gb
    write_cache_enable: false
```

- Example Ansible playbook with an E-Series host role (which targets host (client) connected to E-Series):

```yml
- hosts: eseries_storage_arrays
  gather_facts: false
  collections:
    netapp_eseries.santricity
  tasks:
    - name: Provision E-Series storage
      import_role:
        name: nar_santricity_host
```

- Example of an E-Series storage array host file:

```yaml
eseries_system_api_url: https://192.168.1.200:8443/devmgr/v2/
eseries_system_password: admin_password
eseries_validate_certs: false
eseries_system_name: my_eseries_array
eseries_initiator_protocol: fc

eseries_management_interfaces:
  config_method: static
  subnet_mask: 255.255.255.0
  controller_a:
  - address: 192.168.1.100
  controller_b:
  - address: 192.168.1.102

eseries_storage_pool_configuration:
  - name: vg_example
    raid_level: raid6
    criteria_drive_count: 10
    volumes:
      - name: vol_example_[1-2]
        host: servers
        size: 2
        size_unit: tb
```

## Get started

```sh
mkdir -p ~/ansible_project/{host_vars,group_vars}
```

- Create an inventory file ~/ansible_project/hosts.yml:

```yml 
all:
  children:
    eseries_arrays:
      hosts:
        storage1:
        storage2:
    database_servers:
      hosts:
        storage_server:
```

- Create a storage inventory file ~/ansible_project/host_vars/storage1.yml:

```yml 
eseries_system_name: my_eseries_array
eseries_system_api_url: https://192.168.1.200:8443/devmgr/v2/
eseries_system_password: admin_password
eseries_validate_certs: false
eseries_system_serial: 012345678901 # Use eseries_system_serial and eseries_subnet when dhcp is
eseries_subnet: 192.168.0.0/22      # available and system have not been configured. This will
                                    # allow the collection to discover and set the password.
eseries_initiator_protocol: fc
eseries_management_interfaces:
  config_method: static
  subnet_mask: 255.255.255.0
  gateway: 192.168.1.1
  controller_a:
    - address: 192.168.1.100
  controller_b:
    - address: 192.168.1.102
eseries_storage_pool_configuration:
  - name: vg_example
    raid_level: raid6
    criteria_drive_count: 10
    volumes:
      - name: vol_example_[1-2]
        host: servers
        size: 2048
```

- Create a playbook ~/ansible_project/eseries_playbook.yml:

```yml
- hosts: eseries_arrays
  gather_facts: false
  collections:
    - netapp_eseries.santricity
  tasks:
    - name: Apply management-related tasks to E-Series storage systems
      import_role:
        name: nar_santricity_management
    - name: Apply host-related tasks to E-Series storage systems
      import_role:
        name: nar_santricity_host
```

- Execute the playbook:

```sh
ansible-playbook -i hosts.yml eseries_playbook.yml
```

