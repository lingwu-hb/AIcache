#!/bin/bash
# 配置颜色输出
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 检查参数
if [ $# -lt 7 ]; then
    echo -e "${ERROR} 参数不足"
    echo "Usage: $0 VM_NUM PATTERN FIO_REPLAY_TRACE TARGET_DISK VM_TYPE TEST_TYPE CACHE_SIZE"
    exit 1
fi

VM_NUM=$1
PATTERN=$2          # 定义测试的模式或类型，例如"baseline"或"cache"
FIO_REPLAY_TRACE=$3 # 指定FIO测试的回放轨迹文件，用于模拟实际工作负载
TARGET_DISK=$4      # 指定测试的目标磁盘设备，例如nvme0n1或vda
VM_TYPE=$5          # 定义虚拟机的类型，例如"kvm"或"xen"
TIME_STAMP=$(date "+%m%d_%H%M")
TEST_TYPE=$6 # 定义测试的类型，例如"read"或"write"
CACHE_SIZE=$7

fio_result_log="${RESULT_BASE_VM}/${VM_TYPE}_${PATTERN}_${FIO_REPLAY_TRACE}/${TIME_STAMP}"
# 虚拟机循环
for ((i = 0; i < ${VM_NUM}; i++)); do
    VM_LIST[$i]="vm$(printf "%02d" $(($i + 1)))"
    VM_IP[$i]="${VM_BASE_IP}.$((${VM_START_IP} + i))"
    echo 3 >/proc/sys/vm/drop_caches
    sshpass -p ${VM_SSH_PASS} ssh root@${VM_IP[$i]} "echo 3 > /proc/sys/vm/drop_caches"
    sshpass -p ${VM_SSH_PASS} ssh root@${VM_IP[$i]} "mkdir -p ${fio_result_log}"
    bash ${SCRIPT_DIR}/run_fio_test.sh ${VM_IP[$i]} ${TARGET_DISK} ${PATTERN} ${FIO_REPLAY_TRACE} ${fio_result_log} ${TIME_STAMP} &
done

sleep 10 # 等待fio进程启动

# 轮询等待所有FIO测试结束
echo -e "${INFO} 等待FIO测试完成..."
# 先等待较长时间
sleep 30
# 然后更频繁地检查
while [ $(ps aux | grep "fio_result.log" | grep -v grep | wc -l) -gt 0 ]; do
    sleep 10
    echo -n "."
done
echo

echo -e "${INFO} 从虚拟机复制测试结果到主机"
for ((i = 0; i < ${VM_NUM}; i++)); do
    mkdir -p ${RESULT_BASE}/result/${PATTERN}+${FIO_REPLAY_TRACE}
    sshpass -p ${VM_SSH_PASS} scp -r root@${VM_IP[$i]}:${fio_result_log}/* ${RESULT_BASE}/result/${PATTERN}+${FIO_REPLAY_TRACE}

    # 将 CACHE_SIZE 和时间戳写入每个 FIO 结果文件的末尾
    for result_file in ${RESULT_BASE}/result/${PATTERN}+${FIO_REPLAY_TRACE}/*_fio_result.log; do
        if [ -f "$result_file" ]; then
            echo -e "\n# TEST_METADATA: CACHE_SIZE=${CACHE_SIZE}, TIMESTAMP=${TIME_STAMP}" >>"$result_file"
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

# 环境清理
bash ${SCRIPT_DIR}/stop_vms.sh ${VM_NUM}
echo -e "${INFO} 环境清理完成"
