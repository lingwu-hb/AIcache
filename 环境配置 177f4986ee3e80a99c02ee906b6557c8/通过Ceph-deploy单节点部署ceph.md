# 通过Ceph-deploy在单机部署Ceph

本文档介绍如何在单机环境下使用ceph-deploy工具部署Ceph集群。主要包含以下核心步骤：

## **目录**

1. 环境准备
2. 基础配置
3. Monitor节点部署
4. 存储资源准备
    - 物理硬盘状态
    - LVM配置
    - LVM空间调整
5. 集群组件部署
    - MGR节点部署
    - OSD节点部署
6. RGW节点部署

## **1. 环境准备**

### **1.1 检查主机名**

```bash
hostname
# 输出: AICache-3
```

### **1.2 创建工作目录**

```bash
mkdir -p ~/Proj/ceph-mycluster
cd ~/Proj/ceph-mycluster

```

### **1.3 检查网络配置**

```bash
ip a
# 注意查看网络接口的IP地址和掩码长度# 本例中：173.71.3.3/18# 注意：之前的部署文档中提到掩码长度是/23，但当前环境是/18# 在配置时应以实际检查到的掩码长度为准
```

### **1.4 清理已存在配置**

如果是重新部署，需要清理已存在的配置：

```bash
sudo rm -rf /etc/ceph/* /var/lib/ceph/* /var/run/ceph/*

```

## **2. 基础配置**

### **2.1 创建集群配置**

```bash
# 注意：不要使用sudo，否则生成的文件权限会有问题
ceph-deploy new AICache-3

```

生成的文件：

- `ceph.conf`：集群配置文件
- `ceph.mon.keyring`：monitor密钥文件
- `ceph-deploy-ceph.log`：部署日志

### **2.2 修改网络配置**

在 `ceph.conf` 中添加网络配置：

```
[global]# ... 已有配置 ...public_network = 173.71.0.0/18  # 使用实际检查到的掩码长度

```

**注意事项：**

- 使用 IPv4 地址进行配置
- 网络配置时必须注意掩码长度：
    - 每次部署前都要使用 `ip a` 检查实际的网络接口掩码长度
    - 不要直接使用历史文档中的配置，因为网络配置可能发生变化
    - 在所有网络相关配置中保持掩码长度一致

## **3. Monitor节点部署**

### **3.1 初始化监视器**

```bash
# 如果遇到配置文件已存在的错误，使用 --overwrite-conf 参数
ceph-deploy --overwrite-conf mon create-initial

```

### **3.2 配置管理密钥**

```bash
# 将admin密钥复制到系统配置目录
ceph-deploy admin AICache-3

# 设置正确的权限sudo chmod 644 /etc/ceph/ceph.client.admin.keyring
sudo chmod 644 /etc/ceph/ceph.conf

```

**权限问题解决方案：**

如果遇到权限问题，可以将密钥环文件复制到用户目录：

```bash
sudo cp /etc/ceph/ceph.client.admin.keyring ~/
sudo chown $USER:$USER ~/ceph.client.admin.keyring
export CEPH_KEYRING=~/ceph.client.admin.keyring

```

## **4. 存储资源准备**

### **4.1 物理硬盘状态**

```bash
lsblk

```

当前硬盘配置：

- sda: 894.3G (系统盘)
    - sda1: 600M (/boot/efi)
    - sda2: 1G (/boot)
    - sda3: 892.7G (LVM)
- sdb: 894.3G (整个硬盘作为LVM成员)
- sdc: 894.3G (整个硬盘作为LVM成员)
- sdd: 894.3G (整个硬盘作为LVM成员)
- sde: 3.6T (整个硬盘作为LVM成员)

### **4.2 LVM配置**

```bash
sudo pvs && sudo vgs && sudo lvs

```

**物理卷(PV)状态：**

- /dev/sda3: 892.66G (系统盘)
- /dev/sdb1: 894.25G
- /dev/sdc1: 894.25G
- /dev/sdd1: 894.25G
- /dev/sde1: 3.64T

**卷组(VG)状态：**

- openeuler_hostname-0oncl
    - 总大小: 7.13T
    - 剩余空间: 0
    - 包含5个PV，3个LV
        1. home: 7.06T
        2. root: 70G
        3. swap: 4G

### **4.3 LVM空间调整**

> ⚠️ 危险操作，请严格遵循：备份 -> 卸载 -> 缩减文件系统 -> 缩减逻辑卷 -> 移动数据 -> 移除物理卷
> 

### **4.3.1 缩减 /home 逻辑卷**

```bash
# 1. 卸载 /home 目录（需要先终止所有使用该目录的进程）sudo umount /home

# 2. 检查文件系统sudo e2fsck -f /dev/openeuler_hostname-0oncl/home

# 3. 缩减文件系统和逻辑卷sudo lvreduce -L 890G -r /dev/openeuler_hostname-0oncl/home

# 4. 重新挂载sudo mount /dev/openeuler_hostname-0oncl/home /home

```

