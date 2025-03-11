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

# 更新OCF缓存配置
update_cache_config() {
    local cache_size=$1
    
    echo "更新OCF缓存配置..."
    
    # 1. 删除现有的OCF设备
    cd ${SPDK_PATH}
    ./scripts/rpc.py bdev_ocf_delete CAS1
    if [ $? -ne 0 ]; then
        echo "错误: 删除OCF设备失败" >&2
        return 1
    fi
    
    # 2. 重新创建OCF设备，使用新的缓存大小
    ./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4
    if [ $? -ne 0 ]; then
        echo "错误: 创建OCF设备失败" >&2
        return 1
    fi
    
    # 3. 验证配置
    ./scripts/rpc.py bdev_ocf_get_stats CAS1
    if [ $? -ne 0 ]; then
        echo "错误: 验证OCF设备配置失败" >&2
        return 1
    fi
    
    echo "OCF缓存配置更新成功"
    return 0
}

# 主程序
main() {
    # 更新缓存配置
    if ! update_cache_config "$CACHE_SIZE"; then
        echo "更新缓存配置失败" >&2
        exit 1
    fi
    
    echo "缓存大小更新完成"
    exit 0
}

main
