#!/bin/bash
# 配置颜色输出
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 检查参数
if [ $# -lt 4 ]; then
    echo -e "${ERROR} 必须提供VM_NUM、PATTERN、FIO_REPLAY_TRACE和CACHE_SIZE参数"
    echo "Usage: $0 VM_NUM PATTERN FIO_REPLAY_TRACE CACHE_SIZE [TARGET_DISK] [VM_TYPE] [TEST_TYPE]"
    echo "必需参数:"
    echo "  VM_NUM: 虚拟机数量"
    echo "  PATTERN: 测试模式(baseline/cache等)"
    echo "  FIO_REPLAY_TRACE: FIO回放轨迹文件"
    echo "  CACHE_SIZE: 缓存大小(MB)"
    exit 1
fi

# 设置参数
VM_NUM=$1
PATTERN=$2                  # 测试模式(必需)
FIO_REPLAY_TRACE=$3         # FIO回放轨迹文件(必需)
CACHE_SIZE=$4               # 缓存大小(必需)
TARGET_DISK=${5:-"nvme0n1"} # 默认使用nvme0n1作为目标磁盘
VM_TYPE=${6:-"kvm"}         # 默认使用KVM虚拟化
TEST_TYPE=${7:-"read"}      # 默认使用read测试
TIME_STAMP=$(date "+%m%d_%H%M")

fio_result_log="${RESULT_BASE_VM}/${VM_TYPE}_${PATTERN}_${FIO_REPLAY_TRACE}/${TIME_STAMP}"
# 虚拟机循环
for ((i = 0; i < ${VM_NUM}; i++)); do
    VM_LIST[$i]="vm$(printf "%02d" $(($i + 1)))"
    VM_IP[$i]="${VM_BASE_IP}.$((${VM_START_IP} + i))"
    # drop cache
    echo 3 >/proc/sys/vm/drop_caches
    exec_vm "echo 3 > /proc/sys/vm/drop_caches"
    exec_vm "mkdir -p ${fio_result_log}"
    bash ${SCRIPT_DIR}/run_fio_test.sh ${VM_IP[$i]} ${TARGET_DISK} ${PATTERN} ${FIO_REPLAY_TRACE} ${fio_result_log} ${TIME_STAMP}
done
sleep 10 # 等待fio进程启动

# # 轮询等待所有FIO测试结束
# # echo -e "${INFO} 轮询等待所有FIO测试结束..."
# while [ $(ps aux | grep "fio_result.log" | grep -v grep | wc -l) -gt 0 ]; do
#     sleep 10
#     echo -n "."
# done
# echo

# 等待FIO测试完成
echo -e "${INFO} 等待FIO测试完成..."
while true; do
    fio_running=0
    for disk in "${test_disk[@]}"; do
        # 检查FIO进程是否还在运行
        if exec_vm "test -f ${FIO_RESULT_LOG}/${disk}/fio.pid && ps -p \$(cat ${FIO_RESULT_LOG}/${disk}/fio.pid) >/dev/null 2>&1"; then
            fio_running=1
            break
        fi
    done

    if [ $fio_running -eq 0 ]; then
        break
    fi

    sleep 10
    echo -n "."
done

echo -e "${INFO} 复制测试结果到主机..."
for ((i = 0; i < ${VM_NUM}; i++)); do
    mkdir -p ${FIO_PATH}/${PATTERN}+${FIO_REPLAY_TRACE}
    exec_vm "${VM_LIST[$i]}" "cp -r ${fio_result_log}/* ${FIO_PATH}/${PATTERN}+${FIO_REPLAY_TRACE}"

    # 将 CACHE_SIZE 和时间戳写入每个 FIO 结果文件的末尾
    for result_file in ${FIO_PATH}/${PATTERN}+${FIO_REPLAY_TRACE}/*_fio_result.log; do
        if [ -f "$result_file" ]; then
            echo -e "\n# TEST_METADATA: CACHE_SIZE=${CACHE_SIZE}, TIMESTAMP=${TIME_STAMP}" >>"$result_file"
            echo -e "${INFO} FIO结果写入到${result_file}"

        fi
    done
done

# 收集缓存加速存储（CAS）日志和I/O统计
if [[ ${PATTERN} != baseline ]]; then
    echo -e "${INFO} 收集CAS和IO统计信息..."
    # 收集CAS组件的统计信息
    ${SPDK_PATH}/scripts/rpc.py bdev_ocf_get_stats CAS1 >>${RESULT_BASE}/cas_log/${PATTERN}_${FIO_REPLAY_TRACE}_${TIME_STAMP}_CAS1.json &
    # 收集存储设备的I/O统计信息
    ${SPDK_PATH}/scripts/rpc.py bdev_get_iostat >>${RESULT_BASE}/iostat/${PATTERN}_${FIO_REPLAY_TRACE}_${TIME_STAMP}_iostat.json &
fi
