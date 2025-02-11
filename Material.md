* 脚本代码

```bash
vgs | grep ceph | awk '{print $1}' | xargs vgremove -y
for i in {b..m}; do (echo y | mkfs -t ext4 /dev/sd${i}; dd if=/dev/zero of=/dev/sd${i} bs=1M count=500 conv=fsync)& done; wait
for i in {1..24}; do (echo y | mkfs -t ext4 /dev/nvme0n1p${i}; dd if=/dev/zero of=/dev/nvme0n1p${i} bs=1M count=500 conv=fsync)& done; wait

for node in ceph1
do
j=1
k=2
for i in {b..m}
do
ceph-deploy osd create ${node} --data /dev/sd${i} --block-wal /dev/nvme0n1p${j} --block-db /dev/nvme0n1p${k}
((j=${j}+2))
((k=${k}+2))
sleep 3

done
done
```

