#!/usr/bin/bash

# OnExit called when script closes
function on_exit {
    rm -f "${pipe}"
}

# Called for each line written to pipe
# Processes commands to create or delete VMs
function process_command {
    echo "${1}"
    local params=()
    read -ra params <<<"${1}"

    [[ ${#params[@]} = 6 && ${params[0]} = 'CREATE' &&
        ${params[2]} == ^[0-9]+$ && ${params[3]} == ^[0-9]+$ &&
        ${params[4]} == ^[0-9]+$ && ${params[5]} == ^[0-9]+$ ]] &&
        {
            local name=${params[1]}
            local cpus=${params[2]}
            local mem=${params[3]}
            local gpus=${params[4]}
            local disks=${params[5]}
            local used_gpus=()
            local used_disks=()
            local avail_gpus=()
            local avail_disks=()
            read -ra avail_gpus <${gpus_file}
            read -ra avail_disks <${disks_file}
            local gpus_len=${#avail_gpus[@]}
            local disks_len=${#avail_disks[@]}
            local alph=(echo {b..z})
            local date=''
            date=$(date -u +"%Y-%m-%dT%H:%M:%S")

            [[ ${name} == ^[a-zA-Z]+[0-9]*$ ]] || echo 'Incorrect name' >&2 && return 1
            [[ ${gpus} > ${gpus_len} || ${disks} > ${disks_len} ]] && echo 'Overloading resources' >&2 && return 3

            virt-clone --original ${original_vm} --name "${name}" --file "${avail_disks[0]}${name}.qcow2"
            used_disks=("${avail_disks[0]}")
            avail_disks=("${avail_disks[@]:1}")

            virsh setvcpus "${name}" "${cpus}" --maximum --config
            virsh setvcpus "${name}" "${cpus}" --config
            virsh setmaxmem "${name}" "${mem}G" --config
            virsh setmem "${name}" "${mem}G" --config

            for _ in $(seq "${gpus}"); do
                virsh attach-device "${name}" "${avail_gpus[0]}" --config
                used_gpus=("${used_gpus[@]}" "${avail_gpus[0]}")
                avail_gpus=("${avail_gpus[@]:1}")
            done

            for _ in $(seq "${disks}"); do
                qemu-img create -f qcow2 -o preallocation=metadata "${avail_disks[0]}${name}.qcow2" ${disk_size}
                virsh attach-disk "${name}" "${avail_disks[0]}${name}.qcow2" "vd${alph[0]}" --cache none --subdriver qcow2 --config
                used_disks=("${used_disks[@]}" "${avail_disks[0]}")
                avail_disks=("${avail_disks[@]:1}")
                alph=("${alph[@]:1}")
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

            echo "${date} Created VM ${name}"
            return 0
        }
    [[ ${#params[@]} = 2 && ${params[0]} = 'DESTROY' ]] &&
        {
            local name=${params[1]}
            local avail_gpus=()
            local avail_disks=()
            read -ra avail_gpus <${gpus_file}
            read -ra avail_disks <${disks_file}

            [[ ${name} == ^[a-zA-Z]+[0-9]*$ ]] && echo 'Incorrect name' >&2 && return 1
            [[ ! -r ${state_dir}${name} ]] && echo 'Machine file does not exist' >&2 && return 2
            read -ra machine <"${state_dir}${name}"

            avail_gpus=("${avail_gpus[@]}" "${machine[4]}")
            avail_disks=("${avail_disks[@]}" "${machine[5]}")
            echo "${avail_gpus[@]}" >${gpus_file}
            echo "${avail_disks[@]}" >${disks_file}

            {
                echo "${name} DESTROYED"
                echo "${date}"
                echo "${cpus}"
                echo "${mem}G"
                echo "${used_gpus[@]}"
                echo "${used_disks[@]}"
            } >"${state_dir}${name}"

            echo "${date} Destroyed VM ${name}"
            return 0
        }
} 1>>"${log_file}" 2>>"${err_file}"

original_vm='original_vm'
disk_size='1.7T'

root_path='/var/lib/mlserver/'
state_dir="${root_path}machines/"
pipe='/tmp/mlserver_pipe'
disks_file="${root_path}disks_file"
gpus_file="${root_path}gpus_file"
log_file="${root_path}log.log"
err_file="${root_path}err.log"

echo 'Starting VM manager' >'shut.log'

trap on_exit EXIT
[[ -d ${root_path} && -d ${state_dir} &&
    -r ${disks_file} && -r ${gpus_file} &&
    -r ${log_file} && -r ${err_file} ]] ||
    {
        echo 'The default files do not exist or are broken' >>'shut.log'
        exit 1
    }

line=''
while read -r line <${pipe}; do
    echo "${line}"
    [[ "${line}" = 'EXIT' ]] && exit 0
    process_command "${line}" || echo "Error processing ${line}" >>'shut.log'
done
