#!/bin/bash

WORKING_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$WORKING_DIR" ]]; then WORKING_DIR="$PWD"; fi

source ${WORKING_DIR}/lvm.sh
