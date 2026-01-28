#!/bin/bash
#SBATCH --job-name=my_gpu_cpu_monitor
#SBATCH --partition=NV_4090D
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=16
#SBATCH --gres=gpu:2
#SBATCH --time=08:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

#cd /lenovofs1/home/xshu/git/pixies/clair3/

INTERVAL=10
LOGFILE="usage_${SLURM_JOB_ID}.csv"

# ---------- 固定信息 ----------
echo "===== Job info ====="
echo "JobID: $SLURM_JOB_ID"
echo "Node : $(hostname)"
echo "Start: $(date)"
echo "===================="

echo "===== GPU static info ====="
nvidia-smi
echo "==========================="

# -------- 启动 Python 作业 ---------
/lenovofs1/share/hpc_core/pixi/bin/pixi run -m /lenovofs1/home/xshu/git/pixies/clair3 bash -c '
INPUT_DIR=$PIXI_PROJECT_ROOT/data
OUTPUT_DIR=$PIXI_PROJECT_ROOT/out
MODEL_NAME=hifi_revio
THREADS=$SLURM_NTASKS_PER_NODE

rm -fr $OUTPUT_DIR

$PIXI_PROJECT_ROOT/Clair3/run_clair3.sh \
    --use_gpu \
    --bam_fn=$INPUT_DIR/BA041-chr10.bam \
    --ref_fn=$INPUT_DIR/resources_broad_hg38_v0_Homo_sapiens_assembly38.fasta \
    --threads=$THREADS \
    --platform="hifi" \
    --model_path="$CONDA_PREFIX/bin/models/$MODEL_NAME" \
    --output=$OUTPUT_DIR
' &
JOB_PID=$!

taskset -cp $JOB_PID

pstree -p $JOB_PID

scontrol listpids $SLURM_JOB_ID

# ---------- CSV header ----------
echo "timestamp,gpu_index,gpu_name,memory_total_MiB,memory_used_MiB,utilization_gpu_percent,utilization_memory_percent,power_draw_W,temperature_C,clocks_gr_MHz,cpu_name,cpu_total_percent,pss_mem_used_MiB,rss_mem_used_MiB" > $LOGFILE

CPU_MODEL_CLEAN=$(
lscpu | gawk -F: '
BEGIN { IGNORECASE=1 }
/^Model name/ {
    s=$2
    gsub(/^[ \t]+/, "", s)
    # 绝对冗余
    gsub(/\((R|TM)\)/, "", s)
    gsub(/\<CPU\>/, "", s)
    gsub(/\<Processor\>/, "", s)
    # 空白规范化
    gsub(/[[:space:]]+/, " ", s)
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    print s
}'
)

# -------- 启动后台循环监控 GPU + 作业 CPU/内存 ---------
(
calc_pss_mib() {
    local pids=("$@")
    local total_kb=0
    for pid in "${pids[@]}"; do
        if [[ -r /proc/$pid/smaps_rollup ]]; then
            kb=$(awk '$1=="Pss:"{print $2}' /proc/$pid/smaps_rollup 2>/dev/null)
        elif [[ -r /proc/$pid/smaps ]]; then
            kb=$(awk '$1=="Pss:"{sum+=$2} END {print sum}' /proc/$pid/smaps 2>/dev/null)
        else
            continue
        fi
        total_kb=$(( total_kb + kb ))
    done
    awk "BEGIN { printf \"%.1f\", $total_kb/1024 }"
}

LOOP_COUNT=0
LAST_PSS_MIB=0

while kill -0 $JOB_PID 2>/dev/null; do
    TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)

    mapfile -t JOB_PIDS < <(
      scontrol listpids "$SLURM_JOB_ID" |
      awk '$3=="batch" {print $1}' |
      sort -u
    )

    read CPU_TOTAL RSS_MIB <<EOF
$(
  if ((${#JOB_PIDS[@]})); then
    printf "%s\n" "${JOB_PIDS[@]}" |
    xargs -r ps -o %cpu=,rss= -p |
    awk '
      { cpu += $1; mem += $2 }
      END { printf "%.2f %.1f", cpu, mem/1024 }
    '
  else
    printf "0.00 0.0"
  fi
)
EOF

    # ---- PSS 计算（老内核 + 短 INTERVAL 降频） ----
    if [[ ! -e /proc/$$/smaps_rollup && "$INTERVAL" -lt 10 ]]; then
        # 老内核（无 smaps_rollup）且采样很频繁
        if (( LOOP_COUNT % 6 == 0 )); then
            PSS_MIB=$(calc_pss_mib "${JOB_PIDS[@]}")
            LAST_PSS_MIB="$PSS_MIB"
        else
            PSS_MIB="$LAST_PSS_MIB"
        fi
    else
        # 新内核，或 INTERVAL 不小
        PSS_MIB=$(calc_pss_mib "${JOB_PIDS[@]}")
    fi
    ((LOOP_COUNT++))

    # GPU 信息循环
    nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu,utilization.memory,power.draw,temperature.gpu,clocks.gr \
               --format=csv,noheader,nounits | \
    while IFS=, read -r IDX NAME MEM_TOTAL_GPU MEM_USED_GPU UTIL_GPU UTIL_MEM POWER TEMP CLOCK; do
        if [[ "$IDX" == "0" ]]; then
            CPU_OUT=$CPU_TOTAL
            PSS_OUT=$PSS_MIB
            RSS_OUT=$RSS_MIB
        else
            CPU_OUT="."
            PSS_OUT="."
            RSS_OUT="."
        fi
        echo "$TIMESTAMP,$IDX,$NAME,$MEM_TOTAL_GPU,$MEM_USED_GPU,$UTIL_GPU,$UTIL_MEM,$POWER,$TEMP,$CLOCK,$CPU_MODEL_CLEAN,$CPU_OUT,$PSS_OUT,$RSS_OUT" >> $LOGFILE
    done

    sleep "$INTERVAL"
done
) &

MONITOR_PID=$!

# 等待 Python 作业结束
wait $JOB_PID

# 作业结束后杀掉监控循环
kill $MONITOR_PID
wait $MONITOR_PID 2>/dev/null

echo "===== Job finished ====="
echo "End: $(date)"
echo "Log: $LOGFILE"
