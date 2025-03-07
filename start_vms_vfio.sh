#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# Command line arguments
VM_NUM=$1
PATTERN=$2
FIO_REPLAY_TRACE=$3
CACHE_SIZE=$4

# Validate inputs
if [ $# != 4 ]; then
    echo "Usage: $0 VM_NUM PATTERN FIO_REPLAY_TRACE CACHE_SIZE"
    echo "  VM_NUM: Number of VMs to start (1 or 5)"
    echo "  PATTERN: Test pattern (baseline/ocf_nopf/ocf_das/etc.)"
    echo "  FIO_REPLAY_TRACE: FIO replay trace file"
    echo "  CACHE_SIZE: Cache size in MB"
    exit 1
fi

# Initialize environment
init_env &>/dev/null

echo -e "${INFO} 检查..."
# 检查是否已经有SPDK进程
if pgrep -f "nvmf_tgt" >/dev/null; then
    echo -e "${ERROR} SPDK进程已存在"
    exit 1
fi

# 检查是否有正在运行的测试虚拟机
if virsh list | grep -q "vm0"; then
    echo -e "${ERROR} 存在运行中的测试虚拟机"
    exit 1
fi

# Validate VM number
if [[ ${VM_NUM} -ne 1 && ${VM_NUM} -ne 5 ]]; then
    echo -e "${ERROR} Invalid VM_NUM. Allowed values are 1 and 5."
    exit 1
fi

# Calculate cache partition size
if [[ ${VM_NUM} == 1 ]]; then
    CACHE_PARTITION=${CACHE_SIZE}
elif [[ ${VM_NUM} == 5 ]]; then
    CACHE_PARTITION=$((CACHE_SIZE * VM_NUM * 2))
fi

# Check if cache device is system disk
if echo "pvs" | grep -q "\<${CACHE_DEVICE}\>"; then
    echo -e "${ERROR} ${CACHE_DEVICE} is the system installation disk"
    exit 1
fi

# Sync time
systemctl stop ntpd
ntpdate ceph1
hwclock -w

# Ceph 状态检查（只输出错误）
ceph_status=$(ceph -s 2>/dev/null)
if [[ $ceph_status == *"HEALTH_ERR"* ]]; then
    echo -e "${ERROR} Cluster health check failed"
    exit 1
fi

# Prepare libdas.so based on pattern
echo -e "${INFO} 根据算法模式（PATTERN）准备库文件..."
if [[ ${PATTERN} != baseline ]]; then
    das_so_path=""
    case ${PATTERN} in
    ocf_nopf) das_so_path="no_prefetch" ;;
    ocf_seq) das_so_path="seq" ;;
    ocf_seq_large) das_so_path="seq_large" ;;
    ocf_seq_self) das_so_path="seq_self" ;;
    seq_512) das_so_path="seq_512-512" ;;
    seq_64_512) das_so_path="seq_64-512" ;;
    seq_4reqlen) das_so_path="seq_4reqlen" ;;
    seq_4reqlen_bind) das_so_path="seq_4reqlen_bind" ;;
    var_max) das_so_path="var_max" ;;
    fix_max_512) das_so_path="fix_max_512" ;;
    fix_max_64) das_so_path="fix_max_64" ;;
    no_prefetch) das_so_path="das-final-test/no_prefetch" ;;
    das-ori) das_so_path="das-final-test/das-ori" ;;
    das-bind) das_so_path="das-final-test/das-bind" ;;
    das-bind-adaptive) das_so_path="das-final-test/das-bind-adaptive" ;;
    das-bind-adaptive-64k) das_so_path="das-final-test/das-bind-adaptive-64k" ;;
    das-bind-adaptive-64k-feedback) das_so_path="das-final-test/das-bind-adaptive-64k-feedback" ;;
    das-bind-adaptive-64k-feedback-distance) das_so_path="das-final-test/das-bind-adaptive-64k-feedback-distance" ;;
    belief_io) das_so_path="belief_io" ;;
    belief_page) das_so_path="belief_page" ;;
    belief_ori) das_so_path="belief_ori" ;;
    belief_io_*) das_so_path="belief/belief_io_${PATTERN#belief_io_}" ;;
    belief_page_*) das_so_path="belief/belief_page_${PATTERN#belief_page_}" ;;
    das_belief) das_so_path="das_belief" ;;
    seq_8) das_so_path="seq_8" ;;
    seq_64_256) das_so_path="seq_64_256" ;;
    *)
        echo "Unknown pattern: ${PATTERN}"
        exit 1
        ;;
    esac
    cp ${HOME_PATH}/das-so/${das_so_path}/libdas.so ${SPDK_PATH}/
fi

# SPDK setup
echo -e "${INFO} SPDK preparing..."
${SPDK_PATH}/scripts/setup.sh cleanup &>/dev/null
sleep 2
${SPDK_PATH}/scripts/setup.sh reset &>/dev/null
sleep 2
${SPDK_PATH}/scripts/setup.sh &>/dev/null
sleep 2
${SPDK_PATH}/scripts/setup.sh status

