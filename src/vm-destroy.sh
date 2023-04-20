#!/usr/bin/bash

function exit_message {
    if [ -n "${1}" ]; then
        echo "${1}" >&2
    else
        echo 'Failure while creating machine'
    fi

    if [ -n "${name}" ]; then
        virsh undefine "${name}"

        for disk in "${used_disks[@]}"; do
            rm "${disk}${name}.qcow2"
        done
    fi

    if [ -n "${2}" ]; then
        exit "${2}"
    else
        exit 255
    fi
}

root_path='/var/lib/mlserver/'
state_dir="${root_path}machines/"
disks_file="${root_path}disks_file"
gpus_file="${root_path}gpus_file"

[[ ${1} =~ ^[a-zA-Z][a-zA-Z0-9]+$ ]] || exit_message "Incorrect arguments ${*}" 1
name=${1}

[[ -r "${state_dir}${name}" ]] || exit_message "Machine ${name} does not exist" 2

read -ra avail_gpus <${gpus_file}
read -ra avail_disks <${disks_file}
date_now=$(date -u +"%Y-%m-%d %H:%M:%S")

read -ra machine <"${state_dir}${name}"
date_then=${machine[1]}
cpus=${machine[2]}
mem=${machine[3]}
used_gpus=("${machine[4]}")
used_disks=("${machine[5]}")

virsh destroy "${name}"
virsh undefine "${name}"

for disk in "${used_disks[@]}"; do
    rm "${disk}${name}.qcow2"
done

avail_gpus=("${avail_gpus[@]}" "${used_gpus[@]}")
avail_disks=("${avail_disks[@]}" "${used_disks[@]}")

echo "${avail_gpus[@]}" >${gpus_file}
echo "${avail_disks[@]}" >${disks_file}

{
    echo "${name} DESTROYED"
    echo "${date_then} ${date_now}"
    echo "${cpus}"
    echo "${mem}G"
    echo "${used_gpus[@]}"
    echo "${used_disks[@]}"
} >"${state_dir}${name}"

echo "Destroyed ${name}"
