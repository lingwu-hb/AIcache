* 脚本代码

```bash
# 清理与 Ceph 相关的卷组
vgs | grep ceph | awk '{print $1}' | xargs vgremove -y

# 格式化和清零磁盘（避开 sdd 和 sdf）
for i in {b..c} {e} {g..m}; do
    (echo y | mkfs -t ext4 /dev/sd${i}; dd if=/dev/zero of=/dev/sd${i} bs=1M count=500 conv=fsync) &
done
wait

# 格式化和清零 NVMe 磁盘分区
for i in {1..24}; do
    (echo y | mkfs -t ext4 /dev/nvme0n1p${i}; dd if=/dev/zero of=/dev/nvme0n1p${i} bs=1M count=500 conv=fsync) &
done
wait

# 创建 Ceph OSD
for node in ceph1
do
    j=1
    k=2
    for i in {b..c} {e} {g..m}
    do
        ceph-deploy osd create ${node} --data /dev/sd${i} --block-wal /dev/nvme0n1p${j} --block-db /dev/nvme0n1p${k}
        ((j=${j}+2))
        ((k=${k}+2))
        sleep 3
    done
done
```