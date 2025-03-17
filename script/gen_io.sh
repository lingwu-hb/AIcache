#!/bin/bash

# 定义目录
result_dir="/home/hb/spdk_fio/result"
output_dir="/home/hb/res_analyse/csv"

# 获取当前日期和时间（格式：YYYY-MM-DD_HH-MM-SS）
timestamp=$(date +%Y-%m-%d_%H-%M-%S)

# 获取当前日期（格式：YYYY-MM-DD），如果失败则使用默认值
current_date=$(date +%Y-%m-%d 2>/dev/null || echo "unknown_date")

# 在 output_dir 下创建日期子目录
output_dir_with_date="$output_dir/$current_date"
mkdir -p "$output_dir_with_date"

# TODO: 考虑在文件名中增加使用的算法模式

# 定义汇总的 CSV 文件路径
summary_csv="$output_dir_with_date/result_${timestamp}.csv"

# 初始化汇总 CSV 文件，写入表头
echo "Trace,Cache Size,IOPS,BW(MiB/s)" > "$summary_csv"

# 定义 Trace 和缓存大小的映射关系
declare -A replay_trace_config=(
    ["hm_0.txt"]="96"
    ["mds_1.txt"]="4300"
    ["prn_0.txt"]="193"
    ["proj_0.txt"]="91"
    ["proj_3.txt"]="270"
    ["prxy_0.txt"]="63"
    ["rsrch_0.txt"]="17"
    ["rsrch_2.txt"]="68"
    ["src1_2.txt"]="81"
    ["src2_0.txt"]="41"
    ["src2_1.txt"]="981"
    ["src2_2.txt"]="1040"
    ["stg_1.txt"]="4075"
    ["ts_0.txt"]="51"
    ["usr_0.txt"]="109"
    ["wdev_0.txt"]="41"
    ["web_0.txt"]="369"
    ["web_1.txt"]="188"
    ["web_3.txt"]="46"
    ["prn_1.txt"]="3779"
    ["web_2.txt"]="3440"
    ["proj_2.txt"]="20990"
    ["ali-dev-3.txt"]="8400"
    ["ali-dev-5.txt"]="91"
)

# 规范的目录结构为 /home/hb/spdk_fio/result/8u16g_ocf_seq_large+ali-dev-5.txt/nvme0n1/fio_result.log

# 遍历 result_dir 目录下的所有 fio_result.log 文件
find "$result_dir" -name "fio_result.log" | while read -r file; do
    # 提取 pattern 和 fio_replay_trace
    dir_path=$(dirname "$(dirname "$file")")
    pattern_fio=$(basename "$dir_path")
    
    # 从路径中提取 Trace 名称（支持 Trace 名称中包含下划线）
    trace_name=$(echo "$pattern_fio" | grep -oP '[^+]+\.txt')
    
    # 获取对应的缓存大小
    cache_sizes=${replay_trace_config[$trace_name]}
    
    # 如果没有找到对应的 Trace，跳过
    if [[ -z "$cache_sizes" ]]; then
        echo "Warning: No cache size found for Trace $trace_name in $file"
        continue
    fi
    
    # 提取 IOPS 和 BW 的值
    iops=$(grep -oP 'read: IOPS=\K[0-9.]+[kK]?' "$file")
    bw=$(grep -oP 'read: IOPS=[0-9.]+[kK]?, BW=\K[0-9.]+' "$file")

    # 处理 IOPS 的单位转换（将 K 转换为 1000）
    if echo "$iops" | grep -qi 'k'; then
        iops=$(echo "$iops" | sed 's/[kK]//g')
        iops=$(echo "$iops * 1000" | bc)
    fi
    
    # 将结果追加到汇总 CSV 文件
    for cache_size in $cache_sizes; do
        echo "$trace_name,$cache_size,$iops,$bw" >> "$summary_csv"
    done
    
    echo "Processed $file"
done

echo "All files processed. Summary CSV saved to $summary_csv"#     
