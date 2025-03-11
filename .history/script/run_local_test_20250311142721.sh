#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

usage() {
    echo "Usage: $0 PATTERN FIO_REPLAY_TRACE CACHE_SIZE"
    echo "  PATTERN          : 测试模式 (如 das-bind)"
    echo "  FIO_REPLAY_TRACE : FIO回放文件名 (如 ali-dev-5.txt)"
    echo "  CACHE_SIZE       : 缓存大小"
    exit 1
}

[ $# -lt 3 ] && usage

PATTERN=$1
FIO_REPLAY_TRACE=$2
CACHE_SIZE=$3
TIME_STAMP=$(date "+%m%d_%H%M")

# 创建结果目录
RESULT_DIR="${RESULT_BASE}/result/${PATTERN}+${FIO_REPLAY_TRACE}"
mkdir -p ${RESULT_DIR}

cd ${SPDK_PATH}

# 设置日志级别
./scripts/rpc.py log_set_level ERROR
./scripts/rpc.py log_set_print_level ERROR

# 删除旧设备
./scripts/rpc.py bdev_ocf_delete CAS1 2>/dev/null || true
./scripts/rpc.py bdev_split_delete nvme0n1p0 2>/dev/null || true
./scripts/rpc.py bdev_nvme_detach_controller nvme0 2>/dev/null || true

# 创建基础设备
./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a 0000:83:00.0
./scripts/rpc.py bdev_split_create -s ${CACHE_SIZE} nvme0n1 1

# 创建RBD设备
./scripts/rpc.py bdev_rbd_create -b core1 vmdisk vm01 512

# 创建OCF缓存
./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4

# 运行FIO测试
FIO_RESULT="${RESULT_DIR}/${TIME_STAMP}_fio_result.log"
${SCRIPT_DIR}/run_fio_test.sh "localhost" "CAS1" "${PATTERN}" "${FIO_REPLAY_TRACE}" "${RESULT_DIR}" "${TIME_STAMP}"

# 收集统计信息
if [[ ${PATTERN} != baseline ]]; then
    echo "收集统计信息..."
    ${SPDK_PATH}/scripts/rpc.py bdev_ocf_get_stats CAS1 >> ${RESULT_BASE}/cas_log/${PATTERN}_${FIO_REPLAY_TRACE}_${TIME_STAMP}_CAS1.json
    ${SPDK_PATH}/scripts/rpc.py bdev_get_iostat >> ${RESULT_BASE}/iostat/${PATTERN}_${FIO_REPLAY_TRACE}_${TIME_STAMP}_iostat.json
fi

# 添加测试元数据
echo -e "\n# TEST_METADATA: CACHE_SIZE=${CACHE_SIZE}, TIMESTAMP=${TIME_STAMP}" >> ${FIO_RESULT}

echo "测试完成，结果保存在 ${FIO_RESULT}" 