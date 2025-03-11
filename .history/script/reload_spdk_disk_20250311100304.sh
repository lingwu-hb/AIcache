#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 默认值
VM_BASE_IP=${VM_BASE_IP:-"192.168.122"}
VM_SSH_PASS=${VM_SSH_PASS:-"openEuler12#$"}
SPDK_PATH=${SPDK_PATH:-"/home/lzq/spdk"}

usage() {
    echo "用法: $0 --cache-size SIZE --vm-ids VM_IDS"
    echo "  --cache-size SIZE   : 缓存大小"
    echo "  --vm-ids VM_IDS     : VM ID (例如: 1 或 1,2,3 或 1-5)"
    exit 1
}

# 解析参数
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
    *)
        usage
        ;;
    esac
done

# 检查必需参数
if [ -z "$CACHE_SIZE" ] || [ -z "$VM_IDS" ]; then
    usage
fi

# 解析VM IDs
parse_vm_ids() {
    local ids=$1
    if [[ $ids =~ ^[0-9]+$ ]]; then
        echo "$ids"
    elif [[ $ids =~ ^[0-9]+-[0-9]+$ ]]; then
        local start=${ids%-*}
        local end=${ids#*-}
        seq $start $end
    elif [[ $ids =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        echo $ids | tr ',' '\n'
    else
        echo "错误: 无效的VM ID格式: $ids" >&2
        exit 1
    fi
}

# 发送QEMU监视器命令
send_qemu_cmd() {
    local vm_id=$1
    local cmd=$2
    local vm_name="vm$(printf "%02d" $vm_id)"

    echo "(qemu) $cmd"
    virsh qemu-monitor-command --hmp $vm_name "$cmd"
}

# 在VM中运行SSH命令
run_ssh() {
    local vm_id=$1
    local cmd=$2
    local vm_ip="${VM_BASE_IP}.$((200 + vm_id))"

    sshpass -p "${VM_SSH_PASS}" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${vm_ip} "$cmd"
}

# 重启SPDK进程
restart_spdk() {
    local cache_size=$1

    # 停止现有SPDK进程
    pkill -f spdk_tgt || true
    sleep 2

    # 启动新的SPDK进程
    cd ${SPDK_PATH} && nohup ./scripts/spdk_tgt.py --cache-size ${cache_size} >${SPDK_PATH}/log/spdk_start.log 2>&1 &
    sleep 5

    # 检查进程是否启动
    if ! pgrep -f spdk_tgt >/dev/null; then
        echo "错误: SPDK进程启动失败" >&2
        return 1
    fi
    return 0
}

# 查询设备信息
query_device_info() {
    local vm_id=$1
    echo "查询VM${vm_id}的设备信息..."
    echo "=== 设备树 ==="
    send_qemu_cmd $vm_id "info qtree"
    echo -e "\n=== PCI设备 ==="
    send_qemu_cmd $vm_id "info pci"
    echo -e "\n=== 块设备 ==="
    send_qemu_cmd $vm_id "info block"
}

# 重新加载磁盘
reload_disk() {
    local vm_id=$1
    local cache_size=$2

    echo "处理 VM${vm_id}..."

    # 1. 卸载文件系统
    run_ssh $vm_id "umount /dev/nvme0n1 || true"

    # 2. 从QEMU中移除设备
    if ! send_qemu_cmd $vm_id "device_del spdk_vfio"; then
        echo "错误: 移除设备失败" >&2
        return 1
    fi
    sleep 2

    # 3. 重启SPDK
    if ! restart_spdk $cache_size; then
        return 1
    fi

    # 4. 重新添加设备
    if ! send_qemu_cmd $vm_id "device_add vfio-user-pci,id=spdk_vfio,socket=/var/run/vm${vm_id}/cntrl,bus=pci.1"; then
        echo "错误: 添加设备失败" >&2
        return 1
    fi
    sleep 2

    # 5. 重新挂载文件系统
    run_ssh $vm_id "mount /dev/nvme0n1 /mnt || true"

    echo "VM${vm_id} 处理完成"
    return 0
}

# 主程序
main() {
    local all_success=true

    # 处理每个VM
    while read -r vm_id; do
        if ! reload_disk $vm_id $CACHE_SIZE; then
            all_success=false
            echo "VM${vm_id}处理失败" >&2
        fi
    done < <(parse_vm_ids "$VM_IDS")

    $all_success && exit 0 || exit 1
}

main
