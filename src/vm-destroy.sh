#!/usr/bin/bash

function exit_message {
    [ -n "${1}" ] && echo "${1}" >&2 || echo 'Failure while creating machine'
    [ -n "${2}" ] && exit "${2}" || exit 255
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
date_then=$(grep -Po "[0-9]+-[0-9]+-[0-9]+ [0-9]+:[0-9]+:[0-9]+" <"${state_dir}${name}")
cpus=$(grep -Po "[0-9]+(?!=G)" <"${state_dir}${name}")
mem=$(grep -Po "[0-9]+(?=G)" <"${state_dir}${name}")
used_gpus=("$(grep -Po "/var/lib/mlserver/gpus/.*xml" <"${state_dir}${name}")")
used_disks=("$(grep -Po "/mnt/disk[0-9]/" <"${state_dir}${name}")")

{
    virsh destroy "${name}" && virsh undefine "${name}"
} || exit_message "Failed to destroy ${name}" 3

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
