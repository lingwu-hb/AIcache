#!/bin/bash
# Improved script for parsing FIO test results

# Exit on any error
set -e

# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

# Validate required variables
if [[ -z "${FIO_PATH}" || -z "${CSV_PATH}" ]]; then
    echo "Error: Required variables FIO_PATH or CSV_PATH not set in config.sh"
    exit 1
fi

result_dir=${FIO_PATH}
output_dir=${CSV_PATH}

# Get current timestamp and date
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
current_date=$(date +%Y-%m-%d 2>/dev/null || echo "unknown_date")

# Create date subdirectory in output_dir
output_dir_with_date="$output_dir/$current_date"
mkdir -p "$output_dir_with_date"

# Define summary CSV file path
summary_csv="$output_dir_with_date/result_${timestamp}.csv"

# Initialize summary CSV file with header
echo "Trace,Cache Size,IOPS,BW(MiB/s),Timestamp" >"$summary_csv"

# Define function to extract and process data
process_fio_result() {
    local file=$1
    local summary_file=$2

    # Extract pattern and trace from path
    local dir_path=$(dirname "$(dirname "$file")")
    local pattern_fio=$(basename "$dir_path")

    # Extract trace name using pattern matching
    local trace_name=$(echo "$pattern_fio" | grep -oP '[^+]+\.txt' || echo "unknown_trace")

    # Skip if trace name couldn't be extracted
    if [[ "$trace_name" == "unknown_trace" ]]; then
        echo "Warning: Could not extract trace name from $pattern_fio"
        return 1
    fi

    # Extract CACHE_SIZE and TIMESTAMP from file metadata
    local cache_size=""
    local timestamp=""

    # Try to extract metadata from file
    if grep -q "# TEST_METADATA:" "$file"; then
        cache_size=$(grep "# TEST_METADATA:" "$file" | grep -oP "CACHE_SIZE=\K[^,]+" || echo "")
        timestamp=$(grep "# TEST_METADATA:" "$file" | grep -oP "TIMESTAMP=\K[^,\s]+" || echo "")
    fi

    # If no cache_size found, use "unknown"
    if [[ -z "$cache_size" ]]; then
        cache_size="unknown"
        echo "Warning: No cache size found for $trace_name, using 'unknown'"
    fi

    # Extract IOPS and bandwidth
    local iops=$(grep -oP "IOPS=\K[\d\.]+" "$file" | tail -1)
    local bw=$(grep -oP "BW=\K[\d\.]+MiB/s" "$file" | sed 's/MiB\/s//' | tail -1)

    # If extraction successful, write to summary CSV
    if [[ -n "$iops" && -n "$bw" ]]; then
        echo "$trace_name,$cache_size,$iops,$bw,$timestamp" >>"$summary_file"
        echo "Processed: $trace_name (IOPS: $iops, BW: $bw MB/s, Cache Size: $cache_size, Timestamp: $timestamp)"
    else
        echo "Warning: Could not extract IOPS or BW from $file"
    fi
}

# Process all FIO result files
echo "Starting to process FIO result files..."
find "$result_dir" -name "*_fio_result.log" | while read -r file; do
    process_fio_result "$file" "$summary_csv"
done

echo "Processing complete. Results saved to $summary_csv"
