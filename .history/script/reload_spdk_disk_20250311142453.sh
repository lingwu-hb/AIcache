#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 默认值
VM_BASE_IP=${VM_BASE_IP:-"192.168.122"}
VM_SSH_PASS=${VM_SSH_PASS:-"openEuler12#$"}
SPDK_PATH=${SPDK_PATH:-"/home/lzq/spdk"}

[ $# -lt 2 ] && echo "Usage: $0 --cache-size SIZE" && exit 1

while [[ $# -gt 0 ]]; do
    case $1 in
    --cache-size)
        CACHE_SIZE="$2"
        shift 2
        ;;
    *) exit 1 ;;
    esac
done

cd ${SPDK_PATH}

# 删除OCF缓存设备
./scripts/rpc.py bdev_ocf_delete CAS1 2>/dev/null || true

# 删除分区设备
./scripts/rpc.py bdev_split_delete nvme0n1p0 2>/dev/null || true

# 删除NVMe设备
./scripts/rpc.py bdev_nvme_detach_controller nvme0 2>/dev/null || true

# 重新创建NVMe设备和分区
./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a 0000:83:00.0
./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1

# 创建测试用的内存盘作为core设备
./scripts/rpc.py bdev_malloc_create -b malloc0 512 4096

# 重建OCF缓存设备
./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 malloc0 --cache-line-size 4

# 运行性能测试
echo "Running FIO test..."
$SPDK_PATH/build/examples/perf -q 128 -o 4096 -w randread -t 10 -c 0xF -b CAS1
