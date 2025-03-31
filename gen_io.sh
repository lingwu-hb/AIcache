# 示例路径：rawfio/das-bind+ali-dev-3.txt/0317_1905/fio_result.log
# 示例路径：rawfio/no_prefetch+ali-dev-3.txt/0317_1905/fio_result.log
# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# 获取当前日期和时间（格式：YYYY-MM-DD_HH-MM-SS）
timestamp=$(date +%Y-%m-%d_%H-%M-%S)

# 获取当前日期（格式：YYYY-MM-DD）
current_date=$(date +%Y-%m-%d 2>/dev/null || echo "unknown_date")

# 在 CSV_PATH 下创建日期子目录
output_dir_with_date="${CSV_PATH}/${current_date}"
mkdir -p "$output_dir_with_date"

# 定义汇总的 CSV 文件路径
summary_csv="${output_dir_with_date}/result_${timestamp}.csv"
temp_csv="${output_dir_with_date}/temp_${timestamp}.csv"

# 创建临时文件存储所有结果
>"$temp_csv"

# 初始化汇总 CSV 文件，写入表头
echo "Trace,Cache Size,KIOPS,BW(MiB/s),Timestamp,Pattern,Algorithm,VM Type" >"$summary_csv"

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
    ["ali-dev-3-part-*"]="683"
)

# 遍历 result_dir 目录下的所有 fio_result.log 文件
# 首先找到每个配置目录下最新的时间戳文件夹
find "$FIO_PATH" -mindepth 2 -maxdepth 2 -type d | while read -r config_dir; do
    # 获取配置目录的父目录（去掉时间戳部分）
    base_config_dir=$(dirname "$config_dir")

    # 在父目录下获取最新的时间戳文件夹
    latest_timestamp_dir=$(ls -td "$base_config_dir"/*/ 2>/dev/null | head -n1)

    if [ -z "$latest_timestamp_dir" ]; then
        echo "Warning: No timestamp directories found in $base_config_dir"
        continue
    fi

    # 处理最新时间戳文件夹下的 fio_result.log
    file="$latest_timestamp_dir/fio_result.log"
    if [ ! -f "$file" ]; then
        echo "Warning: No fio_result.log found in $latest_timestamp_dir"
        continue
    fi

    # 提取路径信息
    dir_path=$(dirname "$(dirname "$file")")
    pattern_full=$(basename "$dir_path")
    timestamp_dir=$(basename "$(dirname "$file")")

    # 提取算法名称（+号前的部分）和trace名称（+号后的部分）
    algorithm=${pattern_full%%+*}
    trace_name=${pattern_full#*+}

    # 设置其他字段的默认值
    vm_type="unknown"
    pattern="unknown"
    cache_config="unknown"

    # 从文件末尾的 TEST_METADATA 标签中获取 cache_size 和时间戳
    metadata_line=$(grep "TEST_METADATA:" "$file" || echo "")
    if [[ $metadata_line =~ CACHE_SIZE=([0-9]+),\ *TIMESTAMP=([0-9_]+) ]]; then
        cache_sizes="${BASH_REMATCH[1]}"
        test_timestamp="${BASH_REMATCH[2]}"
    else
        # 如果没有找到 metadata，使用原来的方式作为备选
        if [[ $trace_name =~ ^ali-dev-3-part-[0-9]$ ]]; then
            cache_sizes="683"
        else
            cache_sizes=${replay_trace_config[$trace_name]}
        fi
        test_timestamp=$timestamp_dir
    fi

    # 如果没有找到对应的 cache_size，跳过
    if [[ -z "$cache_sizes" ]]; then
        echo "Warning: No cache size found for Trace $trace_name in $file"
        continue
    fi

    # 提取 IOPS 和 BW 的值
    # IOPS格式可能是: "read: IOPS=7538" 或 "read: IOPS=7.5k"
    iops_line=$(grep "read: IOPS=" "$file" || echo "")
    if [[ $iops_line =~ IOPS=([0-9.]+)k ]]; then
        # 如果是k单位，直接使用数值
        kiops=${BASH_REMATCH[1]}
    else
        # 如果没有单位，需要除以1000
        raw_iops=$(echo "$iops_line" | grep -oP 'IOPS=\K[0-9.]+' || echo "0")
        kiops=$(echo "scale=2; $raw_iops / 1000" | bc)
    fi

    # BW格式示例: "READ: bw=233MiB/s (244MB/s)"
    bw=$(grep "READ: bw=" "$file" | grep -oP 'bw=\K[0-9.]+(?=MiB/s)' ||
        grep "READ: bw=" "$file" | grep -oP '[0-9.]+(?=MB/s)' || echo "0")

    # 单位转换：BW默认单位是MiB/s或MB/s，统一使用MiB/s
    if grep "READ: bw=" "$file" | grep -q 'MiB/s'; then
        bw=$(echo "$bw" | bc -l | awk '{printf "%.2f", $0}')
    fi

    # 使用时间戳目录作为时间戳
    test_timestamp=$timestamp_dir

    # 存储测试结果（按新格式存储）
    # 直接写入临时文件，不使用关联数组
    echo "$trace_name,$cache_sizes,$kiops,$bw,$test_timestamp,$pattern,$algorithm,$vm_type" >>"$temp_csv"

    echo "Processing $file:"
    # echo "  Trace: $trace_name"
    # echo "  KIOPS: $kiops"
    # echo "  BW(MiB/s): $bw"
    # echo "  Timestamp: $test_timestamp"
    # echo "  Pattern: $pattern"
    # echo "  Algorithm: $algorithm"
    # echo "  VM Type: $vm_type"
    # echo "  Cache Size: $cache_sizes"
done

# 对临时文件进行排序（按trace名称排序）
sort -t',' -k1 "$temp_csv" >"${temp_csv}.sorted"

# 合并表头和排序后的数据
cat "$summary_csv" "${temp_csv}.sorted" >"${summary_csv}.tmp" && mv "${summary_csv}.tmp" "$summary_csv"

# 清理临时文件
rm -f "$temp_csv" "${temp_csv}.sorted"

echo "All files processed. Summary CSV saved to $summary_csv"

# 服务器暂时装不了panda包
# # 转换CSV到XLSX并追加到结果文件
# if command -v python3 >/dev/null 2>&1; then
#     echo "Converting CSV to XLSX..."
#     chmod +x "${SCRIPT_DIR}/script/csv2xlsx.py"
#     chmod +x "${SCRIPT_DIR}/script/append_results.py"

#     # 先转换为xlsx
#     xlsx_file="${summary_csv%.csv}.xlsx"
#     python3 "${SCRIPT_DIR}/script/csv2xlsx.py" "$summary_csv"

#     # 然后追加到汇总结果文件
#     echo "Appending results to summary file..."
#     python3 "${SCRIPT_DIR}/script/append_results.py" "$xlsx_file"
# else
#     echo "Warning: Python3 not found, skipping XLSX conversion and appending"
# fi
