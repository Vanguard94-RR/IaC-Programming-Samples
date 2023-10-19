#!/bin/bash

##enable (unlock) user script

while :
do 
	USERNAME=$(whiptail --inputbox "Enter username:" 10 60 3>&1 1>&2 2>&3)
        if [ $? != 0 ]; then . ./scripts/main-menu.sh; exit; fi
        id $USERNAME &>/dev/null
        if [ $? -eq 0 ]; then
		usermod -U $USERNAME
                whiptail --title "Enable User" --msgbox "User $USERNAME was enabled successfully." 10 60
                . ./scripts/main-menu.sh
        else
            	whiptail --title "NOT FOUND!!" --msgbox "There is no such user\nPlease enter username correctly." 8 78
        fi
done


