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

set -x
# 检查设备初始状态
check_device_status() {
    local vm_id=$1
    local vm_name="vm$(printf "%02d" $vm_id)"
    # TODO: 需要确认SSH的具体连接参数是否正确
    sshpass -p "${VM_SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${VM_BASE_IP}.${vm_id} "lsblk | grep nvme || echo '无nvme0设备'"
}

# 1. 获取PCI设备信息
PCI_ADDR="0000:83:00.0"
PCI_DEV="pci_${PCI_ADDR//:/_}"



# 2. 创建临时XML文件
cat >/tmp/vfio.xml <<EOF
<hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
        <address domain='0x0000' bus='0x83' slot='0x00' function='0x0'/>
    </source>
</hostdev>
EOF

# 检查每个VM的初始设备状态
echo "检查设备初始状态..."
for vm_id in $(echo $VM_IDS | tr ',' ' '); do
    check_device_status $vm_id
done

# 3. 分离设备
# virsh nodedev-detach $PCI_DEV

cd ${SPDK_PATH}

# 4. 删除CAS1, 然后lsblk会发现nvme0n1p0消失了
./scripts/rpc.py bdev_ocf_delete CAS1
./scripts/rpc.py bdev_split_delete nvme0n1

# ./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a ${PCI_ADDR}
# 5. 重新组合OCF设备

./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1

#./scripts/rpc.py bdev_split_create -s 100 nvme0n1 1

./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4

# 6. 重新配置VFIO传输
# ./scripts/rpc.py nvmf_create_transport -t VFIOUSER
# ./scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device1 -a -s sys1 -i 1 -I 32760
./scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device1 CAS1
# ./scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0

# # 7. 重新附加设备到VM，验证lsblk是否看到nvme0n1
# for vm_id in $(echo $VM_IDS | tr ',' ' '); do
#     VM_NAME="vm$(printf "%02d" $vm_id)"
#     virsh attach-device $VM_NAME /tmp/vfio.xml --current
# done

# 检查每个VM的最终设备状态
echo "检查是否重新发现了nvme..."
for vm_id in $(echo $VM_IDS | tr ',' ' '); do
    check_device_status $vm_id
done

# 8. 清理
rm -f /tmp/vfio.xml
echo 3 >/proc/sys/vm/drop_caches
sshpass -p "${VM_SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${VM_BASE_IP}.201 "echo 3 > /proc/sys/vm/drop_caches"

