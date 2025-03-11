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

# 设置日志级别
./scripts/rpc.py log_set_level ERROR
./scripts/rpc.py log_set_print_level ERROR

# 删除现有设备
./scripts/rpc.py nvmf_subsystem_remove_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0
./scripts/rpc.py nvmf_delete_subsystem nqn.2021-06.io.spdk:ctc_device1
./scripts/rpc.py bdev_ocf_delete CAS1

# 重新创建设备
./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1
./scripts/rpc.py bdev_rbd_create -b core1 vmdisk vm01 512
./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4

# 重新配置VFIO传输
rm -rf /var/run/bar0 /var/run/cntrl
./scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device1 -a -s sys1 -i 1 -I 32760
./scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device1 CAS1
./scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0

# 获取缓存统计信息
./scripts/rpc.py bdev_ocf_get_stats CAS1
