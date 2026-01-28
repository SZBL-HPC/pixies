#!/bin/bash
#SBATCH --job-name=my_gpu_cpu_monitor
#SBATCH --partition=NV_4090D
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=32
#SBATCH --gres=gpu:4
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

# ---------- CSV header ----------
echo "timestamp,gpu_index,gpu_name,memory_total_MiB,memory_used_MiB,utilization_gpu_percent,utilization_memory_percent,power_draw_W,temperature_C,clocks_gr_MHz,cpu_total_percent,cpu_mem_used_MiB" > $LOGFILE

# -------- 启动 Python 作业 ---------
srun --ntasks=1 --cpu-bind=none /lenovofs1/share/hpc_core/pixi/bin/pixi run -m /lenovofs1/home/xshu/git/pixies/clair3 bash -c '
INPUT_DIR=$PIXI_PROJECT_ROOT/data
OUTPUT_DIR=$PIXI_PROJECT_ROOT/out
MODEL_NAME=hifi_revio
THREADS=32

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

# -------- 启动后台循环监控 GPU + 作业 CPU/内存 ---------
(
while kill -0 $JOB_PID 2>/dev/null; do
    TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)

    # CPU / MEM（按 PPID，安全）
    read CPU_TOTAL MEM_TOTAL <<EOF
$(ps -eo pid,ppid,%cpu,rss | awk -v p="$JOB_PID" '
$1==p || $2==p { cpu+=$3; mem+=$4 }
END { printf "%.2f %.1f", cpu, mem/1024 }
')
EOF

    # GPU 信息循环
    nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu,utilization.memory,power.draw,temperature.gpu,clocks.gr \
               --format=csv,noheader,nounits | \
    while IFS=, read -r IDX NAME MEM_TOTAL_GPU MEM_USED_GPU UTIL_GPU UTIL_MEM POWER TEMP CLOCK; do
        echo "$TIMESTAMP,$IDX,$NAME,$MEM_TOTAL_GPU,$MEM_USED_GPU,$UTIL_GPU,$UTIL_MEM,$POWER,$TEMP,$CLOCK,$CPU_TOTAL,$MEM_TOTAL" >> $LOGFILE
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
