#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# Command line arguments
VM_NUM=$1

# Validate inputs
if [ $# -lt 1 ]; then
        echo "Usage: $0 VM_NUM"
        exit 1
fi

# Initialize environment
init_env

# Destroy VMs
vm_num=$(virsh list --all | grep vm | wc -l)
for ((i = 0; i < ${vm_num}; i++)); do
        vm_name="vm$(printf "%02d" $((i + 1)))"
        virsh destroy "${vm_name}" 2>/dev/null || true
        virsh undefine "${vm_name}" --nvram 2>/dev/null || true
        sleep 2
done

# Clean up runtime directories
rm -rf /var/run/vm0*

# Kill related processes
# for _process in nvmf vhost VFIOUSER collect_spdk_cache.sh fio_result.log; do
#         pkill -f "${_process}" 2>/dev/null || true
# done
for _prosess in {nvmf,vhost,VFIOUSER,collect_spdk_cache.sh,fio_result.log};do
        ps aux | grep ${_prosess} | grep -v grep | awk '{print $2}' | xargs kill -9
done

sleep 2

# Clean up SPDK
${SPDK_PATH}/scripts/setup.sh cleanup
${SPDK_PATH}/scripts/setup.sh reset
# 接管设备
${SPDK_PATH}/scripts/setup.sh

# Clean up cache device
if [ -b "/dev/${CACHE_DEVICE}" ]; then
        mkfs -t ext4 /dev/${CACHE_DEVICE}
        sleep 3
        dd if=/dev/zero of=/dev/${CACHE_DEVICE} bs=1G count=1 oflag=direct
        sleep 3
fi

echo "Environment cleanup completed"


