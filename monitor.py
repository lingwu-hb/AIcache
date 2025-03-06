#!/usr/bin/env python3

import subprocess
import json
import time
from datetime import datetime
import argparse
import os
import csv
from typing import Dict, Any, Tuple, List, Optional

# ANSI颜色代码
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

class OCFMonitor:
    def __init__(self, cache_name: str, interval: int = 5, log_file: str = "ocf_stats.log"):
        self.cache_name = cache_name
        self.interval = interval
        self.log_file = log_file
        self.rpc_path = "/home/lzq/spdk/scripts/rpc.py"
        self.last_stats = None  # 存储上一次的统计数据
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

    def get_stats(self) -> Optional[Dict[str, Any]]:
        """获取OCF统计信息"""
        try:
            cmd = [self.rpc_path, "bdev_ocf_get_stats", self.cache_name]
            result = subprocess.run(cmd, capture_output=True, text=True)
            return json.loads(result.stdout)
        except Exception as e:
            print(f"{Colors.RED}获取统计信息失败: {e}{Colors.ENDC}")
            return None

    def format_value(self, value: Any, width: int = 15) -> str:
        """格式化数值，保持对齐"""
        return f"{str(value):<{width}}"

    def format_percentage(self, value: float, width: int = 15, threshold: float = 80.0) -> str:
        """格式化百分比，根据数值添加颜色"""
        if value >= threshold:
            color = Colors.RED
        elif value >= threshold * 0.8:
            color = Colors.YELLOW
        else:
            color = Colors.GREEN
        return f"{color}{value:>{width-1}.2f}%{Colors.ENDC}"

    def format_stats(self, stats: Dict[str, Any]) -> Tuple[str, List[Any]]:
        """格式化统计信息，返回显示文本和CSV数据"""
        if not stats:
            return "统计信息获取失败", None

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        display_output = []

        # 标题
        display_output.append(f"{Colors.BOLD}{Colors.BLUE}OCF缓存监控 - {self.cache_name}{Colors.ENDC}")
        display_output.append(f"{Colors.BOLD}时间: {timestamp}{Colors.ENDC}\n")

        # 缓存使用情况
        usage = stats["usage"]
        total_blocks = usage['occupancy']['count'] + usage['free']['count']
        display_output.append(f"{Colors.BOLD}{Colors.UNDERLINE}缓存使用情况{Colors.ENDC}")
        
        # 使用固定宽度格式化
        label_width = 20
        value_width = 15
        
        display_output.append(f"{'总容量:':<{label_width}}{self.format_value(total_blocks, value_width)}块")
        display_output.append(f"{'已使用:':<{label_width}}{self.format_value(usage['occupancy']['count'], value_width)}块 "
                            f"({self.format_percentage(usage['occupancy']['percentage'], 8)})")
        display_output.append(f"{'脏数据:':<{label_width}}{self.format_value(usage['dirty']['count'], value_width)}块 "
                            f"({self.format_percentage(usage['dirty']['percentage'], 8)})")

        # 请求统计
        req = stats["requests"]
        display_output.append(f"\n{Colors.BOLD}{Colors.UNDERLINE}请求统计{Colors.ENDC}")
        
        # 读请求
        display_output.append(f"{Colors.BOLD}读请求:{Colors.ENDC}")
        display_output.append(f"{'  命中:':<{label_width}}{self.format_value(req['rd_hits']['count'], value_width)} "
                            f"({self.format_percentage(req['rd_hits']['percentage'], 8)})")
        display_output.append(f"{'  部分未命中:':<{label_width}}{self.format_value(req['rd_partial_misses']['count'], value_width)} "
                            f"({self.format_percentage(req['rd_partial_misses']['percentage'], 8)})")
        display_output.append(f"{'  完全未命中:':<{label_width}}{self.format_value(req['rd_full_misses']['count'], value_width)} "
                            f"({self.format_percentage(req['rd_full_misses']['percentage'], 8)})")
        display_output.append(f"{'  直通:':<{label_width}}{self.format_value(req['rd_pt']['count'], value_width)}")

        # 写请求
        display_output.append(f"\n{Colors.BOLD}写请求:{Colors.ENDC}")
        display_output.append(f"{'  命中:':<{label_width}}{self.format_value(req['wr_hits']['count'], value_width)} "
                            f"({self.format_percentage(req['wr_hits']['percentage'], 8)})")
        display_output.append(f"{'  完全未命中:':<{label_width}}{self.format_value(req['wr_full_misses']['count'], value_width)} "
                            f"({self.format_percentage(req['wr_full_misses']['percentage'], 8)})")
        display_output.append(f"{'  直通:':<{label_width}}{self.format_value(req['wr_pt']['count'], value_width)} "
                            f"({self.format_percentage(req['wr_pt']['percentage'], 8)})")

        # 块统计
        blocks = stats["blocks"]
        display_output.append(f"\n{Colors.BOLD}{Colors.UNDERLINE}块统计{Colors.ENDC}")
        display_output.append(f"{Colors.BOLD}核心卷:{Colors.ENDC}")
        display_output.append(f"{'  读:':<{label_width}}{self.format_value(blocks['core_volume_rd']['count'], value_width)}块")
        display_output.append(f"{'  写:':<{label_width}}{self.format_value(blocks['core_volume_wr']['count'], value_width)}块")
        display_output.append(f"{Colors.BOLD}缓存卷:{Colors.ENDC}")
        display_output.append(f"{'  读:':<{label_width}}{self.format_value(blocks['cache_volume_rd']['count'], value_width)}块")
        display_output.append(f"{'  写:':<{label_width}}{self.format_value(blocks['cache_volume_wr']['count'], value_width)}块")

        # 错误统计
        errors = stats["errors"]
        total_errors = errors["total"]["count"]
        display_output.append(f"\n{Colors.BOLD}{Colors.UNDERLINE}错误统计{Colors.ENDC}")
        if total_errors > 0:
            display_output.append(f"{Colors.RED}总错误数: {total_errors}{Colors.ENDC}")
            display_output.append(f"{Colors.RED}核心卷错误: {errors['core_volume_total']['count']}{Colors.ENDC}")
            display_output.append(f"{Colors.RED}缓存卷错误: {errors['cache_volume_total']['count']}{Colors.ENDC}")
        else:
            display_output.append(f"{Colors.GREEN}无错误{Colors.ENDC}")

        display_output.append(f"\n{Colors.BOLD}{'='*50}{Colors.ENDC}\n")

        # CSV数据
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

    def has_stats_changed(self, current_stats: List[Any]) -> bool:
        """检查统计数据是否发生变化"""
        if self.last_stats is None:
            return True
        
        # 跳过时间戳比较（第一个元素）
        return current_stats[1:] != self.last_stats[1:]

    def write_log(self, csv_data: List[Any]) -> None:
        """以CSV格式写入日志文件，仅在数据发生变化时写入"""
        if not csv_data:
            return

        try:
            # 检查数据是否发生变化
            if not self.has_stats_changed(csv_data):
                return

            # 更新上一次的统计数据
            self.last_stats = csv_data[:]

            # 检查文件是否存在
            file_exists = os.path.exists(self.log_file)
            
            with open(self.log_file, "a", newline='', encoding="utf-8") as f:
                writer = csv.writer(f)
                # 如果是新文件，写入表头
                if not file_exists:
                    writer.writerow(self.headers)
                # 写入数据行
                writer.writerow(csv_data)
        except Exception as e:
            print(f"{Colors.RED}写入日志失败: {e}{Colors.ENDC}")

    def monitor(self) -> None:
        """开始监控"""
        print(f"{Colors.BOLD}{Colors.GREEN}开始监控OCF缓存 {self.cache_name}{Colors.ENDC}")
        print(f"{Colors.BOLD}日志文件: {self.log_file}{Colors.ENDC}")
        print(f"{Colors.BOLD}监控间隔: {self.interval}秒{Colors.ENDC}")
        print(f"{Colors.YELLOW}按Ctrl+C停止监控{Colors.ENDC}\n")

        try:
            while True:
                # 清屏
                os.system('cls' if os.name == 'nt' else 'clear')
                
                stats = self.get_stats()
                if stats:
                    display_text, csv_data = self.format_stats(stats)
                    print(display_text)
                    self.write_log(csv_data)
                time.sleep(self.interval)
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}监控已停止{Colors.ENDC}")

def main():
    parser = argparse.ArgumentParser(description=f"{Colors.BOLD}OCF缓存性能监控工具{Colors.ENDC}")
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