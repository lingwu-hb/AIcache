#!/bin/bash
# 配置颜色输出
INFO='\e[32m[INFO]\e[0m'
ERROR='\e[31m[ERROR]\e[0m'
WARNING='\e[33m[WARNING]\e[0m'

# Base paths - can be overridden by environment variables
# TODO: 修改为用户主目录
export HOME_PATH=/home/lzq

export SPDK_PATH=${SPDK_PATH:-"${HOME_PATH}/spdk"}
export TRACE_PATH=${TRACE_PATH:-"/home/b00669757/traces"}

# VM configurations
export VM_CONFIG_PATH=${VM_CONFIG_PATH:-"${HOME_PATH}/opencas_vm"}
export VM_BASE_IP="192.168.122"
export VM_START_IP=201
export VM_SSH_PASS="openEuler12#$"

# Storage configurations
export CACHE_DEVICE="nvme0n1"
export CACHE_PCIE="0000:83:00.0"
export RBD_POOL="vmdisk"

# Test configurations
export CACHE_LINE_SIZE=4
export FREE_SYS_MEM=$((200 * 1024 * 1024))
export VM_TYPE="8u16g"
export VM_MEM=16
export CPU_MASK="0x1000000000000000"

# Result paths
export RESULT_BASE_VM="/root/fiotest" # in VM

export RESULT_BASE="${HOME_PATH}/AICache-tools"

export FIO_PATH="${RESULT_BASE}/rawfio"

export CSV_PATH="${RESULT_BASE}/csv"
# export MYLOG= "${SPDK_PATH}/log"


# Verify and create required directories
create_required_dirs() {
    local dirs=(
        "${RESULT_BASE}/rawfio"
        "${RESULT_BASE}/cas_log"
        "${RESULT_BASE}/iostat"
        "${SPDK_PATH}/log"
        "${SPDK_PATH}/trace_log"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
        fi
    done
}

# Verify SPDK installation
verify_spdk() {
    if [ ! -d "${SPDK_PATH}" ]; then
        echo "ERROR: SPDK directory not found at ${SPDK_PATH}"
        return 1
    fi

    if [ ! -f "${SPDK_PATH}/scripts/setup.sh" ]; then
        echo "ERROR: SPDK setup script not found"
        return 1
    fi

    return 0
}

# Verify required tools
verify_tools() {
    local required_tools=(virsh sshpass fio ceph)

    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &>/dev/null; then
            echo "ERROR: Required tool '$tool' is not installed"
            return 1
        fi
    done

    return 0
}

# Print current configuration
print_config() {
    echo -e "${INFO}Current configuration:"
    echo "HOME_PATH: ${HOME_PATH}"
    echo "SPDK_PATH: ${SPDK_PATH}"
    echo "TRACE_PATH: ${TRACE_PATH}"
    echo "VM_CONFIG_PATH: ${VM_CONFIG_PATH}"
    echo "CACHE_DEVICE: ${CACHE_DEVICE}"
    echo "RBD_POOL: ${RBD_POOL}"
}

# Initialize environment
init_env() {
    create_required_dirs
    verify_spdk || exit 1
    verify_tools || exit 1
    print_config
}

# Export helper functions
export -f create_required_dirs
export -f verify_spdk
export -f verify_tools
export -f print_config
export -f init_env
