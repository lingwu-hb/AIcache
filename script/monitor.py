#!/usr/bin/env python3

# ./monitor_ocf_stats.py CAS1
# 调用SPDK RPC, 监视OCF的性能
# 可选参数：
# -i 或 --interval：设置监控间隔（秒）
# -l 或 --log：指定日志文件路径

import subprocess
import json
import time
from datetime import datetime
import argparse
import os
import csv
rpc_path = "/home/lzq/spdk/scripts/rpc.py" 

class OCFMonitor:
    def __init__(self, cache_name, interval=5, log_file="ocf_stats.log"):
        """初始化OCF监控器
        
        Args:
            cache_name: OCF缓存设备名称
            interval: 统计信息收集间隔(秒)
            log_file: 日志文件路径
        """
        self.cache_name = cache_name
        self.interval = interval
        self.log_file = log_file
        self.rpc_path = rpc_path
        # CSV表头
        self.headers = [
            "时间",
            "总容量(4KiB块)",
            "已用空间(块)",
            "已用空间(%)",
            "脏数据(块)",
            "脏数据(%)",
            "读命中数",
            "读命中率(%)",
            "读部分未命中数",
            "读部分未命中率(%)",
            "读完全未命中数",
            "读完全未命中率(%)",
            "读直通数",
            "写命中数",
            "写命中率(%)",
            "写部分未命中数",
            "写部分未命中率(%)",
            "写完全未命中数",
            "写完全未命中率(%)",
            "写直通数",
            "核心卷读(块)",
            "核心卷写(块)",
            "缓存卷读(块)",
            "缓存卷写(块)",
            "总错误数"
        ]

    def get_stats(self):
        """获取OCF统计信息"""
        try:
            cmd = [self.rpc_path, "bdev_ocf_get_stats", self.cache_name]
            result = subprocess.run(cmd, capture_output=True, text=True)
            return json.loads(result.stdout)
        except Exception as e:
            print(f"获取统计信息失败: {e}")
            return None

    def format_stats(self, stats):
        """格式化统计信息为两种格式：显示格式和CSV格式"""
        if not stats:
            return "统计信息获取失败", None

        # 1. 用于显示的格式化文本
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        display_output = []
        display_output.append(f"时间: {timestamp}")
        
        usage = stats["usage"]
        total_blocks = usage['occupancy']['count'] + usage['free']['count']
        display_output.append("\n=== 缓存使用情况 ===")
        display_output.append(f"总容量: {total_blocks} 个4KiB块")
        display_output.append(f"已使用: {usage['occupancy']['count']} 块 ({usage['occupancy']['percentage']}%)")
        display_output.append(f"脏数据: {usage['dirty']['count']} 块 ({usage['dirty']['percentage']}%)")
        
        req = stats["requests"]
        display_output.append("\n=== 请求统计 ===")
        display_output.append("读请求:")
        display_output.append(f"  - 命中: {req['rd_hits']['count']} ({req['rd_hits']['percentage']}%)")
        display_output.append(f"  - 部分未命中: {req['rd_partial_misses']['count']} ({req['rd_partial_misses']['percentage']}%)")
        display_output.append(f"  - 完全未命中: {req['rd_full_misses']['count']} ({req['rd_full_misses']['percentage']}%)")
        display_output.append(f"  - 直通: {req['rd_pt']['count']}")
        display_output.append("写请求:")
        display_output.append(f"  - 命中: {req['wr_hits']['count']} ({req['wr_hits']['percentage']}%)")
        display_output.append(f"  - 完全未命中: {req['wr_full_misses']['count']} ({req['wr_full_misses']['percentage']}%)")
        display_output.append(f"  - 直通: {req['wr_pt']['count']} ({req['wr_pt']['percentage']}%)")

        blocks = stats["blocks"]
        display_output.append("\n=== 块统计 ===")
        display_output.append("核心卷:")
        display_output.append(f"  - 读: {blocks['core_volume_rd']['count']} 块")
        display_output.append(f"  - 写: {blocks['core_volume_wr']['count']} 块")
        display_output.append("缓存卷:")
        display_output.append(f"  - 读: {blocks['cache_volume_rd']['count']} 块")
        display_output.append(f"  - 写: {blocks['cache_volume_wr']['count']} 块")

        errors = stats["errors"]
        total_errors = errors["total"]["count"]
        display_output.append("\n=== 错误统计 ===")
        if total_errors > 0:
            display_output.append(f"总错误数: {total_errors}")
            display_output.append(f"核心卷错误: {errors['core_volume_total']['count']}")
            display_output.append(f"缓存卷错误: {errors['cache_volume_total']['count']}")
        else:
            display_output.append("无错误")

        display_output.append("\n" + "="*50 + "\n")

        # 2. CSV格式数据
        csv_data = [
            timestamp,
            total_blocks,
            usage['occupancy']['count'],
            usage['occupancy']['percentage'],
            usage['dirty']['count'],
            usage['dirty']['percentage'],
            req['rd_hits']['count'],
            req['rd_hits']['percentage'],
            req['rd_partial_misses']['count'],
            req['rd_partial_misses']['percentage'],
            req['rd_full_misses']['count'],
            req['rd_full_misses']['percentage'],
            req['rd_pt']['count'],
            req['wr_hits']['count'],
            req['wr_hits']['percentage'],
            req['wr_partial_misses']['count'],
            req['wr_partial_misses']['percentage'],
            req['wr_full_misses']['count'],
            req['wr_full_misses']['percentage'],
            req['wr_pt']['count'],
            blocks['core_volume_rd']['count'],
            blocks['core_volume_wr']['count'],
            blocks['cache_volume_rd']['count'],
            blocks['cache_volume_wr']['count'],
            total_errors
        ]

        return "\n".join(display_output), csv_data

    def write_log(self, csv_data):
        """以CSV格式写入日志文件"""
        try:
            # 检查文件是否存在
            file_exists = os.path.exists(self.log_file)
            
            with open(self.log_file, "a", newline='', encoding="utf-8") as f:
                writer = csv.writer(f)
                # 如果是新文件，写入表头
                if not file_exists:
                    writer.writerow(self.headers)
                # 写入数据行
                if csv_data:
                    writer.writerow(csv_data)
        except Exception as e:
            print(f"写入日志失败: {e}")

    def monitor(self):
        """开始监控"""
        print(f"开始监控OCF缓存 {self.cache_name}")
        print(f"日志文件: {self.log_file}")
        print(f"监控间隔: {self.interval}秒")
        print("按Ctrl+C停止监控\n")

        try:
            while True:
                stats = self.get_stats()
                if stats:
                    display_text, csv_data = self.format_stats(stats)
                    print(display_text)
                    self.write_log(csv_data)
                time.sleep(self.interval)
        except KeyboardInterrupt:
            print("\n监控已停止")

def main():
    parser = argparse.ArgumentParser(description="OCF缓存性能监控工具")
    parser.add_argument("cache_name", help="OCF缓存设备名称")
    parser.add_argument("-i", "--interval", type=int, default=1,
                      help="统计信息收集间隔(秒), 默认1秒")
    parser.add_argument("-l", "--log", default="ocf_stats.log",
                      help="日志文件路径, 默认为ocf_stats.log")
    
    args = parser.parse_args()
    
    monitor = OCFMonitor(args.cache_name, args.interval, args.log)
    monitor.monitor()

if __name__ == "__main__":
    main() 

