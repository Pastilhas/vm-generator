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
disks=${5}
used_gpus=()
used_disks=()
read -ra avail_gpus <${gpus_file}
read -ra avail_disks <${disks_file}
alph=(echo {b..z})
date=$(date -u +"%Y-%m-%d %H:%M:%S")

[[ ${gpus} > ${#avail_gpus[@]} || ${disks} > ${#avail_disks[@]} ]] &&
    exit_message 'Overloading resources' 2

{
    virt-clone --original ${original_vm} --name "${name}" --file "${avail_disks[0]}${name}.qcow2" &>'/dev/null' &&
        used_disks=("${avail_disks[0]}") &&
        avail_disks=("${avail_disks[@]:1}")
} || {
    exit_message 'Failed cloning original machine' 3
}

{
    virsh setvcpus "${name}" "${cpus}" --maximum --config &&
        virsh setvcpus "${name}" "${cpus}" --config &&
        virsh setmaxmem "${name}" "${mem}G" --config &&
        virsh setmem "${name}" "${mem}G" --config
} || {
    exit_message 'Failed setting cpus and memory' 4
}

for _ in $(seq "${gpus}"); do
    {
        virsh attach-device "${name}" "${avail_gpus[0]}" --config &&
            used_gpus=("${used_gpus[@]}" "${avail_gpus[0]}") &&
            avail_gpus=("${avail_gpus[@]:1}")
    } || {
        exit_message 'Failed attaching the gpus' 5
    }
done

for _ in $(seq "${disks}"); do
    {
        qemu-img create -f qcow2 -o preallocation=metadata "${avail_disks[0]}${name}.qcow2" ${disk_size} &>'/dev/null' &&
            virsh attach-disk "${name}" "${avail_disks[0]}${name}.qcow2" "vd${alph[0]}" --cache none --subdriver qcow2 --config &&
            used_disks=("${used_disks[@]}" "${avail_disks[0]}") &&
            avail_disks=("${avail_disks[@]:1}") &&
            alph=("${alph[@]:1}")
    } || {
        exit_message 'Failed attaching the gpus' 6
    }
done

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

virsh start "${name}" && sleep 10
echo "Created ${name}"
