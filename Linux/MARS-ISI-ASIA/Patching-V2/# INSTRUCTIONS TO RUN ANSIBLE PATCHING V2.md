# INSTRUCTIONS TO RUN ANSIBLE PATCHING V2

## RUN PLAYBOOK WITH COMMAND:

To install only security patches run:
$ ansible-playbook -i /home/manu3113/MARS-ISI-ASIA/Patching/V2/inventory -l HKG_Group_1_2 OS-Patching-Playbook.yml --extra-vars "ev_security_only=yes" --check

Test
$ ansible-playbook -i /home/manu3113/MARS-ISI-ASIA/Patching/V2/inventory -l dphk-vl-logging-01 OS-Patching-Playbook.yml --extra-vars "ev_security_only=yes" --check

To install all packages run:
$ ansible-playbook -i /home/manu3113/MARS-ISI-ASIA/Patching/V2/inventory -l HKG_Group_1_2 OS-Patching-Playbook.yml --extra-vars "ev_security_only=no" --check