### **4.3.2 移除SSD物理卷**

```bash
# 移除第一块SSDsudo vgreduce openeuler_hostname-0oncl /dev/sdb1
sudo pvremove /dev/sdb1

# 移除第二块SSDsudo vgreduce openeuler_hostname-0oncl /dev/sdc1
sudo pvremove /dev/sdc1

# 移除第三块SSDsudo vgreduce openeuler_hostname-0oncl /dev/sdd1
sudo pvremove /dev/sdd1

```

### **4.3.3 调整HDD盘**

> ⚠️ 危险操作，要严格确保文件系统末端在1.6TB之前
> 

```bash
# 1. 缩小物理卷sudo pvresize --setphysicalvolumesize 1.6T /dev/sde1

# 2. 调整分区大小sudo parted /dev/sde
(parted) resizepart 1 1.6TB
(parted) mkpart primary 1.6TB 2.6TB
(parted) mkpart primary 2.6TB 3.6TB
(parted) quit

```

## **5. 继续集群组件部署**

### **5.1 MGR节点部署**

管理器（Manager，MGR）是Ceph集群的监控系统，主要功能包括：

- 指标采集和存储
- 数据分析和报警
- 监控可视化
- 集群指标对外暴露

### **5.1.1 部署步骤**

```bash
# 在工作目录下执行cd ~/Proj/ceph-mycluster
ceph-deploy mgr create AICache-3

```

验证部署

```bash
ceph -s

```

预期输出：

```
cluster:
  id:     [集群ID]
  health: HEALTH_OK

services:
  mon: 1 daemons, quorum AICache-3
  mgr: AICache-3(active, since [时间])

```

### **5.2 OSD节点部署**

OSD（Object Storage Daemon）是Ceph集群的存储节点，负责数据的实际存储。为了优化性能，我们将：

- 在SSD上创建WAL和DB分区：
    - WAL分区：60GB（用于Write-Ahead Log，提高写入性能）
    - DB分区：180GB（用于存储OSD元数据）
- 在HDD上创建数据分区：
    - 数据分区：1TB（用于存储实际数据）

### **5.2.1 清除磁盘数据**

首先需要在SSD上创建所需的分区：

```bash
# 使用parted创建分区sudo parted /dev/sdb
(parted) mklabel gpt
(parted)# WAL分区：60GB(parted) mkpart primary 60GB 240GB# DB分区：180GB(parted) quit
# 题外话: 在 GPT 分区表中，primary 只是一个占位符，# 没有实际意义。你可以用任何名字，比如 data、wal、db，甚至直接省略。
```

![https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-4.png](https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-4.png)

然后清除这些分区上的旧数据：

```bash
# 清除WAL分区sudo ceph-deploy disk zap AICache-3 /dev/sdb1

# 清除DB分区sudo ceph-deploy disk zap AICache-3 /dev/sdb2

# 清除数据分区sudo ceph-deploy disk zap AICache-3 /dev/sde2
sudo ceph-deploy disk zap AICache-3 /dev/sde3

```

强制删除

% sudo systemctl stop ceph-osd@1.service

% sudo lvremove -f /dev/

### **5.2.2 创建OSD**

```bash
sudo ceph-deploy osd create AICache-3 \
    --data /dev/sde2 \
    --block-wal /dev/sdb1 \
    --block-db /dev/sdb2

```

```bash
sudo ceph-deploy osd create AICache-3 \
    --data /dev/sde3 \
#--block-wal /dev/sdb1 \#--block-db /dev/sdb2
```

TODO: 共用一个WAL DB会提示锁住创建失败

> 手动部署命令:
> 

```bash
# 1. 清理旧设备（如果需要）sudo vgremove [vg_name] -f
sudo pvremove /dev/sde2 /dev/sde3

# 2. 部署第一个OSDsudo ceph-volume lvm prepare --bluestore --data /dev/sde2
sudo ceph-volume lvm activate --bluestore 0 e1b6ffc4-5548-4e52-8a2d-00a23452894d

# 3. 部署第二个OSDsudo ceph-volume lvm prepare --bluestore --data /dev/sde3
sudo ceph-volume lvm activate --bluestore 1 531b9f14-0bc7-468f-8f95-f2c192e0b3fd

创建配置存储池

sudo ceph -s

```

让MON允许单副本

```bash
ceph config set global mon_allow_pool_size_one true

```

创建新的存储池

```bash
sudo ceph osd pool create test_pool 256 256

```

设置副本数为1（带确认标志）

```bash
sudo ceph osd pool set test_pool size 1 --yes-i-really-mean-it

```

### **5.2.3 验证OSD状态**

```bash
ceph osd tree

```

功能测试

![https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-8.png](https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-8.png)

![https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-7.png](https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-7.png)

**说明：**

