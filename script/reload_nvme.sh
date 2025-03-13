#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 默认值
VM_BASE_IP=${VM_BASE_IP:-"192.168.122"}
# VM_SSH_PASS=${VM_SSH_PASS:-"openEuler12#$"} # 注释掉密码，因为已配置免密登录
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

# set -x
# set -e # 添加错误检查

# 获取PCI设备信息
# PCI_ADDR="0000:83:00.0"
# PCI_DEV="pci_${PCI_ADDR//:/_}"
# virsh nodedev-detach $PCI_DEV

# 辅助函数：执行命令并获取输出
execute_in_vm() {
    local VM_NAME=${1:-"vm01"}
    local CMD=$2

    # 执行命令并获取PID
    local EXEC_OUT=$(virsh qemu-agent-command "$VM_NAME" "{
        \"execute\": \"guest-exec\",
        \"arguments\": {
            \"path\": \"/bin/sh\",
            \"arg\": [\"-c\", \"$CMD\"],
            \"capture-output\": true
        }
    }")

    # 提取PID
    local PID=$(echo "$EXEC_OUT" | grep -o '"pid":[0-9]*' | cut -d':' -f2)

    # 获取命令执行结果
    local RESULT=$(virsh qemu-agent-command "$VM_NAME" "{
        \"execute\": \"guest-exec-status\",
        \"arguments\": {
            \"pid\": $PID
        }
    }")

    # 提取实际输出 (需要base64解码)
    echo "$RESULT" | grep -o '"out-data":"[^"]*"' | cut -d'"' -f4 | base64 -d
}

# 1. 检查是否有nvme设备
for vm_id in $(echo $VM_IDS | tr ',' ' '); do
    VM_NAME="vm$(printf "%02d" $vm_id)"
    if ! execute_in_vm "$VM_NAME" "lsblk" | grep -q nvme; then
        echo -e "${ERROR} VM${vm_id} 无nvme设备"
    fi
done

cd ${SPDK_PATH}

# 2. 删除CAS1, 然后lsblk会发现nvme0n1p0消失了
./scripts/rpc.py bdev_ocf_delete CAS1 || true # 忽略首次删除可能的错误
sleep 3

# 检查设备状态
VM_NAME="vm$(printf "%02d" $vm_id)"
execute_in_vm "$VM_NAME" "lsblk"

# 3. 删除nvme0n1，按新的CacheSize重建
./scripts/rpc.py bdev_split_delete nvme0n1 || true # 忽略首次删除可能的错误
sleep 3

# ./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a ${PCI_ADDR}
if ! ./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1; then
    echo -e "${ERROR} 创建split设备失败"
fi
sleep 3

# 4. 重新创建OCF设备
if ! ./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4; then
    echo -e "${ERROR} 创建OCF设备失败"
fi
sleep 3

# 重新配置VFIO传输
# ./scripts/rpc.py nvmf_create_transport -t VFIOUSER
# ./scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device1 -a -s sys1 -i 1 -I 32760
if ! ./scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device1 CAS1; then
    echo -e "${ERROR} 添加namespace失败"
fi
sleep 3
# ./scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0

# #  创建临时XML文件
# # 重新附加设备到VM，验证lsblk是否看到nvme0n1
# cat >/tmp/vfio.xml <<'EOF'
# <hostdev mode='subsystem' type='pci' managed='yes'>
#     <source>
#         <address domain='0x0000' bus='0x83' slot='0x00' function='0x0'/>
#     </source>
# </hostdev>
# EOF

# for vm_id in $(echo $VM_IDS | tr ',' ' '); do
#     VM_NAME="vm$(printf "%02d" $vm_id)"
#     virsh attach-device $VM_NAME /tmp/vfio.xml --current
# done

# 检查是否重新发现了nvme设备
for vm_id in $(echo $VM_IDS | tr ',' ' '); do
    VM_NAME="vm$(printf "%02d" $vm_id)"
    if ! execute_in_vm "$VM_NAME" "lsblk" | grep -q nvme; then
        echo -e "${ERROR} VM${vm_id} VM无CAS1"
    fi
done

# 清理
rm -f /tmp/vfio.xml
# 清理缓存
echo 3 >/proc/sys/vm/drop_caches

# 为每个VM清理缓存
for vm_id in $(echo $VM_IDS | tr ',' ' '); do
    VM_NAME="vm$(printf "%02d" $vm_id)"
    if ! execute_in_vm "$VM_NAME" "echo 3 > /proc/sys/vm/drop_caches"; then
        echo -e "${WARNING} VM ${vm_id} 清理缓存失败"
    fi
done
