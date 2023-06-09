#!/usr/bin/bash

function exit_message {
    [ -n "${1}" ] && echo "${1}" >&2 || echo 'Failure while creating machine'

    [ -n "${name}" ] && {
        virsh undefine "${name}"
        for disk in "${used_disks[@]}"; do
            rm "${disk}${name}.qcow2"
        done
    }
        
    [ -n "${2}" ] && exit "${2}" || exit 255
}

original_vm='original_vm'
disk_size='1.7T'

root_path='/var/lib/mlserver/'
state_dir="${root_path}machines/"
disks_file="${root_path}disks_file"
gpus_file="${root_path}gpus_file"

[[ ${1} =~ ^[a-zA-Z][a-zA-Z0-9]+$ &&
    ${2} =~ ^[0-9]+$ && ${3} =~ ^[0-9]+$ &&
    ${4} =~ ^[0-9]+$ && ${5} =~ ^[0-9]+$ ]] || exit_message "Incorrect arguments ${*}" 1

name=${1}
cpus=${2}
mem=${3}
gpus=${4}
disks=$((${5} - 1))
used_gpus=()
used_disks=()
read -ra avail_gpus <${gpus_file}
read -ra avail_disks <${disks_file}
alph=(echo {b..z})
date=$(date -u +"%Y-%m-%d %H:%M:%S")

[[ ${gpus} -gt ${#avail_gpus[@]} || ${disks} -gt ${#avail_disks[@]} ]] && exit_message 'Overloading resources' 2

{
    virt-clone --original ${original_vm} --name "${name}" --file "${avail_disks[0]}${name}.qcow2" &&
        used_disks=("${avail_disks[0]}") &&
        avail_disks=("${avail_disks[@]:1}")
} &>'/dev/null' || exit_message 'Failed cloning original machine' 3

{
    virsh setvcpus "${name}" "${cpus}" --maximum --config &&
        virsh setvcpus "${name}" "${cpus}" --config &&
        virsh setmaxmem "${name}" "${mem}G" --config &&
        virsh setmem "${name}" "${mem}G" --config
} &>'/dev/null' || exit_message 'Failed setting cpus and memory' 4

for _ in $(seq "${gpus}"); do
    {
        virsh attach-device "${name}" "${avail_gpus[0]}" --config &&
            used_gpus=("${used_gpus[@]}" "${avail_gpus[0]}") &&
            avail_gpus=("${avail_gpus[@]:1}")
    } &>'/dev/null' || exit_message 'Failed attaching the gpus' 5
done

for _ in $(seq "${disks}"); do
    {
        qemu-img create -f qcow2 -o preallocation=metadata "${avail_disks[0]}${name}.qcow2" ${disk_size} &&
            virsh attach-disk "${name}" "${avail_disks[0]}${name}.qcow2" "vd${alph[0]}" --cache none --subdriver qcow2 --config &&
            used_disks=("${used_disks[@]}" "${avail_disks[0]}") &&
            avail_disks=("${avail_disks[@]:1}") &&
            alph=("${alph[@]:1}")
    } &>'/dev/null' || exit_message 'Failed attaching the disks' 6
done

virsh start "${name}" || exit_message 'Failed starting' 7

sleep 30

echo "${avail_gpus[@]}" >${gpus_file}
echo "${avail_disks[@]}" >${disks_file}

{
    echo "${name}"
    echo "${date}"
    echo "${cpus}"
    echo "${mem}G"
    echo "${used_gpus[@]}"
    echo "${used_disks[@]}"
} >"${state_dir}${name}"

echo "Created ${name}"
