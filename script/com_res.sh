#!/bin/bash


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
out_dir="/home/hb/res_analyse/csv"
output_dir="${out_dir}/res_compare"
mkdir -p "$output_dir"

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
        iops_percent=$(echo "scale=8; ($iops - $iops1) / $iops1 * 100" | bc)
        bw_percent=$(echo "scale=8; ($bw - $bw1) / $bw1 * 100" | bc)
        
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
    avg_iops_percent=$(echo "scale=8; $total_iops_percent / $count" | bc)
    avg_bw_percent=$(echo "scale=8; $total_bw_percent / $count" | bc)
    
    # 将平均值写入输出 CSV 文件的最后一行
    echo "Average,,,,$avg_iops_percent,,,$avg_bw_percent" >> "$output_csv"
fi

echo "Comparison completed. Results saved to $output_csv"#                                                         
