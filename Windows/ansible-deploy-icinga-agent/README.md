# Ansible Role: Deploy Icinga2 Agent 

*Role for deploying Icinga2 on any RPM / DEB -based Host and connecting to an existing Icinga master instance.*

This will

* Install the official Icinga2 APT / RPM repository on your agent host(s)
* Install and configure Icinga2 on your agent hosts
* Configure your Icinga2 master host

A "Top-Down Config Sync" approach is used between Icinga master and agent. (See: https://icinga.com/docs/icinga2/latest/doc/06-distributed-monitoring/#top-down-config-sync)

## How to use

```yaml
- name: Setup Icinga2 Agent
  hosts: icinga-agents          # Hosts on which to deploy Icinga agent
  roles:
    - deploy-icinga-agent       # This Icinga role
  vars:
    - i2_master_fqdn: icingamaster.domain.tld     # (Ansible) FQDN of the master
    - i2_master_internal_hostname: "fd08::1"      # Internal Hostname / IP of Icinga master
```

* `i2_master_fqdn`: FQDN of the Icinga2 master as mentioned in the Ansible inventory.
* `i2_master_internal_hostname`: Internal / private Hostname or IP-address of the Icinga2 master. If you are using a public network to connect agent and master, use the master's FQDN here (or use `"{{ inventory_hostname }}"` as a value)

Start via 

```
ansible-playbook -i myhosts.yml deploy-icinga-agent-role.yml
```

Then configure your host and your services in the agent's config directory **on the Icinga master**:

* Host settings: `/etc/icinga2/zones.d/<agent fqdn>/host.conf`
* Service settings: `/etc/icinga2/zones.d/<agent fqdn>/services.conf` _(to be created)_

Your templates such as `generic-host` and `generic-master` should be created in `/etc/icinga2/zones.d/global-templates/global-templates.conf`, e.g.:

```
/*
 * GLOBAL Generic template examples.
 */


template Host "global-generic-host" {
  max_check_attempts = 3
  check_interval = 1m
  retry_interval = 30s

  check_command = "hostalive"
}

template Service "global-generic-service" {
  max_check_attempts = 5
  check_interval = 1m
  retry_interval = 30s
}

template User "global-generic-user" {
}
```

Those will be copied to all agents globally and can therefore be used in the service-/host-config of all agents.

