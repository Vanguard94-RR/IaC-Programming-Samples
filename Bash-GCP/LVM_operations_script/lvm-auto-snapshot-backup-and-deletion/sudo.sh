# Providing sudo access to complete function 
function Sudo {
        local firstArg=$1
        if [ $(type -t $firstArg) = function ]
        then
                shift && $(which sudo) bash -c "$(declare -f $firstArg);$firstArg $*"
        elif [ $(type -t $firstArg) = alias ]
        then
                alias sudo='\sudo '
                eval "sudo $@"
        else
                $(which sudo) "$@"
        fi
}
