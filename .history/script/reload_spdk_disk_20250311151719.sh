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

# 1. 获取PCI设备信息
PCI_ADDR="0000:83:00.0"
PCI_DEV="pci_${PCI_ADDR//:/_}"

# 2. 创建临时XML文件
cat > /tmp/vfio.xml << EOF
<hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
        <address domain='0x0000' bus='0x83' slot='0x00' function='0x0'/>
    </source>
</hostdev>
EOF

# 3. 分离设备
virsh nodedev-detach $PCI_DEV

cd ${SPDK_PATH}

# 4. 删除现有SPDK配置
./scripts/rpc.py nvmf_subsystem_remove_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0
./scripts/rpc.py bdev_ocf_delete CAS1
rm -rf /var/run/bar0 /var/run/cntrl

# 5. 重新创建设备链
./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a ${PCI_ADDR}
./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1
./scripts/rpc.py bdev_rbd_create -b core1 vmdisk vm01 512
./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4

# 6. 重新配置VFIO传输
./scripts/rpc.py nvmf_create_transport -t VFIOUSER
./scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device1 -a -s sys1 -i 1 -I 32760
./scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device1 CAS1
./scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0

# 7. 重新附加设备到VM
for vm_id in $(echo $VM_IDS | tr ',' ' '); do
    VM_NAME="vm$(printf "%02d" $vm_id)"
    virsh attach-device $VM_NAME /tmp/vfio.xml --current
done

# 8. 清理
rm -f /tmp/vfio.xml
