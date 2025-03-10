#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re
import sys
from datetime import datetime
from pathlib import Path

# 从环境变量获取配置
FIO_PATH = os.getenv('FIO_PATH', '')
CSV_PATH = os.getenv('CSV_PATH', '')

# 检查配置
if not FIO_PATH or not CSV_PATH:
    print("错误: 环境变量FIO_PATH或CSV_PATH未设置")
    sys.exit(1)

# 创建输出目录
current_date = datetime.now().strftime('%Y-%m-%d')
output_dir = Path(CSV_PATH) / current_date
output_dir.mkdir(parents=True, exist_ok=True)

# 创建输出文件
timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
output_file_path = output_dir / f"result_{timestamp}.csv"

# 写入CSV头
with open(output_file_path, 'w', encoding='utf-8') as f:
    f.write("Trace,Cache Size,IOPS,BW(MiB/s),Timestamp\n")
    
    # 处理所有FIO结果文件
    for fio_file in Path(FIO_PATH).rglob('*_fio_result.log'):
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
            
        # 提取元数据
        metadata_match = re.search(r'# TEST_METADATA:.*?CACHE_SIZE=([^,]+).*?TIMESTAMP=([^,\s]+)', content)
        cache_size = metadata_match.group(1) if metadata_match else "unknown"
        timestamp = metadata_match.group(2) if metadata_match else ""
        
        # 提取性能数据
        iops_match = re.findall(r'IOPS=([\d\.]+)', content)
        bw_match = re.findall(r'BW=([\d\.]+)MiB/s', content)
        
        if iops_match and bw_match:
            iops = iops_match[-1]  # 使用最后一个匹配结果
            bw = bw_match[-1]
            
            # 写入结果到CSV
            f.write(f"{trace_name},{cache_size},{iops},{bw},{timestamp}\n")
            print(f"已处理: {trace_name} (IOPS: {iops}, BW: {bw} MB/s, Cache Size: {cache_size})")
        else:
            print(f"警告: 无法从{fio_file}提取性能数据")

print(f"处理完成. 结果保存到{output_file_path}") 