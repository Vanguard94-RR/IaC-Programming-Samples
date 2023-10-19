
An Ansible role that installs Sysmon with selected configuration.

Currently there are no configurations included for Linux. You must supply your own if you wish to use this role on Linux hosts.

Supported platforms:

- Windows 10
- Windows Server 2019
- Windows Server 2016

Requirements
------------

None

Role Variables
--------------

Ansible variables from defaults/main.yml

```
sysmon_install_path: "C:\\Program Files\\Sysmon"
sysmon_version: "11.11"
sysmon_config: swiftonsecurity-sysmonconfig.xml
sysmon_linux_config: linux_sysmonconfig.xml
```

Dependencies
------------

None

Example Playbook Windows
----------------

```
- name: Install Sysmon
  hosts:
    - windows_host
    - linux_host
  vars:
    sysmon_install_path: "C:\tools\Sysmon"
    sysmon_version: "13.30"
    sysmon_config: olafhartong-sysmonconfig.xml
    sysmon_linux_config: linux-sysmonconfig.xml
  roles:
    - ansible-role-sysmon
```