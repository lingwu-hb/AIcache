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
    try:
        result = subprocess.run(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def send_qemu_cmd(vm_id, cmd):
    """发送命令到QEMU监控器"""
    monitor_socket = f"/var/run/vm{vm_id:02d}/monitor.sock"
    if not os.path.exists(monitor_socket):
        return False, "监控器套接字不存在"
        
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(monitor_socket)
        sock.settimeout(5)
        
        # 读取并显示欢迎消息
        welcome = sock.recv(4096).decode('utf-8', errors='ignore')
        print(welcome, end='', flush=True)
        
        # 发送命令并显示
        print(f"(qemu) {cmd}")
        sock.sendall(f"{cmd}\n".encode('utf-8'))
        
        # 读取并显示响应
        response = sock.recv(4096).decode('utf-8', errors='ignore')
        print(response, end='', flush=True)
        sock.close()
        
        # 仅在明确的错误情况下返回False
        return not ("error" in response.lower() and "failed" in response.lower()), response
    except Exception as e:
        return False, str(e)

def run_ssh(vm_id, cmd):
    """在VM中运行SSH命令"""
    vm_base_ip = os.environ.get("VM_BASE_IP", "192.168.122")
    vm_ssh_pass = os.environ.get("VM_SSH_PASS", "openEuler12#$")
    vm_ip = f"{vm_base_ip}.{200 + vm_id}"
    
    ssh_cmd = f"sshpass -p '{vm_ssh_pass}' ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@{vm_ip} '{cmd}'"
    return run_cmd(ssh_cmd)[0]

def restart_spdk(cache_size):
    """重启SPDK进程并设置新的缓存大小"""
    spdk_path = os.environ.get("SPDK_PATH", "/home/lzq/spdk")
    
    # 停止现有SPDK进程
    run_cmd("pkill -f spdk_tgt || true")
    time.sleep(2)
    
    # 启动新的SPDK进程
    start_cmd = f"cd {spdk_path} && ./scripts/spdk_tgt.py --cache-size {cache_size}"
    success, _, _ = run_cmd(f"nohup {start_cmd} > {spdk_path}/log/spdk_start.log 2>&1 &")
    if not success:
        return False
    
    time.sleep(5)
    return run_cmd("pgrep -f spdk_tgt")[0]

def reload_disk(vm_id, cache_size):
    """重新加载VM中的磁盘"""
    # 1. 卸载文件系统
    run_ssh(vm_id, "umount /dev/nvme0n1 || true")
    
    # 2. 从QEMU中移除设备
    success, response = send_qemu_cmd(vm_id, "device_del spdk_disk")
    if not success:
        return False
    time.sleep(2)
    
    # 3. 重启SPDK
    if not restart_spdk(cache_size):
        return False
    
    # 4. 重新添加设备
    success, response = send_qemu_cmd(vm_id, "device_add vhost-user-blk-pci,id=spdk_disk,chardev=spdk_char")
    if not success:
        return False
    time.sleep(2)
    
    # 5. 重新挂载文件系统
    run_ssh(vm_id, "mount /dev/nvme0n1 /mnt || true")
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache-size", type=str, required=True)
    parser.add_argument("--vm-ids", type=str, default="1")
    args = parser.parse_args()
    
    try:
        if ',' in args.vm_ids:
            vm_ids = [int(x.strip()) for x in args.vm_ids.split(',')]
        elif '-' in args.vm_ids:
            start, end = map(int, args.vm_ids.split('-'))
            vm_ids = list(range(start, end + 1))
        else:
            vm_ids = [int(args.vm_ids)]
    except ValueError as e:
        print(f"错误: 无效的VM ID格式: {e}", file=sys.stderr)
        return 1
    
    all_success = True
    for vm_id in vm_ids:
        if not reload_disk(vm_id, args.cache_size):
            all_success = False
            print(f"VM{vm_id}处理失败", file=sys.stderr)
    
    return 0 if all_success else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(str(e), file=sys.stderr)
        sys.exit(1) 