#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
在不关闭虚拟机的前提下，重启SPDK并重载硬盘
用于快速修改缓存大小参数而无需完全重启虚拟机
"""

import os
import sys
import time
import subprocess
import argparse
import socket

def run_cmd(cmd, shell=True):
    """运行命令并返回结果"""
    print(f"执行: {cmd}")
    result = subprocess.run(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return result.returncode == 0, result.stdout

def send_qemu_cmd(vm_id, cmd):
    """发送命令到QEMU监控器"""
    monitor_socket = f"/var/run/vm{vm_id:02d}/monitor.sock"
    if not os.path.exists(monitor_socket):
        print(f"错误: 找不到监控器套接字 {monitor_socket}")
        return False
        
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(monitor_socket)
        sock.settimeout(5)
        
        # 读取欢迎消息
        sock.recv(4096)
        
        # 发送命令
        print(f"QEMU命令: {cmd}")
        sock.sendall(f"{cmd}\n".encode('utf-8'))
        
        # 读取响应
        response = sock.recv(4096).decode('utf-8', errors='ignore')
        sock.close()
        return True
    except Exception as e:
        print(f"QEMU命令失败: {e}")
        return False

def run_ssh(vm_id, cmd):
    """在VM中运行SSH命令"""
    # 从环境变量读取SSH密码和IP基址
    vm_base_ip = os.environ.get("VM_BASE_IP", "192.168.122")
    vm_ssh_pass = os.environ.get("VM_SSH_PASS", "openEuler12#$")
    vm_ip = f"{vm_base_ip}.{200 + vm_id}"
    
    ssh_cmd = f"sshpass -p '{vm_ssh_pass}' ssh -o StrictHostKeyChecking=no root@{vm_ip} '{cmd}'"
    return run_cmd(ssh_cmd)

def restart_spdk(cache_size):
    """重启SPDK进程并设置新的缓存大小"""
    # 从环境变量获取SPDK路径
    spdk_path = os.environ.get("SPDK_PATH", "/home/lzq/spdk")
    
    # 停止现有SPDK进程
    print("停止SPDK进程...")
    run_cmd("pkill -f spdk_tgt || true")
    time.sleep(2)
    
    # 启动新的SPDK进程
    print(f"启动SPDK，缓存大小: {cache_size}...")
    start_cmd = f"cd {spdk_path} && ./scripts/spdk_tgt.py --cache-size {cache_size}"
    run_cmd(f"nohup {start_cmd} > {spdk_path}/log/spdk_start.log 2>&1 &")
    time.sleep(5)
    
    # 检查SPDK是否成功启动
    success, _ = run_cmd("pgrep -f spdk_tgt")
    if not success:
        print("错误: SPDK启动失败")
        return False
    return True

def reload_disk(vm_id, cache_size):
    """重新加载VM中的磁盘"""
    print(f"处理VM{vm_id:02d}...")
    
    # 1. 卸载文件系统
    print("卸载文件系统...")
    run_ssh(vm_id, "umount /dev/sda1 || echo 'Not mounted'")
    
    # 2. 从QEMU中移除设备
    print("移除磁盘设备...")
    if not send_qemu_cmd(vm_id, "device_del spdk_disk"):
        print("移除设备失败")
        return False
    time.sleep(2)
    
    # 3. 重启SPDK（仅执行一次）
    if not restart_spdk(cache_size):
        return False
    
    # 4. 重新添加设备
    print("重新添加磁盘设备...")
    if not send_qemu_cmd(vm_id, "device_add vhost-user-blk-pci,id=spdk_disk,chardev=spdk_char"):
        print("添加设备失败")
        return False
    time.sleep(2)
    
    # 5. 重新挂载文件系统
    print("重新挂载文件系统...")
    run_ssh(vm_id, "mount /dev/sda1 /mnt || echo 'Mount failed'")
    
    print(f"VM{vm_id:02d}的磁盘已重新加载")
    return True

def main():
    parser = argparse.ArgumentParser(description="重载SPDK磁盘设备而不重启VM")
    parser.add_argument("--cache-size", type=str, required=True, help="缓存大小")
    parser.add_argument("--vm-ids", type=str, default="1", help="VM ID，用逗号分隔")
    args = parser.parse_args()
    
    # 解析VM ID
    if ',' in args.vm_ids:
        vm_ids = [int(x.strip()) for x in args.vm_ids.split(',')]
    elif '-' in args.vm_ids:
        start, end = map(int, args.vm_ids.split('-'))
        vm_ids = list(range(start, end + 1))
    else:
        vm_ids = [int(args.vm_ids)]
    
    # 处理每个虚拟机
    all_success = True
    for vm_id in vm_ids:
        if not reload_disk(vm_id, args.cache_size):
            print(f"VM{vm_id:02d}的磁盘重载失败")
            all_success = False
    
    return 0 if all_success else 1

if __name__ == "__main__":
    sys.exit(main()) 