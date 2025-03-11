#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 默认值
VM_BASE_IP=${VM_BASE_IP:-"192.168.122"}
VM_SSH_PASS=${VM_SSH_PASS:-"openEuler12#$"}
SPDK_PATH=${SPDK_PATH:-"/home/lzq/spdk"}

[ $# -lt 4 ] && echo "Usage: $0 --cache-size SIZE --vm-ids VM_IDS" && exit 1

while [[ $# -gt 0 ]]; do
    case $1 in
    --cache-size)
        CACHE_SIZE="$2"
        shift 2
        ;;
    --vm-ids)
        VM_IDS="$2"
        shift 2
        ;;
    *) exit 1 ;;
    esac
done

cd ${SPDK_PATH}

# 1. 确保IOMMU已启用
if ! grep -q "intel_iommu=on" /proc/cmdline; then
    echo "Warning: IOMMU not enabled in kernel cmdline" >&2
fi

# 2. 解绑并重新绑定VFIO设备
if [ -e /sys/bus/pci/devices/0000:83:00.0/driver ]; then
    echo 0000:83:00.0 > /sys/bus/pci/devices/0000:83:00.0/driver/unbind
fi
echo "vfio-pci" > /sys/bus/pci/devices/0000:83:00.0/driver_override
echo 0000:83:00.0 > /sys/bus/pci/drivers/vfio-pci/bind

# 3. 删除现有设备和配置
./scripts/rpc.py nvmf_subsystem_remove_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0
./scripts/rpc.py bdev_ocf_delete CAS1
rm -rf /var/run/bar0 /var/run/cntrl

# 4. 重新创建设备链
./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a 0000:83:00.0
./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1
./scripts/rpc.py bdev_rbd_create -b core1 vmdisk vm01 512
./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4

# 5. 重新配置VFIO传输
./scripts/rpc.py nvmf_create_transport -t VFIOUSER
./scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device1 -a -s sys1 -i 1 -I 32760
./scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device1 CAS1
./scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0
