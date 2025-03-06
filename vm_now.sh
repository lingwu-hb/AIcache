#!/bin/bash
# 手动测试
# 该脚本会启动SPDK和QEMU

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 接管设备
source ${SPDK_HOME}/scripts/setup.sh

# 分配大页
echo 15000 >/sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
echo 5000 >/sys/devices/system/node/node1/hugepages/hugepages-2048kB/nr_hugepages
echo 5000 >/sys/devices/system/node/node2/hugepages/hugepages-2048kB/nr_hugepages
echo 5000 >/sys/devices/system/node/node3/hugepages/hugepages-2048kB/nr_hugepages

sleep 1

cd ${SPDK_HOME}

./scripts/rpc.py log_set_level ERROR
./scripts/rpc.py log_set_print_level ERROR
./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a 0000:83:00.0
./scripts/rpc.py bdev_split_create -s nvme0n1 1
./scripts/rpc.py bdev_rbd_create -b core1 vmdisk vm01 512
./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4
scripts/rpc.py nvmf_create_transport -t VFIOUSER
scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device1 -a -s sys1 -i 1 -I 32760
scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device1 CAS1
rm -rf /var/run/bar0 /var/run/cntrl
scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0

#!/bin/bash
#  手动连入虚拟机（自动修改xml文件，并且退出时修改回来）

set -x
XML_FILE="${VM_CONFIG_PATH}/vm01.xml" # 调整XML文件的目录

sleep 1
#
virsh destroy vm01

# 取消定义
virsh undefine vm01 --nvram

sed -i 's#/var/run/vm01/cntrl#/var/run/cntrl#' "$XML_FILE"

# 定义
virsh define ${VM_CONFIG_PATH}/vm01.xml

# 启动
virsh start vm01

# 把xml修改回脚本可用的
sed -i 's#/var/run/cntrl#/var/run/vm01/cntrl#' "$XML_FILE"
