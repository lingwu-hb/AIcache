#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# Command line arguments
VMIP=$1
TARGET_DISK=$2
PATTERN=$3
FIO_REPLAY_TRACE=$4
FIO_RESULT_LOG=$5
TIME_STAMP=$6

# Validate inputs
if [ $# -lt 6 ]; then
    echo "Usage: $0 VMIP TARGET_DISK PATTERN FIO_REPLAY_TRACE FIO_RESULT_LOG TIME_STAMP"
    exit 1
fi

# Initialize environment
init_env

# Determine test disk configuration
if [[ ${TARGET_DISK} == nvme0n1 ]]; then
    test_disk=nvme0n1
    existing_cas=CAS1
elif [[ ${TARGET_DISK} == nvme0n ]]; then
    test_disk=("nvme0n1" "nvme0n2")
elif [[ ${TARGET_DISK} == vda ]]; then
    test_disk=vda
elif [[ ${TARGET_DISK} == vd ]]; then
    test_disk=("vda" "vdb")
else
    echo "unsupported target disk, exit"
    exit 1
fi

# Run FIO tests
for disk in "${test_disk[@]}"; do
    if [[ ${FIO_REPLAY_TRACE} == req ]]; then
        echo "start fio seq test"
        exec_vm "mkdir -p ${FIO_RESULT_LOG}/${disk} && \
            cd ${FIO_RESULT_LOG}/${disk} && \
            fio -filename=/dev/${disk} \
                -direct=1 \
                -bs=4k \
                -iodepth=128 \
                -ioengine=libaio \
                -rw=read \
                -size=10G \
                -name=test \
                -log_avg_msec=10000 \
                -write_bw_log=fiotest \
                -write_lat_log=fiotest \
                -write_iops_log=fiotest \
                -status-interval=1 \
                2>&1 | tee >(nc -l -p 12345) ${FIO_RESULT_LOG}/${disk}/fio_result.log & \
            echo \$! > ${FIO_RESULT_LOG}/${disk}/fio.pid"

        # 在主机端监听输出
        nc localhost 12345 &
    else
        echo "start fio real trace ${FIO_REPLAY_TRACE} replay"
        exec_vm "mkdir -p ${FIO_RESULT_LOG}/${disk} && \
            cd ${FIO_RESULT_LOG}/${disk} && \
            fio -replay_redirect=/dev/${disk} \
                -direct=1 \
                -iodepth=128 \
                -thread \
                -ioengine=libaio \
                --read_iolog=${TRACE_PATH}/${FIO_REPLAY_TRACE} \
                -name=relplay \
                -log_avg_msec=10000 \
                -write_bw_log=fiotest \
                -write_lat_log=fiotest \
                -write_iops_log=fiotest \
                -status-interval=1 \
                2>&1 | tee >(nc -l -p 12345) ${FIO_RESULT_LOG}/${disk}/fio_result.log & \
            echo \$! > ${FIO_RESULT_LOG}/${disk}/fio.pid"

        # 在主机端监听输出
        nc localhost 12345 &
    fi
done

# 等待所有FIO任务完成
for disk in "${test_disk[@]}"; do
    # 等待FIO进程结束
    exec_vm "while kill -0 \$(cat ${FIO_RESULT_LOG}/${disk}/fio.pid) 2>/dev/null; do sleep 1; done"
done

# 打印日志文件位置
echo -e "\n${INFO} FIO测试完成！日志文件位置："
for disk in "${test_disk[@]}"; do
    echo "- ${FIO_RESULT_LOG}/${disk}/fio_result.log (主要结果)"
    echo "  ${FIO_RESULT_LOG}/${disk}/fiotest_bw.log (带宽日志)"
    echo "  ${FIO_RESULT_LOG}/${disk}/fiotest_lat.log (延迟日志)"
    echo "  ${FIO_RESULT_LOG}/${disk}/fiotest_iops.log (IOPS日志)"
done
