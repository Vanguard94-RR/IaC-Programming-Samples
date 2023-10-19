#! /bin/bash
# Select Check mode for ansible
function prompt_confirm() {
    while true; do
        read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
        case $REPLY in
        [yY])
            echo
            return 0
            printf "--check"
            ;;
        [nN])
            echo
            return 1
            printf " "
            ;;
        *) printf " \033[31m %s \n\033[0m" "invalid input" ;;
        esac
    done
}

# example usage
prompt_confirm "Overwrite File?" || exit 0