# Configure hugepages
echo 0 >/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
echo 3 >/proc/sys/vm/drop_caches

_vm_mem=$((${VM_NUM} * ${VM_MEM} * 1024 * 1024))
_pg_num=610000
_single_vm_pg=20000

if [[ ${_vm_mem} -lt ${FREE_SYS_MEM} ]]; then
    if [[ ${VM_NUM} == 1 ]]; then
        for node in node0 node1 node2 node3; do
            echo 15000 >"/sys/devices/system/node/${node}/hugepages/hugepages-2048kB/nr_hugepages"
        done
    elif [[ ${VM_NUM} == 5 ]]; then
        for node in node0 node1; do
            echo ${_pg_num} >"/sys/devices/system/node/${node}/hugepages/hugepages-2048kB/nr_hugepages"
        done
        for node in node2 node3; do
            echo ${_single_vm_pg} >"/sys/devices/system/node/${node}/hugepages/hugepages-2048kB/nr_hugepages"
        done
    fi
else
    echo "VM capacity exceeds system memory. Huge page allocation failed."
    exit 1
fi

# 输出当前测试的配置信息
echo -e "${INFO} ==================== Test Configuration ===================="
echo -e "${INFO} Pattern:     ${PATTERN}"
echo -e "${INFO} Trace File:  ${FIO_REPLAY_TRACE}"
echo -e "${INFO} Cache Size:  ${CACHE_SIZE}MB"
echo -e "${INFO} VM Count:    ${VM_NUM}"
echo -e "${INFO} Cache Part:  ${CACHE_PARTITION}MB"
echo -e "${INFO} ======================================================"

# spdk/vfiouser process starting
mkdir -p ${RESULT_BASE}/log
datetime=$(date "+%m%d_%H%M")
nqnuuid=$(date "+%H%M")

#LD_PRELOAD=/usr/lib/gcc/aarch64-linux-gnu/7.3.0/libasan.so

#-e enable record trace
cd ${SPDK_PATH} && LD_LIBRARY_PATH=${SPDK_PATH}/build/lib:${SPDK_PATH}/dpdk/build/lib:./ ${SPDK_PATH}/build/bin/nvmf_tgt -e vbdev_ocf >${RESULT_BASE}/log/nvmf_${datetime}_${PATTERN}_${FIO_REPLAY_TRACE}.log 2>&1 & # core 60-63
#cd ${SPDK_HOME} &&  LD_LIBRARY_PATH=build/lib:dpdk/build/lib:./ build/bin/nvmf_tgt -m ${CPU_MASK} -e vbdev_ocf > log/nvmf_${datetime}_${PATTERN}_${FIO_REPLAY_TRACE}.log 2>&1 & # core 60-63
sleep 5

# #record trace
# mkdir -p ${SPDK_PATH}/trace_log
# spdk_pid=$(ps aux | grep nvmf_tgt | grep -v grep | awk '{print $2}')
# cd ${SPDK_PATH} && LD_LIBRARY_PATH=${SPDK_PATH}/build/lib:${SPDK_PATH}/dpdk/build/lib:./ ${SPDK_PATH}/build/bin/spdk_trace_record -q -s nvmf -p ${spdk_pid} -f ${SPDK_PATH}/trace_log/spdk_nvmf_record_${datetime}_${PATTERN}_${FIO_REPLAY_TRACE}.trace &

${SPDK_PATH}/scripts/rpc.py log_set_level ERROR
#./scripts/rpc.py log_set_level ERROR
${SPDK_PATH}/scripts/rpc.py log_set_print_level ERROR
#./scripts/rpc.py log_set_print_level ERROR
${SPDK_PATH}/scripts/rpc.py nvmf_create_transport -t VFIOUSER

# cache partitions preparing
if [[ ${PATTERN} == baseline ]]; then
    echo " there is no need for nvme partitions "
else
    ${SPDK_PATH}/scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a ${CACHE_PCIE}
    ${SPDK_PATH}/scripts/rpc.py bdev_split_create -s ${CACHE_PARTITION} nvme0n1 1
fi

