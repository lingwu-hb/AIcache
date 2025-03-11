#!/bin/bash

# 检查参数
if [ $# -ne 1 ]; then
    echo "用法: $0 <vm_id>"
    echo "例如: $0 1 (查询vm01的设备ID)"
    exit 1
fi

VM_ID=$1
VM_NAME="vm$(printf "%02d" $VM_ID)"

echo "====== 查询虚拟机 $VM_NAME 的设备信息 ======"

# 查询所有PCI设备
echo -e "\n==== PCI设备列表 ===="
virsh qemu-monitor-command --hmp $VM_NAME "info pci"

# 查询所有设备
echo -e "\n==== 所有设备 ===="
virsh qemu-monitor-command --hmp $VM_NAME "info qtree"

# 查询所有块设备
echo -e "\n==== 块设备 ===="
virsh qemu-monitor-command --hmp $VM_NAME "info block"

# 查询设备ID
echo -e "\n==== 查找vfio-user设备 ===="
DEVICE_INFO=$(virsh qemu-monitor-command --hmp $VM_NAME "info qtree" | grep -A 20 "vfio-user")
if [ -n "$DEVICE_INFO" ]; then
    echo "$DEVICE_INFO"
    DEVICE_ID=$(echo "$DEVICE_INFO" | grep -oP 'id = "\K[^"]+' | head -1)
    if [ -n "$DEVICE_ID" ]; then
        echo -e "\n找到vfio-user设备ID: $DEVICE_ID"
        echo "使用以下命令热拔插该设备:"
        echo "virsh qemu-monitor-command --hmp $VM_NAME \"device_del $DEVICE_ID\""
        echo "virsh qemu-monitor-command --hmp $VM_NAME \"device_add vhost-user-blk-pci,id=$DEVICE_ID,chardev=spdk_char\""
    else
        echo "未找到设备ID"
    fi
else
    echo "未找到vfio-user设备"
fi 