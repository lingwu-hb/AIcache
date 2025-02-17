# 启动流程
启动spdk target 
sudo env "LD_LIBRARY_PATH=$PWD/build/lib:$PWD/dpdk/build/lib:$LD_LIBRARY_PATH" build/bin/nvmf_tgt

清理tgt
查找
sudo ps aux | grep nvmf_tgt
杀掉
sudo kill <pid>

配置磁盘
先切root：sudo su root
./scripts/rpc.py log_set_level ERROR

./scripts/rpc.py log_set_print_level ERROR

./scripts/rpc.py bdev_nvme_attach_controller -b nvme0 -t PCIe -a 0000:83:00.0

./scripts/rpc.py bdev_split_create -s 153600 nvme0n1 1 #缓存大小，单位MB

./scripts/rpc.py bdev_rbd_create -b core1 vmdisk vm01 512

./scripts/rpc.py bdev_ocf_create CAS1 wt nvme0n1p0 core1 --cache-line-size 4
scripts/rpc.py nvmf_create_transport -t VFIOUSER

scripts/rpc.py nvmf_create_subsystem nqn.2021-06.io.spdk:ctc_device1 -a -s sys1 -i 1 -I 32760

scripts/rpc.py nvmf_subsystem_add_ns nqn.2021-06.io.spdk:ctc_device1 CAS1
rm -rf /var/run/bar0 /var/run/cntrl

scripts/rpc.py nvmf_subsystem_add_listener nqn.2021-06.io.spdk:ctc_device1 -t VFIOUSER -a /var/run -s 0

启动虚拟机
（root）
virsh start vm01

virsh console vm01
root
openEuler12#$

fio
fio -replay_redirect=/dev/nvme0n1 -direct=1 -iodepth=128 -thread -ioengine=libaio --read_iolog=/home/b00669757/traces/proj_0.txt -name=relplay
在服务端iostat -x 1 看带宽

停止重启
exit
virsh destroy vm01

如果跑脚本要改一个.xml文件
跑脚本：/var/run/vm01/cntrl'/
不跑脚本：/var/run/cntrl'/
