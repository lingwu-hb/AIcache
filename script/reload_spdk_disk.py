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
    print(f"\n执行命令: {cmd}")
    result = subprocess.run(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.stdout:
        print(f"命令输出:\n{result.stdout}")
    if result.stderr:
        print(f"错误输出:\n{result.stderr}")
    print(f"返回码: {result.returncode}")
    return result.returncode == 0, result.stdout, result.stderr

def send_qemu_cmd(vm_id, cmd):
    """发送命令到QEMU监控器"""
    monitor_socket = f"/var/run/vm{vm_id:02d}/monitor.sock"
    if not os.path.exists(monitor_socket):
        print(f"错误: 找不到监控器套接字 {monitor_socket}")
        return False, None
        
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(monitor_socket)
        sock.settimeout(5)
        
        # 读取欢迎消息
        welcome = sock.recv(4096).decode('utf-8', errors='ignore')
        print(f"QEMU欢迎消息:\n{welcome}")
        
        # 发送命令
        print(f"发送QEMU命令: {cmd}")
        sock.sendall(f"{cmd}\n".encode('utf-8'))
        
        # 读取响应
        response = sock.recv(4096).decode('utf-8', errors='ignore')
        print(f"QEMU响应:\n{response}")
        sock.close()
        
        # 检查响应中是否包含错误信息
        if "error" in response.lower():
            print(f"QEMU命令返回错误")
            return False, response
        return True, response
    except Exception as e:
        print(f"QEMU命令异常: {str(e)}")
        return False, str(e)

def run_ssh(vm_id, cmd):
    """在VM中运行SSH命令"""
    # 从环境变量读取SSH密码和IP基址
    vm_base_ip = os.environ.get("VM_BASE_IP", "192.168.122")
    vm_ssh_pass = os.environ.get("VM_SSH_PASS", "openEuler12#$")
    vm_ip = f"{vm_base_ip}.{200 + vm_id}"
    
    print(f"\n在VM {vm_ip}上执行: {cmd}")
    ssh_cmd = f"sshpass -p '{vm_ssh_pass}' ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@{vm_ip} '{cmd}'"
    success, stdout, stderr = run_cmd(ssh_cmd)
    
    if not success:
        print(f"SSH命令失败:")
        if stdout: print(f"标准输出:\n{stdout}")
        if stderr: print(f"错误输出:\n{stderr}")
    return success

def restart_spdk(cache_size):
    """重启SPDK进程并设置新的缓存大小"""
    # 从环境变量获取SPDK路径
    spdk_path = os.environ.get("SPDK_PATH", "/home/lzq/spdk")
    print(f"\nSPDK路径: {spdk_path}")
    
    # 停止现有SPDK进程
    print("\n停止SPDK进程...")
    success, stdout, stderr = run_cmd("pkill -f spdk_tgt || true")
    time.sleep(2)
    
    # 启动新的SPDK进程
    print(f"\n启动SPDK，缓存大小: {cache_size}...")
    start_cmd = f"cd {spdk_path} && ./scripts/spdk_tgt.py --cache-size {cache_size}"
    success, stdout, stderr = run_cmd(f"nohup {start_cmd} > {spdk_path}/log/spdk_start.log 2>&1 &")
    if not success:
        print("启动SPDK失败")
        return False
    
    # 等待SPDK启动
    print("\n等待SPDK启动...")
    time.sleep(5)
    
    # 检查SPDK是否成功启动
    success, stdout, stderr = run_cmd("pgrep -f spdk_tgt")
    if not success:
        print("错误: 未找到SPDK进程")
        # 显示启动日志
        if os.path.exists(f"{spdk_path}/log/spdk_start.log"):
            with open(f"{spdk_path}/log/spdk_start.log", 'r') as f:
                print("\nSPDK启动日志:")
                print(f.read())
        return False
        
    print("SPDK进程已启动")
    return True

def reload_disk(vm_id, cache_size):
    """重新加载VM中的磁盘"""
    print(f"\n开始处理VM{vm_id:02d}...")
    
    # 1. 卸载文件系统
    print("\n步骤1: 卸载文件系统...")
    run_ssh(vm_id, "umount /dev/sda1 || echo 'Not mounted'")
    
    # 2. 从QEMU中移除设备
    print("\n步骤2: 移除磁盘设备...")
    success, response = send_qemu_cmd(vm_id, "device_del spdk_disk")
    if not success:
        print(f"移除设备失败: {response}")
        return False
    time.sleep(2)
    
    # 3. 重启SPDK（仅执行一次）
    print("\n步骤3: 重启SPDK...")
    if not restart_spdk(cache_size):
        return False
    
    # 4. 重新添加设备
    print("\n步骤4: 重新添加磁盘设备...")
    success, response = send_qemu_cmd(vm_id, "device_add vhost-user-blk-pci,id=spdk_disk,chardev=spdk_char")
    if not success:
        print(f"添加设备失败: {response}")
        return False
    time.sleep(2)
    
    # 5. 重新挂载文件系统
    print("\n步骤5: 重新挂载文件系统...")
    run_ssh(vm_id, "mount /dev/sda1 /mnt || echo 'Mount failed'")
    
    print(f"\nVM{vm_id:02d}的磁盘已重新加载")
    return True

def main():
    parser = argparse.ArgumentParser(description="重载SPDK磁盘设备而不重启VM")
    parser.add_argument("--cache-size", type=str, required=True, help="缓存大小")
    parser.add_argument("--vm-ids", type=str, default="1", help="VM ID，用逗号分隔")
    args = parser.parse_args()
    
    print(f"\n参数信息:")
    print(f"缓存大小: {args.cache_size}")
    print(f"VM IDs: {args.vm_ids}")
    
    # 解析VM ID
    try:
        if ',' in args.vm_ids:
            vm_ids = [int(x.strip()) for x in args.vm_ids.split(',')]
        elif '-' in args.vm_ids:
            start, end = map(int, args.vm_ids.split('-'))
            vm_ids = list(range(start, end + 1))
        else:
            vm_ids = [int(args.vm_ids)]
    except ValueError as e:
        print(f"\n错误: 无效的VM ID格式: {e}")
        return 1
    
    print(f"处理的VM列表: {vm_ids}")
    
    # 处理每个虚拟机
    all_success = True
    for vm_id in vm_ids:
        print(f"\n{'='*50}")
        print(f"处理VM {vm_id}")
        print(f"{'='*50}")
        if not reload_disk(vm_id, args.cache_size):
            print(f"\nVM{vm_id:02d}的磁盘重载失败")
            all_success = False
    
    if all_success:
        print("\n所有VM处理成功")
    else:
        print("\n部分VM处理失败")
    return 0 if all_success else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"\n发生未预期的错误: {str(e)}")
        import traceback
        print(traceback.format_exc())
        sys.exit(1) 