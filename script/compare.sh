#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh


# compare the two csv result file
# 执行示例：sudo sh com_res.sh /home/hb/res_analyse/csv/2025-03-05/result_2025-03-05_18-44-17.csv 
#                             /home/hb/res_analyse/csv/2025-03-05/result_2025-03-05_18-45-08.csv
# 检查参数数量
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <csv_file1> <csv_file2>"
    exit 1
fi

# 定义输入文件和输出目录
csv_file1="$1"
csv_file2="$2"
output_dir="${CSV_PATH}"

# 定义输出文件名
output_csv="$output_dir/com_$(basename "${csv_file1%.*}")_and_$(basename "${csv_file2%.*}").csv"

# 初始化输出 CSV 文件，写入表头
echo "Trace,Cache Size,IOPS1,IOPS2,IOPS(%),BW1(MiB/s),BW2(MiB/s),BW(%)" > "$output_csv"

# 读取第一个 CSV 文件的内容到关联数组
declare -A file1_data
while IFS=, read -r trace cache_size iops bw; do
    if [[ "$trace" != "Trace" ]]; then  # 跳过表头
        file1_data["$trace"]="$cache_size,$iops,$bw"
    fi
done < "$csv_file1"

# 读取第二个 CSV 文件的内容并比较
total_iops_percent=0
total_bw_percent=0
count=0

while IFS=, read -r trace cache_size iops bw; do
    if [[ "$trace" != "Trace" && -n "${file1_data[$trace]}" ]]; then  # 跳过表头并检查是否存在相同 Trace
        # 提取第一个文件中的数据
        IFS=, read -r cache_size1 iops1 bw1 <<< "${file1_data[$trace]}"
        
        # 计算 IOPS 和 BW 的百分比
        iops_percent=$(echo "scale=2; ($iops - $iops1) / $iops1 * 100" | bc)
        bw_percent=$(echo "scale=2; ($bw - $bw1) / $bw1 * 100" | bc)
        
        # 将结果写入输出 CSV 文件
        echo "$trace,$cache_size,$iops1,$iops,$iops_percent,$bw1,$bw,$bw_percent" >> "$output_csv"
        
        # 累加百分比值
        total_iops_percent=$(echo "$total_iops_percent + $iops_percent" | bc)
        total_bw_percent=$(echo "$total_bw_percent + $bw_percent" | bc)
        count=$((count + 1))
    fi
done < "$csv_file2"

# 计算平均值
if [ "$count" -gt 0 ]; then
    avg_iops_percent=$(echo "scale=2; $total_iops_percent / $count" | bc)
    avg_bw_percent=$(echo "scale=2; $total_bw_percent / $count" | bc)
    
    # 将平均值写入输出 CSV 文件的最后一行
    echo "Average,,,$avg_iops_percent,,,$avg_bw_percent" >> "$output_csv"
fi

echo "Comparison completed. Results saved to $output_csv"




# #!/bin/bash

# # 定义目录
# result_dir="/home/lzq/spdk_fio/result"
# output_dir="/home/lzq/res_analyse/csv"

# # 获取当前日期和时间（格式：YYYY-MM-DD_HH-MM-SS）
# timestamp=$(date +%Y-%m-%d_%H-%M-%S)

# # 获取当前日期（格式：YYYY-MM-DD），如果失败则使用默认值
# current_date=$(date +%Y-%m-%d 2>/dev/null || echo "unknown_date")

# # 在 output_dir 下创建日期子目录
# output_dir_with_date="$output_dir/$current_date"
# mkdir -p "$output_dir_with_date"


# # TODO: 考虑在文件名中增加使用的算法模式

# # 定义汇总的 CSV 文件路径
# summary_csv="$output_dir_with_date/result_${timestamp}.csv"

# # 初始化汇总 CSV 文件，写入表头
# echo "Trace,Cache Size,IOPS,BW(MiB/s)" > "$summary_csv"

# # 定义 Trace 和缓存大小的映射关系
# declare -A replay_trace_config=(
#     ["ali-dev-3.txt"]="8200"
#     ["ali-dev-5.txt"]="91"
#     ["mds_1.txt"]="4864"
#     ["prn_0.txt"]="679"
#     ["proj_0.txt"]="167"
#     ["proj_3.txt"]="2261"
#     ["prxy_0.txt"]="213"
#     ["rsrch_0.txt"]="173"
#     ["rsrch_2.txt"]="799"
#     ["src1_2.txt"]="82"
#     ["src2_0.txt"]="161"
#     ["src2_1.txt"]="1736"
#     ["src2_2.txt"]="1736"
#     ["stg_1.txt"]="1039"
#     ["ts_0.txt"]="225"
#     ["usr_0.txt"]="109"
#     ["wdev_0.txt"]="120"
#     ["web_0.txt"]="348"
#     ["web_1.txt"]="695"
#     ["web_3.txt"]="1735"
#     ["prn_1.txt"]="3948"
# )

# # 规范的目录结构为 /home/lzq/spdk_fio/result/8u16g_ocf_seq_large+ali-dev-5.txt/nvme0n1/fio_result.log

# # 遍历 result_dir 目录下的所有 fio_result.log 文件
# find "$result_dir" -name "fio_result.log" | while read -r file; do
#     # 提取 pattern 和 fio_replay_trace
#     dir_path=$(dirname "$(dirname "$file")")
#     pattern_fio=$(basename "$dir_path")
    
#     # 从路径中提取 Trace 名称（支持 Trace 名称中包含下划线）
#     trace_name=$(echo "$pattern_fio" | grep -oP '[^+]+\.txt')
    
#     # 获取对应的缓存大小
#     cache_sizes=${replay_trace_config[$trace_name]}
    
#     # 如果没有找到对应的 Trace，跳过
#     if [[ -z "$cache_sizes" ]]; then
#         echo "Warning: No cache size found for Trace $trace_name in $file"
#         continue
#     fi
    
#     # 提取 IOPS 和 BW 的值
#     iops=$(grep -oP 'read: IOPS=\K[0-9.]+[kK]?' "$file")
#     bw=$(grep -oP 'read: IOPS=[0-9.]+[kK]?, BW=\K[0-9.]+' "$file")

#     # 处理 IOPS 的单位转换（将 K 转换为 1000）
#     if echo "$iops" | grep -qi 'k'; then
#         iops=$(echo "$iops" | sed 's/[kK]//g')
#         iops=$(echo "$iops * 1000" | bc)
#     fi
    
#     # 将结果追加到汇总 CSV 文件
#     for cache_size in $cache_sizes; do
#         echo "$trace_name,$cache_size,$iops,$bw" >> "$summary_csv"
#     done
    
#     echo "Processed $file"
# done

# echo "All files processed. Summary CSV saved to $summary_csv"
