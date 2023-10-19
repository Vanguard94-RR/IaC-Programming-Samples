## Requirements

* Ansible 2.3.0

## Variables

| Name                                           | Default Value   | Description                                                                                                                           |
| ---------------------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `win_security_PasswordComplexity`              | `1`             | Flag that indicates whether the operating system MUST require that passwords meet complexity requirements. Default: True              |
| `win_security_LockoutBadCount`                 | `4`             | Number of failed logon attempts after which a user account MUST be locked out. Default: 4                                             |
| `win_security_ResetLockoutCount`               | `15`            | Number of minutes after a failed logon attempt that the account MUST be locked out. Default: 15 minutes                               |
| `win_security_LockoutDuration`                 | `15`            | The number of minutes that a locked-out account MUST remain locked out before automatically becoming unlocked. Default: 15 minutes    |
| `win_security_SeRemoteInteractiveLogonRight`   | `*S-1-5-32-544` | Determines which users or groups can access the logon screen of a remote computer through a RDP connection. Default: Administrators   |
| `win_security_SeTcbPrivilege`                  | `*S-1-0-0`      | Allows a process to authenticate like a user and thus gain access to the same resources as a user. Default: Nobody                    |
| `win_security_SeMachineAccountPrivilege`       | `*S-1-5-32-544` | Allows the user to add a computer to a specific domain. Default: Administrators                                                       |
| `win_security_SeTrustedCredManAccessPrivilege` | ``              | Access Credential Manager as a trusted caller policy setting is used by Credential Manager during backup and restore. Default: No One |
| `win_security_SeNetworkLogonRight`             | `*S-1-0-0`      | Required for an account to log on using the network logon type. Default: Nobody                                                       |