# vm ip config adn test routine list
rm -rf /var/run/vm*
for ((i = 0; i < ${VM_NUM}; i++)); do
    VM_LIST[$i]="vm$(printf "%02d" $(($i + 1)))"
    VM_IP[$i]="${VM_BASE_IP}.$((201 + i))"
    # bdev preparing
    if [[ ${VM_NUM} == 5 ]]; then
        mkdir -p /var/run/${VM_LIST[$i]}
        ${SPDK_PATH}/scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device$((i + 1)) -a -s sys$((i + 1)) -i 1 -I 32760
        ${SPDK_PATH}/scripts/rpc.py bdev_rbd_create -b core$((2 * ($i + 1) - 1)) ${RBD_POOL} vm$(printf "%02d" $((2 * ($i + 1) - 1))) 512
        ${SPDK_PATH}/scripts/rpc.py bdev_rbd_create -b core$((2 * (i + 1))) ${RBD_POOL} vm$(printf "%02d" $((2 * ($i + 1)))) 512
        if [[ ${PATTERN} == das ]]; then
            ${SPDK_PATH}/scripts/rpc.py bdev_ocf_create CAS$((2 * ($i + 1) - 1)) wt ${CACHE_DEVICE}p0 core$((2 * (i + 1) - 1)) --cache-line-size ${CACHE_LINE_SIZE}
            sleep 30
            ${SPDK_PATH}/scripts/rpc.py bdev_ocf_create CAS$((2 * (i + 1))) wt ${CACHE_DEVICE}p0 core$((2 * (i + 1))) --cache-line-size ${CACHE_LINE_SIZE}
            sleep 30
            ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device$((i + 1)) CAS$((2 * (i + 1) - 1))
            ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device$((i + 1)) CAS$((2 * (i + 1)))
        elif [[ ${PATTERN} == baseline ]]; then
            ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device$((i + 1)) core$((2 * (i + 1) - 1))
            ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device$((i + 1)) core$((2 * (i + 1)))
        else
            echo -e "${ERROR} unsupport test pattern, exit"
            exit 1
        fi
        ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device$((i + 1)) -t VFIOUSER -a /var/run/${VM_LIST[$i]} -s 0
    elif [[ ${VM_NUM} == 1 ]]; then
        mkdir -p /var/run/${VM_LIST[$i]}
        ${SPDK_PATH}/scripts/rpc.py nvmf_create_subsystem nqn.2023-11.io.spdk:node${nqnuuid}$((i + 1)) -a -s sys$((i + 1)) -i 1 -I 32760
        ${SPDK_PATH}/scripts/rpc.py bdev_rbd_create -b core$((i + 1)) ${RBD_POOL} vm01 512
        sleep 3
        if [[ ${PATTERN} == baseline ]]; then
            ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-11.io.spdk:node${nqnuuid}$((i + 1)) core$((i + 1))
        else
            ${SPDK_PATH}/scripts/rpc.py bdev_ocf_create CAS$((i + 1)) wt nvme0n1p0 core$((i + 1)) --cache-line-size ${CACHE_LINE_SIZE}
            echo -e "${INFO} wait for bdev_ocf_create"
            sleep 30 # make sure bdev_ocf_create DONE !
            ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-11.io.spdk:node${nqnuuid}$((i + 1)) CAS$((i + 1))
        fi
        ${SPDK_PATH}/scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-11.io.spdk:node${nqnuuid}$((i + 1)) -t VFIOUSER -a /var/run/${VM_LIST[$i]} -s 0
    fi
    # start vm
    virsh define ${VM_CONFIG_PATH}/${VM_LIST[$i]}.xml
    echo 3 >/proc/sys/vm/drop_caches
    virsh start ${VM_LIST[$i]}
done

# 等待虚拟机启动并检查SSH连接
echo -e "${INFO} 等待虚拟机启动..."
# sleep 60 # 基础等待时间

# # Wait for VMs to be ready
# for ((j = 0; j < ${#VM_LIST[@]}; j++)); do
#     max_attempts=20
#     attempt=1
#     while [[ $attempt -le $max_attempts ]]; do
#         if sshpass -p "${VM_SSH_PASS}" ssh -o ConnectTimeout=2 root@${VM_IP[$j]} "echo ssh_login_success"; then
#             echo -e "${INFO} VM ${VM_LIST[$j]} ssh login success"
#             break
#         else
#             attempt=$((attempt + 1))
#             sleep 5
#         fi
#     done
#     if [[ $attempt -gt $max_attempts ]]; then
#         echo -e "${ERROR} VM ${VM_LIST[$j]} ssh login failed"

# 循环检查直到所有VM都就绪
for ((i = 0; i < ${VM_NUM}; i++)); do
    while true; do
        if sshpass -p "${VM_SSH_PASS}" ssh -o ConnectTimeout=2 root@${VM_IP[$i]} "exit" 2>/dev/null; then
            echo -e "${INFO} VM ${VM_LIST[$i]} 已就绪"
            break
        fi
        echo -n "."
        sleep 2
    done
done
echo

# Start FIO test
if [[ ${VM_NUM} == 5 ]]; then
    bash ${SCRIPT_DIR}/fio_vm_test.sh ${VM_NUM} ${PATTERN} nvme0n ${VM_TYPE} ${FIO_BS} ${FIO_RW} vfio ${CACHE_SIZE}
else
    bash ${SCRIPT_DIR}/fio_vm_test.sh ${VM_NUM} ${PATTERN} ${FIO_REPLAY_TRACE} nvme0n1 ${VM_TYPE} vfio ${CACHE_SIZE}
fi
