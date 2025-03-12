# Quick Start

1. 停止和清理环境:
```bash
/home/lzq/AICache-tools/script/stop_vms.sh
```

2. 手动测:


```bash
# 先起SPDK

# 起VM
/home/lzq/AICache-tools/script/vm_now.sh

# 测试
/home/lzq/AICache-tools/script/man_run.sh
```


3. 批量测试:

```bash
/home/lzq/AICache-tools/script/RUN.sh
```

4. 监控 OCF 状态：

./script/monitor_ocf_stats.py CAS1




# 脚本配置

更新： 使用 config.sh 配置,修改为用户主目录即可

<!--
- [用户主目录路径: ./start_vms_vfio.sh#2](./start_vms_vfio.sh#2) 该脚本需要直接放在用户主目录下

- [结果存放路径:./fio_vm_test.sh](./fio_vm_test.sh#L55)

- [日志和 I/O 统计信息](./fio_vm_test.sh#62)

- [虚拟机 IP](./fio_vm_test.sh#28) -->

### 路径

#### 系统路径
- `HOME_PATH`: `/home/lzq` (用户主目录)
- `SPDK_PATH`: `${HOME_PATH}/spdk` (SPDK安装目录)
- `TRACE_PATH`: `/home/b00669757/traces` (测试trace文件目录)

#### 虚拟机配置
- `VM_CONFIG_PATH`: `${HOME_PATH}/opencas_vm` (虚拟机配置文件目录)
- `VM_BASE_IP`: `192.168.122` (虚拟机IP基址)
- 虚拟机运行时目录: `/var/run/vm*`

#### 存储配置
- `CACHE_DEVICE`: `nvme0n1` (缓存设备名)
- `CACHE_PCIE`: `0000:83:00.0` (PCIe设备地址)
- `RBD_POOL`: `vmdisk` (Ceph RBD池名)

#### 日志和结果目录
- SPDK日志: `${SPDK_PATH}/log`
- Trace日志: `${SPDK_PATH}/trace_log`
- FIO测试结果(VM内): `/root/fiotest`
- 收集器目录: `${HOME_PATH}/spdk_fio/collectors`
  - CAS日志: `${COLLECTOR_BASE}/cas_log`
  - IO统计: `${COLLECTOR_BASE}/iostat`
- 测试结果: `${HOME_PATH}/spdk_fio/result`

#### 动态生成的文件
- SPDK日志文件: `${SPDK_PATH}/log/nvmf_${datetime}_${PATTERN}_${FIO_REPLAY_TRACE}.log`
- Trace记录文件: `${SPDK_PATH}/trace_log/spdk_nvmf_record_${datetime}_${PATTERN}_${FIO_REPLAY_TRACE}.trace`

#### 算法库文件
- DAS库路径: `${HOME_PATH}/das-so/${das_so_path}/libdas.so`
- 目标SPDK库路径: `${SPDK_PATH}/libdas.so`

#### 特殊路径说明

##### 虚拟机相关
- VM XML配置文件: `${VM_CONFIG_PATH}/vm[01-99].xml`
- VM运行时目录: `/var/run/vm[01-99]`

##### 系统配置文件
- Hugepages配置: `/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages`
- NUMA节点Hugepages: `/sys/devices/system/node/node[0-3]/hugepages/hugepages-2048kB/nr_hugepages`
- 系统缓存清理: `/proc/sys/vm/drop_caches`


  
#  调用链

- **run_batch.sh**
  - 为每个 trace**start_vms_vfio.sh**
    - 循环启动虚拟机并配置 VFIO 设备
      - 为每个虚拟机分配名称和 IP 地址
        - 虚拟机名称格式：`vmXX`（例如：`vm01`）
        - 虚拟机 IP 地址格式：`192.168.122.20X`（例如：`192.168.122.201`）
      - 清除主机和虚拟机上的缓存
    - **fio_vm_test.sh**
      - 在每个虚拟机上执行 `run_fio_test.sh` 脚本
      - 环境清泪`stop_vms.sh`停止所有虚拟机


