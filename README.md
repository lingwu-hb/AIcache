1. 停止和清理环境:

/home/lzq/spdk_scripts_replaytrace/stop_vms.sh

2. 单个测试:

/home/lzq/spdk_scripts_replaytrace/vm_now.sh

3. 批量测试:

./run_batch

4. 监控 OCF 状态：

./script/monitor_ocf_stats.py CAS1

## 脚本配置

更新： 使用 config.sh 配置,修改为用户主目录即可

<!--
- [用户主目录路径: ./start_vms_vfio.sh#2](./start_vms_vfio.sh#2) 该脚本需要直接放在用户主目录下

- [结果存放路径:./fio_vm_test.sh](./fio_vm_test.sh#L55)

- [日志和 I/O 统计信息](./fio_vm_test.sh#62)

- [虚拟机 IP](./fio_vm_test.sh#28) -->

## 执行 FIO 测试

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
