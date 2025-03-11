#!/bin/bash
# 优化的批量测试脚本，避免为每个trace重启虚拟机
# 使用热插拔方式重载SPDK磁盘

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 测试trace配置
replay_trace_config=(
    "ali-dev-5.txt 91"
    "hm_0.txt 96"
    "mds_1.txt 4300"
    "prn_0.txt 193"
    "proj_0.txt 91"
    "proj_3.txt 270"
    "prxy_0.txt 63"
    "rsrch_0.txt 17"
    "rsrch_2.txt 68"
    "src1_2.txt 81"
    "src2_0.txt 41"
    "src2_1.txt 981"
    "src2_2.txt 1040"
    "stg_1.txt 4075"
    "ts_0.txt 51"
    "usr_0.txt 109"
    "wdev_0.txt 41"
    "web_0.txt 369"
    "web_1.txt 188"
    "web_3.txt 46"
    "prn_1.txt 3779"
    "web_2.txt 3440"
    # "proj_2.txt 20990"
    # "ali-dev-3.txt 8200"
)

# 算法配置
algo_config=(
    "das-bind"
    "no-prefetch"
    # 可以根据需要添加更多的算法
)

# 虚拟机数量
VM_COUNT=1

# 日志设置
log_file="${RESULT_BASE}/batch_run_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$log_file") 2>&1

echo "===== 批量测试开始 $(date) ====="

# 获取第一个trace和缓存大小用于初始启动
read -r first_trace first_cache <<<"${replay_trace_config[0]}"

# 启动虚拟机并计时
echo "start_vms_vfio.sh..."
start_time=$(date +%s)
${SCRIPT_DIR}/start_vms_vfio.sh $VM_COUNT "${algo_config[0]}" "$first_trace" "$first_cache"

# 等待VM就绪
vm_ip="${VM_BASE_IP}.$((200 + 1))"
while ! sshpass -p "${VM_SSH_PASS}" ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no root@${vm_ip} "exit" 2>/dev/null; do
    elapsed=$(($(date +%s) - start_time))
    echo -ne "\r等待VM就绪... ${elapsed}秒"
    sleep 2
done
echo -e "\nVM已就绪，用时${elapsed}秒"

# 标记第一次运行
first_run=true

# 算法循环
for algo in "${algo_config[@]}"; do
    echo "===== 测试算法: $algo ====="

    # Trace循环
    for replay_trace in "${replay_trace_config[@]}"; do
        # 解析trace和缓存大小
        read -r trace_file cache_size <<<"$replay_trace"
        echo "===== 测试: $trace_file (缓存: $cache_size) ====="

        # 对于首次运行，不需要重载磁盘（因为start_vms_vfio.sh已经配置好了）
        if [ "$first_run" != "true" ]; then
            echo "重载SPDK磁盘..."
            python3 ${SCRIPT_DIR}/reload_spdk_disk.sh --cache-size "$cache_size" --vm-ids "$VM_COUNT"
            if [ $? -ne 0 ]; then
                echo "重载磁盘失败，跳过此trace"
                continue
            fi
        else
            first_run=false
        fi

        # 执行FIO测试
        echo "执行FIO测试..."
        ${SCRIPT_DIR}/fio_vm_test.sh "$algo" "$trace_file" "$cache_size"
        test_status=$?

        # 清理缓存
        echo "清理缓存..."
        echo 3 >/proc/sys/vm/drop_caches

        # 为每个VM清理缓存
        for ((i = 1; i <= VM_COUNT; i++)); do
            sshpass -p "${VM_SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${VM_BASE_IP}.$((200 + i)) "echo 3 > /proc/sys/vm/drop_caches"
        done

        sleep 3
    done
done

# 测试完成后停止虚拟机
echo "所有测试完成，停止虚拟机..."
${SCRIPT_DIR}/../stop_vms.sh

# 生成测试报告
if [[ -x "${SCRIPT_DIR}/parse_fio.py" ]]; then
    echo "生成测试报告..."
    python3 ${SCRIPT_DIR}/parse_fio.py
fi

echo "===== 批量测试结束 $(date) ====="