- WAL（Write-Ahead Log）分区用于提高写入性能
- DB分区用于存储OSD的元数据
- 数据分区用于存储实际数据
- 分区大小可以根据实际需求调整
- 建议在执行分区操作前备份重要数据

## **6. RGW节点部署**

### **6.1 RGW简介**

RGW（RADOS Gateway）是Ceph集群的对象存储网关服务，主要功能包括：

- 提供兼容S3和Swift的RESTful API接口
- 为客户端提供对象存储访问服务
- 支持多区域和多站点部署
- 提供细粒度的访问控制

### **6.2 部署RGW实例**

### **6.2.1 创建RGW实例**

修改配置文件

[mon]

mon_allow_pool_delete = true

[client.rgw.bucket1]

rgw_frontends = civetweb port=10001

log file = /var/log/ceph/client.rgw.bucket1.log

更新配置文件

```bash
sudo ceph-deploy --overwrite-conf config push AICache-3

```

在工作目录下执行以下命令：

```bash
cd ~/Proj/ceph-mycluster

# 在各节点创建RGW实例sudo ceph-deploy rgw create AICache-3:bucket1

```

![https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-5.png](https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-5.png)

验证部署状态

```bash
ceph -s

```

![https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-6.png](https://vscode-remote+ssh-002dremote-002b7b22686f73744e616d65223a2248572d3137332e37312e332e33227d.vscode-resource.vscode-cdn.net/home/lzq/Proj/ceph-mycluster/image-6.png)

预期输出：

```
cluster:
  id:     [集群ID]
  health: HEALTH_OK

services:
  mon: 1 daemons, quorum AICache-3 (age 25h)
  mgr: AICache-3(active, since 2d)
  osd: 1 osds: 1 up (since 25h), 1 in (since 9d)
  rgw: 1 daemons active (1 hosts, 1 zones)

```

**说明：**

- RGW默认监听7480端口
- 每个RGW实例可以配置不同的域名和端口
- 可以根据需求部署多个RGW实例来实现负载均衡
- 建议在生产环境中配置HTTPS和域名证书

总结一下:

- 在SSD上创建WAL和DB分区：
    - WAL分区：60GB（用于Write-Ahead Log，提高写入性能）
    - DB分区：180GB（用于存储OSD元数据）
- 在HDD上创建数据分区：
    - 数据分区：1TB（用于存储实际数据）
# 问题汇总
客户端 ceph -s没反应
关闭防火墙（双方 ）
systemctl stop firewalld 
systemctl disable firewalld 
systemctl status firewalld

iostatu里：看不到nvme的流量，重启OSD

2025年2月25日09:25:50：昨天RBD创建没反应，重启了Ceph，启动测试看不到IO；重装OSD，一直报错名称占用；ceph命令卡死，ceph -s没反应；


 ceph创建MON节点报错：[ceph_deploy.mon][WARNIN] mon.ceph1 monitor is not yet in quorum, tries left: 5
[ceph1][DEBUG ] deploying mon to ceph1
[ceph1][DEBUG ] remote hostname: ceph1
[ceph1][DEBUG ] checking for done path: /var/lib/ceph/mon/ceph-ceph1/done
[ceph1][INFO  ] Running command: systemctl enable ceph.target
[ceph1][INFO  ] Running command: systemctl enable ceph-mon@ceph1
[ceph1][INFO  ] Running command: systemctl start ceph-mon@ceph1
[ceph1][INFO  ] Running command: ceph --cluster=ceph --admin-daemon /var/run/ceph/ceph-mon.ceph1.asok mon_status
[ceph1][ERROR ] admin_socket: exception getting command descriptions: [Errno 2] No such file or directory
[ceph1][WARNIN] monitor: mon.ceph1, might not be running yet
[ceph1][INFO  ] Running command: ceph --cluster=ceph --admin-daemon /var/run/ceph/ceph-mon.ceph1.asok mon_status
[ceph1][ERROR ] admin_socket: exception getting command descriptions: [Errno 2] No such file or directory
[ceph1][WARNIN] monitor ceph1 does not exist in monmap
[ceph_deploy.mon][INFO  ] processing monitor mon.ceph1
[ceph1][DEBUG ] connected to host: ceph1 
[ceph1][INFO  ] Running command: ceph --cluster=ceph --admin-daemon /var/run/ceph/ceph-mon.ceph1.asok mon_status
[ceph1][ERROR ] admin_socket: exception getting command descriptions: [Errno 2] No such file or directory
[ceph_deploy.mon][WARNIN] mon.ceph1 monitor is not yet in quorum, tries left: 5

暂时解决：
ceph-deploy purge ceph1
ceph-deploy purgedata ceph1（会调用yum删除ceph）
sudo yum install ceph -y

InvalidArgumentError('RADOS invalid argument (error calling conf_read_file)')

ceph -s                                 
Error initializing cluster client: InvalidArgumentError('RADOS invalid argument (error calling conf_read_file)')
权限问题，从ceph new 重做
