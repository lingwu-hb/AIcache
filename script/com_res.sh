#!/bin/bash

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 如果没有提供参数，自动查找最新的两个结果文件
if [ "$#" -eq 0 ]; then
    # 获取当前日期目录
    current_date=$(date +%Y-%m-%d)
    csv_dir="${CSV_PATH}/${current_date}"

    if [ ! -d "$csv_dir" ]; then
        echo -e "${ERROR} 当天结果目录不存在: ${csv_dir}"
        exit 1
    fi

    # 查找最新的两个result_*.csv文件
    files=($(ls -t ${csv_dir}/result_*.csv 2>/dev/null | head -n 2))
    if [ ${#files[@]} -lt 2 ]; then
        echo -e "${ERROR} 未找到足够的结果文件用于比较"
        echo "Usage: $0 [csv_file1] [csv_file2]"
        exit 1
    fi
    csv_file1="${files[0]}"
    csv_file2="${files[1]}"
    echo -e "${INFO} 自动选择最新的两个结果文件进行比较:"
    echo "文件1: $(basename ${csv_file1})"
    echo "文件2: $(basename ${csv_file2})"
elif [ "$#" -eq 2 ]; then
    csv_file1="$1"
    csv_file2="$2"
else
    echo "Usage: $0 [csv_file1] [csv_file2]"
    echo "如果不提供参数，将自动比较当天最新的两个结果文件"
    exit 1
fi

# 检查文件是否存在
if [ ! -f "$csv_file1" ] || [ ! -f "$csv_file2" ]; then
    echo -e "${ERROR} 输入文件不存在"
    exit 1
fi

# 创建比较结果目录
output_dir="${CSV_PATH}/res_compare"
mkdir -p "$output_dir"

# 定义输出文件名
timestamp=$(date +%Y%m%d_%H%M)
output_csv="${output_dir}/com_${timestamp}.csv"

# 初始化输出 CSV 文件，写入表头
echo "Trace,Cache Size,IOPS1,IOPS2,IOPS(%),BW1(MiB/s),BW2(MiB/s),BW(%)" >"$output_csv"

# 读取第一个 CSV 文件的内容到关联数组
declare -A file1_data
while IFS=, read -r trace cache_size iops bw _; do
    if [[ "$trace" != "Trace" ]]; then # 跳过表头
        file1_data["$trace"]="$cache_size,$iops,$bw"
    fi
done <"$csv_file1"

# 读取第二个 CSV 文件的内容并比较
total_iops_percent=0
total_bw_percent=0
count=0

while IFS=, read -r trace cache_size iops bw _; do
    if [[ "$trace" != "Trace" && -n "${file1_data[$trace]}" ]]; then # 跳过表头并检查是否存在相同 Trace
        # 提取第一个文件中的数据
        IFS=, read -r cache_size1 iops1 bw1 <<<"${file1_data[$trace]}"

        # 计算 IOPS 和 BW 的百分比变化
        iops_percent=$(echo "scale=2; ($iops - $iops1) / $iops1 * 100" | bc)
        bw_percent=$(echo "scale=2; ($bw - $bw1) / $bw1 * 100" | bc)

        # 将结果写入输出 CSV 文件
        echo "$trace,$cache_size,$iops1,$iops,$iops_percent,$bw1,$bw,$bw_percent" >>"$output_csv"

        # 累加百分比值
        total_iops_percent=$(echo "$total_iops_percent + $iops_percent" | bc)
        total_bw_percent=$(echo "$total_bw_percent + $bw_percent" | bc)
        count=$((count + 1))
    fi
done <"$csv_file2"

# 计算平均值
if [ "$count" -gt 0 ]; then
    avg_iops_percent=$(echo "scale=2; $total_iops_percent / $count" | bc)
    avg_bw_percent=$(echo "scale=2; $total_bw_percent / $count" | bc)

    # 将平均值写入输出 CSV 文件的最后一行
    echo "Average,,,,$avg_iops_percent,,,$avg_bw_percent" >>"$output_csv"

    echo -e "${INFO} 比较完成. 结果已保存到: ${output_csv}"
    echo -e "${INFO} 平均性能变化:"
    echo "IOPS: ${avg_iops_percent}%"
    echo "带宽: ${avg_bw_percent}%"

    # 转换为Excel格式
    echo -e "${INFO} 正在生成Excel文件..."
    if python3 ${SCRIPT_DIR}/csv2xlsx.py "${output_csv}"; then
        echo -e "${INFO} Excel文件已生成"
    else
        echo -e "${WARNING} Excel文件生成失败，请检查是否安装了必要的Python包"
        echo "提示: pip3 install pandas xlsxwriter"
    fi
fi
