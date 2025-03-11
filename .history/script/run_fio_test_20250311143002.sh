#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 检查参数
if [ $# -lt 6 ]; then
    echo "Usage: $0 HOST TARGET_DEV PATTERN FIO_REPLAY_TRACE RESULT_DIR TIME_STAMP"
    exit 1
fi

HOST=$1           # localhost 或 IP地址
TARGET_DEV=$2     # 目标设备名称
PATTERN=$3        # 测试模式
FIO_REPLAY_TRACE=$4 # FIO回放文件
RESULT_DIR=$5     # 结果目录
TIME_STAMP=$6     # 时间戳

# 确保结果目录存在
mkdir -p ${RESULT_DIR}

# 准备FIO配置
FIO_JOB="${RESULT_DIR}/${TIME_STAMP}_fio.job"
FIO_RESULT="${RESULT_DIR}/${TIME_STAMP}_fio_result.log"

# 生成FIO配置文件
cat > ${FIO_JOB} << EOF
[global]
ioengine=spdk_bdev
spdk_json_conf=${SPDK_PATH}/scripts/bdev.json
thread=1
group_reporting=1
direct=1
verify=0
time_based=0
size=100%
filename=${TARGET_DEV}

[replay]
replay_redirect=${FIO_REPLAY_TRACE}
replay_scale=100
EOF

# 运行FIO测试
if [ "$HOST" = "localhost" ]; then
    # 本地测试
    ${FIO_PATH}/fio ${FIO_JOB} > ${FIO_RESULT} 2>&1
else
    # 远程测试
    sshpass -p ${VM_SSH_PASS} ssh root@${HOST} "${FIO_PATH}/fio ${FIO_JOB} > ${FIO_RESULT} 2>&1"
fi

# 清理临时文件
rm -f ${FIO_JOB}
