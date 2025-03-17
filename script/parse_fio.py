#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re
import sys
from datetime import datetime
from pathlib import Path

# 从环境变量获取配置，如果没有设置则使用默认值
FIO_PATH = os.getenv('FIO_PATH', '/home/lzq/AICache-tools/rawfio')
CSV_PATH = os.getenv('CSV_PATH', '/home/lzq/AICache-tools/csv')

# 检查目录是否存在
if not os.path.exists(FIO_PATH):
    print(f"错误: FIO结果目录不存在: {FIO_PATH}")
    sys.exit(1)

if not os.path.exists(CSV_PATH):
    print(f"创建CSV输出目录: {CSV_PATH}")
    os.makedirs(CSV_PATH, exist_ok=True)

# 创建输出目录
current_date = datetime.now().strftime('%Y-%m-%d')
output_dir = Path(CSV_PATH) / current_date
output_dir.mkdir(parents=True, exist_ok=True)

# 创建输出文件
timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
output_file_path = output_dir / f"result_{timestamp}.csv"

def convert_to_number(value_str):
    """将带单位的值转换为数字"""
    if not value_str:
        return 0
    
    # 移除所有空格
    value_str = value_str.strip()
    
    # 处理带k, M, G单位的值
    multiplier = 1
    if value_str.endswith('k'):
        multiplier = 1000
        value_str = value_str[:-1]
    elif value_str.endswith('M'):
        multiplier = 1000000
        value_str = value_str[:-1]
    elif value_str.endswith('G'):
        multiplier = 1000000000
        value_str = value_str[:-1]
    
    try:
        return float(value_str) * multiplier
    except ValueError:
        return 0

# 写入CSV头
with open(output_file_path, 'w', encoding='utf-8') as f:
    f.write("Trace,Cache Size,IOPS,BW(MiB/s),Timestamp\n")
    
    # 处理所有FIO结果文件
    for fio_file in Path(FIO_PATH).rglob('*_fio_result.log'):
        print(f"处理文件: {fio_file}")
        
        # 提取trace名称
        pattern_dir = fio_file.parent.parent.name
        trace_match = re.search(r'([^+]+\.txt)', pattern_dir)
        trace_name = trace_match.group(1) if trace_match else "unknown_trace"
        
        if trace_name == "unknown_trace":
            print(f"警告: 无法从{pattern_dir}提取trace名称")
            continue
            
        # 读取文件内容
        with open(fio_file, 'r', encoding='utf-8') as file:
            content = file.read()
            
        # 提取元数据 (如果存在)
        metadata_match = re.search(r'# TEST_METADATA:.*?CACHE_SIZE=([^,]+).*?TIMESTAMP=([^,\s]+)', content)
        cache_size = metadata_match.group(1) if metadata_match else "unknown"
        timestamp = metadata_match.group(2) if metadata_match else datetime.now().strftime('%Y%m%d%H%M%S')
        
        # 提取性能数据 - 改进正则表达式以支持带单位的值
        # 查找IOPS
        iops_str = None
        iops_match = re.search(r'IOPS=(\d+\.?\d*[kMG]?)', content)
        if iops_match:
            iops_str = iops_match.group(1)
            # 转换带单位的值为纯数字
            iops_value = convert_to_number(iops_str)
            iops_str = f"{iops_value:.1f}"  # 转回字符串用于CSV输出
        
        # 查找带宽
        bw_str = None
        bw_match = re.search(r'BW=(\d+\.?\d*)MiB/s', content)
        if bw_match:
            bw_str = bw_match.group(1)
        
        if iops_str and bw_str:
            # 写入结果到CSV
            f.write(f"{trace_name},{cache_size},{iops_str},{bw_str},{timestamp}\n")
            print(f"已处理: {trace_name} (IOPS: {iops_str}, BW: {bw_str} MB/s, Cache Size: {cache_size})")
        else:
            print(f"警告: 无法从{fio_file}提取性能数据")
            if not iops_str:
                print(f"  - 未找到IOPS值")
            if not bw_str:
                print(f"  - 未找到BW值")

print(f"处理完成. 结果保存到{output_file_path}") 