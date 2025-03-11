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

# 删除OCF缓存设备
./scripts/rpc.py bdev_ocf_delete CAS1

# 重新创建分区和OCF缓存设备
./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1
./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4

# 验证配置
./scripts/rpc.py bdev_ocf_get_stats CAS1
