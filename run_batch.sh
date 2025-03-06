#!/bin/bash
# Source configuration
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
source ${SCRIPT_DIR}/config.sh

replay_trace_config=(

	# "ali-dev-3.txt 91"
	"ali-dev-5.txt 91"
	# "hm_0.txt 96"
	"mds_1.txt 4300"
	"prn_0.txt 193"
	"proj_0.txt 91"
	# "proj_3.txt 270"
	#"prxy_0.txt 63"
	"rsrch_0.txt 17"
	#"rsrch_2.txt 68"
	"src1_2.txt 81"
	#"src2_0.txt 41"
	# "src2_1.txt 981"
	# "src2_2.txt 1040"
	# "stg_1.txt 4075"
	#"ts_0.txt 51"
	# "usr_0.txt 109"
	# "wdev_0.txt 41"
	# "web_0.txt 369"
	# "web_1.txt 188"
	#"web_3.txt 46"
	# "prn_1.txt 3779"
	# "web_2.txt 3440"
	#"proj_2.txt 20990"
)

algo_config=(
	#"baseline" #不开缓存
	#"ocf_nopf"
	"ocf_seq_large"
	#"ocf_seq"
	#"seq_512"
	#"seq_64_512"
	#"seq_4reqlen"
	#"seq_4reqlen_bind"
	#"var_max"
	#"fix_max_512"
	#"fix_max_64"

	#"das-ori"
	#"das-bind"
	#"das-bind-adaptive"
	#"das-bind-adaptive-64k"
	#"das-bind-adaptive-64k-feedback"
	#"das-bind-adaptive-64k-feedback-distance"
	#"belief_io"
	#"belief_page"
	#"belief_ori"
	#"belief_io_5552"
	#"no_prefetch"
	#"belief_io_5550"
	# "belief_io_5553"
	#"belief_io"
	#"no_prefetch"
	#"belief_io_10553"
	#"no_prefetch"
	#"belief_page_5550"
	#"belief_page_10550"
	#"belief_page_20550"
	#"belief_page_30550"
	#"no_prefetch"
	#"das_belief"
	#"seq_8"
	#"seq_64_256"
)
#ocf_seq

for algo in "${algo_config[@]}"; do
	for relplay_trace in "${replay_trace_config[@]}"; do
		sh start_vms_vfio.sh 1 ${algo} ${relplay_trace}
	done
done
