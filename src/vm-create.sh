#!/usr/bin/bash

original_vm='original_vm'
disk_size='1.7T'

root_path='/var/lib/mlserver/'
state_dir="${root_path}machines/"
disks_file="${root_path}disks_file"
gpus_file="${root_path}gpus_file"

{
    [[ ${1} =~ ^[a-zA-Z][a-zA-Z0-9]+$ &&
        ${2} =~ ^[0-9]+$ && ${3} =~ ^[0-9]+$ &&
        ${4} =~ ^[0-9]+$ && ${5} =~ ^[0-9]+$ ]]
} || {
    echo Incorrect arguments "${@}"
    exit 1
}

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

[[ ${gpus} > ${#avail_gpus[@]} || ${disks} > ${#avail_disks[@]} ]] && echo Overloading resources >&2 && exit 2

{
    virt-clone --original ${original_vm} --name "${name}" --file "${avail_disks[0]}${name}.qcow2" &&
        used_disks=("${avail_disks[0]}") &&
        avail_disks=("${avail_disks[@]:1}")
} || {
    echo Failed cloning original machine >&2
    virsh undefine "${name}"
    rm "${used_disks[@]}"
    exit 3
}

echo Cloned original vm

{
    virsh setvcpus "${name}" "${cpus}" --maximum --config &&
        virsh setvcpus "${name}" "${cpus}" --config &&
        virsh setmaxmem "${name}" "${mem}G" --config &&
        virsh setmem "${name}" "${mem}G" --config
} || {
    echo Failed setting cpus and memory >&2
    virsh undefine "${name}"
    rm "${used_disks[@]}"
    exit 4
}

echo Set vcpus and mem

for _ in $(seq "${gpus}"); do
    {
        virsh attach-device "${name}" "${avail_gpus[0]}" --config &&
            used_gpus=("${used_gpus[@]}" "${avail_gpus[0]}") &&
            avail_gpus=("${avail_gpus[@]:1}")
    } || {
        echo Failed attaching the gpus >&2
        virsh undefine "${name}"
        rm "${used_disks[@]}"
        exit 5
    }
done

echo Attached all gpus

for _ in $(seq "${disks}"); do
    {
        qemu-img create -f qcow2 -o preallocation=metadata "${avail_disks[0]}${name}.qcow2" ${disk_size} &&
            virsh attach-disk "${name}" "${avail_disks[0]}${name}.qcow2" "vd${alph[0]}" --cache none --subdriver qcow2 --config &&
            used_disks=("${used_disks[@]}" "${avail_disks[0]}") &&
            avail_disks=("${avail_disks[@]:1}") &&
            alph=("${alph[@]:1}")
    } || {
        echo Failed attaching the gpus >&2
        virsh undefine "${name}"
        rm "${used_disks[@]}"
        exit 6
    }
done

echo Attached all disks

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

echo Created "${name}"
