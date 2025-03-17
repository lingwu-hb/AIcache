# AICache-tools 使用

## 环境配置

所有路径配置都在 `config.sh` 中，使用前只需修改用户主目录路径即可。
默认已配置 VM 的 SSH 免密登录。

### 关键路径说明

- `HOME_PATH`: 用户主目录，如 `/home/lzq`
- `SPDK_PATH`: SPDK 安装目录，位于 `${HOME_PATH}/spdk`
- `TRACE_PATH`: 测试 trace 文件目录，位于 `/home/b00669757/traces`
- `VM_CONFIG_PATH`: 虚拟机配置目录，位于 `${HOME_PATH}/opencas_vm`
- 测试结果目录: `${HOME_PATH}/spdk_fio/result`

## Quick Start

### 1. 环境准备

```bash
# 停止和清理环境
${HOME_PATH}/AICache-tools/script/stop_vms.sh
```

### 2. 手动测试模式

```bash
# 1. 先启动 SPDK（根据实际环境手动启动）

# 2. 启动虚拟机
${HOME_PATH}/AICache-tools/script/vm_now.sh

# 3. 执行测试
${HOME_PATH}/AICache-tools/script/man_run.sh
```

### 3. 批量测试模式

```bash
# 一键执行批量测试
${HOME_PATH}/AICache-tools/script/RUN.sh
```

### 4. 监控与分析

```bash
# 监控 OCF 状态
${HOME_PATH}/AICache-tools/script/monitor.py CAS1

# 结果比较和分析
# 1. 只生成 CSV 比较结果（自动选择最新两个结果）
./com_res.sh 

# 2. 生成 CSV 和 Excel 格式结果
./com_res.sh -e

# 3. 比较指定的两个结果文件
./com_res.sh -e file1.csv file2.csv
```

## 系统架构

### 虚拟机配置

- 虚拟机命名：`vmXX`（如：`vm01`）
- IP 地址分配：`192.168.122.20X`（如：`192.168.122.201`）
- 配置文件：`${VM_CONFIG_PATH}/vmXX.xml`
- 运行时目录：`/var/run/vmXX`

### 存储配置

- 缓存设备：`nvme0n1`
- PCIe 设备地址：`0000:83:00.0`
- Ceph RBD 池：`vmdisk`

### 日志与结果收集

- SPDK 日志：`${SPDK_PATH}/log`
- Trace 日志：`${SPDK_PATH}/trace_log`
- FIO 测试结果（VM内）：`/root/fiotest`
- 收集器目录：`${HOME_PATH}/spdk_fio/collectors`
  - CAS 日志：`${COLLECTOR_BASE}/cas_log`
  - IO 统计：`${COLLECTOR_BASE}/iostat`

## 脚本调用关系

```
RUN.sh
  ├── start_vms_vfio.sh  # 启动VM并配置VFIO
  │   └── 循环启动虚拟机
  ├── fio_vm_test.sh     # 执行测试
  │   └── run_fio_test.sh（在VM内执行）
  └── stop_vms.sh        # 清理环境
```

# 问题




# 脚本配置

更新： 使用 config.sh 配置,修改为用户主目录即可

VM 配置了 SSH 免密登录

<!--
- [用户主目录路径: ./start_vms_vfio.sh#2](./start_vms_vfio.sh#2) 该脚本需要直接放在用户主目录下

- [结果存放路径:./fio_vm_test.sh](./fio_vm_test.sh#L55)

- [日志和 I/O 统计信息](./fio_vm_test.sh#62)

- [虚拟机 IP](./fio_vm_test.sh#28) -->






### 路径

#### 系统路径

- `HOME_PATH`: `/home/lzq` (用户主目录)
- `SPDK_PATH`: `${HOME_PATH}/spdk` (SPDK 安装目录)
- `TRACE_PATH`: `/home/b00669757/traces` (测试 trace 文件目录)

#### 虚拟机配置

- `VM_CONFIG_PATH`: `${HOME_PATH}/opencas_vm` (虚拟机配置文件目录)
- `VM_BASE_IP`: `192.168.122` (虚拟机 IP 基址)
- 虚拟机运行时目录: `/var/run/vm*`

#### 存储配置

- `CACHE_DEVICE`: `nvme0n1` (缓存设备名)
- `CACHE_PCIE`: `0000:83:00.0` (PCIe 设备地址)
- `RBD_POOL`: `vmdisk` (Ceph RBD 池名)

#### 日志和结果目录

- SPDK 日志: `${SPDK_PATH}/log`
- Trace 日志: `${SPDK_PATH}/trace_log`
- FIO 测试结果(VM 内): `/root/fiotest`
- 收集器目录: `${HOME_PATH}/spdk_fio/collectors`
  - CAS 日志: `${COLLECTOR_BASE}/cas_log`
  - IO 统计: `${COLLECTOR_BASE}/iostat`
- 测试结果: `${HOME_PATH}/spdk_fio/result`

#### 动态生成的文件

- SPDK 日志文件: `${SPDK_PATH}/log/nvmf_${datetime}_${PATTERN}_${FIO_REPLAY_TRACE}.log`
- Trace 记录文件: `${SPDK_PATH}/trace_log/spdk_nvmf_record_${datetime}_${PATTERN}_${FIO_REPLAY_TRACE}.trace`

#### 算法库文件

- DAS 库路径: `${HOME_PATH}/das-so/${das_so_path}/libdas.so`
- 目标 SPDK 库路径: `${SPDK_PATH}/libdas.so`

#### 特殊路径说明

##### 虚拟机相关

- VM XML 配置文件: `${VM_CONFIG_PATH}/vm[01-99].xml`
- VM 运行时目录: `/var/run/vm[01-99]`

##### 系统配置文件

- Hugepages 配置: `/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages`
- NUMA 节点 Hugepages: `/sys/devices/system/node/node[0-3]/hugepages/hugepages-2048kB/nr_hugepages`
- 系统缓存清理: `/proc/sys/vm/drop_caches`

# 调用链

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
