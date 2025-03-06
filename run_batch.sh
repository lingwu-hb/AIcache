#!/bin/bash
# 配置颜色输出
INFO='\e[32m[INFO]\e[0m'
ERROR='\e[31m[ERROR]\e[0m'
WARNING='\e[33m[WARNING]\e[0m'
VM_NUM=$1
PATTERN=$2                      # PATTERN：定义测试的模式或类型，例如"baseline"或"cache"。
FIO_REPLAY_TRACE=$3             # FIO_REPLAY_TRACE：指定FIO测试的回放轨迹文件，用于模拟实际工作负载。
TARGET_DISK=$4                  # TARGET_DISK：指定测试的目标磁盘设备，例如nvme0n1或vda。
VM_TYPE=$5                      # VM_TYPE：定义虚拟机的类型，例如"kvm"或"xen"。
TIME_STAMP=$(date "+%m%d_%H%M") # TIME_STAMP：生成当前时间戳，用于测试结果文件的命名，格式为%m%d_%H%M。
HOME_PATH=/home/lzq             # HOME_PATH：用户主目录的路径，例如/home/lzq。
SPDK_HOME=${HOME_PATH}/spdk     # SPDK_HOME：SPDK工具的安装路径，例如${HOME_PATH}/spdk。
TEST_TYPE=$6                    # TEST_TYPE：定义测试的类型，例如"read"或"write"。
CACHE_SIZE=$7

# WARM_UP_SEC=300
# RUN_SEC=600

fio_result_log="/root/fiotest/${VM_TYPE}_${PATTERN}_${FIO_REPLAY_TRACE}/${TIME_STAMP}"
for ((i = 0; i < ${VM_NUM}; i++)); do
	VM_LIST[$i]="vm$(printf "%02d" $(($i + 1)))"
	VM_IP[$i]="192.168.122.$((201 + i))"
	#	ssh root@${VM_LIST[$i]} "mkfs.ext4 ${TARGET_DISK}"
	echo 3 >/proc/sys/vm/drop_caches
	sshpass -p openEuler12#$ ssh root@${VM_IP[$i]} "echo 3 > /proc/sys/vm/drop_caches"
	sshpass -p openEuler12#$ ssh root@${VM_IP[$i]} "mkdir -p ${fio_result_log}"
	bash ${HOME_PATH}/spdk_scripts_replaytrace/run_fio_test.sh ${VM_IP[$i]} ${TARGET_DISK} ${PATTERN} ${FIO_REPLAY_TRACE} ${fio_result_log} ${TIME_STAMP} &
done

sleep 10 # 等待fio进程跑起来

# 轮询等待所有FIO测试结束
fio_test_numjobs=$(ps aux | grep "fio_result.log" | grep -v grep | wc -l)
while [ $fio_test_numjobs -gt 0 ]; do
	#sleep $(($WARM_UP_SEC+$RUN_SEC-50))
	sleep 30
	fio_test_numjobs=$(ps aux | grep "fio_result.log" | grep -v grep | wc -l)
	while [ $fio_test_numjobs -gt 0 ]; do
		sleep 10
		fio_test_numjobs=$(ps aux | grep "fio_result.log" | grep -v grep | wc -l)
	done
done
echo -e "${INFO}fio test finished"

echo -e "${INFO}从虚拟机复制测试结果到主机"
for ((i = 0; i < ${VM_NUM}; i++)); do
	mkdir -p ${HOME_PATH}/spdk_fio/result/${PATTERN}+${FIO_REPLAY_TRACE}
	sshpass -p openEuler12#$ scp -r root@${VM_IP[$i]}:${fio_result_log}/* ${HOME_PATH}/spdk_fio/result/${PATTERN}+${FIO_REPLAY_TRACE}
done

# 收集缓存加速存储（CAS）日志和I/O统计
COLLECTOR_DIR=${HOME_PATH}/spdk_fio/collectors
mkdir -p ${COLLECTOR_DIR}/cas_log
mkdir -p ${COLLECTOR_DIR}/iostat

existing_cas=CAS1
if [[ ${PATTERN} != baseline ]]; then
	for cas in "${existing_cas[@]}"; do
		# 收集CAS组件的统计信息
		${SPDK_HOME}/scripts/rpc.py bdev_ocf_get_stats ${cas} >>${COLLECTOR_DIR}/cas_log/${PATTERN}_${FIO_REPLAY_TRACE}_${TIME_STAMP}_${cas}.json &
	done
	# 收集存储设备的I/O统计信息
	${SPDK_HOME}/scripts/rpc.py bdev_get_iostat >>${COLLECTOR_DIR}/iostat/${PATTERN}_${FIO_REPLAY_TRACE}_${TIME_STAMP}_iostat.json &
fi

## env clean
bash ${HOME_PATH}/spdk_scripts_replaytrace/stop_vms.sh ${VM_NUM}
echo "env clean-up completed"
