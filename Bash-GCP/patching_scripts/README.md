The health_check.sh script will check for the system information. It was written
in Bash (rather than Python) since most of my fellow admin are more comfortable
in shell scripting.
    - Hostname
    - IP Address
    - Bastion/Jump Server (use to access this server)
    - Uptime
    - OS Type
    - Kernel Release
    - OS Release Version
    - OS Release Name
    - Architecture
    - Hardware Type
    - Number of Processors
    - Memory
    - Date of Last Patch
    - Third-Party Packages
    - Proxy Info
    - Repolist
    - Updates (if there are any)
    - Pending Package Updates
    - Installed Oracle ASMLib
    - Running Oracle ASMLib Process
    - Authentication Type
    - HPSA Agent Status
    - Mounted File System Disk Space
    - File System Over 80% Threshold

NOTE: The health_check.sh only run on RHEL5-6 and later release.  RHEL4 have
      some funky array issues and whatnot, so I ended up re-writing the
      health_check.sh script for the older RHEL4.

The patching script does the following:
    1. Create a backup of /etc/grub.conf file.
    2. Disable BoKs authentication.
    3. Run the patching tool. Either yum or the older up2date (for RHEL4).
    4. Activate back BoKs authentication.
    5. Check if server is physical or VMware guest OS.
    6. If VMware guest OS, check if vmware-config-tools.pl is installed (and
       then run it of course).
    7. Determined if Grub password has been setup, if yes, disable it
       temporarily.
    8. Verify patching status if,
       - All package update has been applied.
       - An error occured during patching.
       - There are still remaining updates available.


