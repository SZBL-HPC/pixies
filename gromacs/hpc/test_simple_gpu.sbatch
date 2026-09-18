#!/usr/bin/env bash
#SBATCH -J hrex-simple-gpu
#SBATCH -p gpu-2-h
#SBATCH -N 2
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:2
#SBATCH --export=NONE
#SBATCH -o hrex-simple-gpu-%j.out
#SBATCH -e hrex-simple-gpu-%j.err

set -eo pipefail

PIXI_DIR="/lustre/software/pixi/gromacs-plumed-hpc"
ROOT="$SLURM_SUBMIT_DIR"
DATA_DIR="$ROOT/hrex-data"
RUN_DIR="$ROOT/test/hrex-simple-${SLURM_JOB_ID:-manual}"
TMP_DIR="$ROOT/tmp"

SRC_DATA_DIR="$PIXI_DIR/hrex-data"
if [ ! -d "$DATA_DIR" ] || [ -z "$(find "$DATA_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "Initializing HREX data: $DATA_DIR"
    mkdir -p "$DATA_DIR"
    cp -a "$SRC_DATA_DIR"/. "$DATA_DIR"/
fi

mkdir -p "$TMP_DIR"
export TMPDIR="$TMP_DIR"
export TMP="$TMP_DIR"
export TEMP="$TMP_DIR"
export PIXI_CACHE_DIR="$TMP_DIR/pixi-cache"

eval "$(/lustre/software/pixi/pixi shell-hook --as-is -m "$PIXI_DIR/pixi.toml")"
export SLURM_EXPORT_ENV=ALL

export OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK"
export OMP_PLACES=cores
export OMP_PROC_BIND=close
export GMX_PME_NUM_THREADS=1
export GMX_FORCE_GPU_AWARE_MPI=1

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
cp "$DATA_DIR/conf.gro" "$RUN_DIR/"
cp "$DATA_DIR/topol.top" "$RUN_DIR/"

NSTEPS="${HREX_NSTEPS:-10000}"
REPLEX="${HREX_REPLEX:-100}"
awk '!/^(nsteps|nstlog|nstenergy|nstxout-compressed|nstlist|continuation|gen-vel|gen-temp|gen-seed)[[:space:]]*=/' \
    "$DATA_DIR/grompp.mdp" > "$RUN_DIR/md.mdp"
cat >> "$RUN_DIR/md.mdp" <<EOF
nsteps             = $NSTEPS
nstlist            = $REPLEX
nstlog             = $REPLEX
nstenergy          = $REPLEX
nstxout-compressed = $REPLEX
continuation       = no
gen-vel            = yes
gen-temp           = 300
EOF

gmx_mpi grompp -f "$RUN_DIR/md.mdp" -c "$RUN_DIR/conf.gro" \
    -p "$RUN_DIR/topol.top" -pp "$RUN_DIR/processed.top" -o "$RUN_DIR/base.tpr"

printf '%s\n' \
    'd: DISTANCE ATOMS=1,2' \
    "PRINT ARG=d FILE=COLVAR STRIDE=$REPLEX" \
    > "$RUN_DIR/plumed.dat"

awk '
    /^\[ *moleculetype *\]/{section="moleculetype"; print; next}
    /^\[ *atoms *\]/{section="atoms"; print; next}
    /^\[/{section="other"}
    section == "moleculetype" && $1 !~ /^[;#]/ && NF {molecule=$1}
    section == "atoms" && molecule == "Protein" && $1 ~ /^[0-9]+$/ {$2=$2 "_"; selected++}
    {print}
    END {if (selected != 22) exit 1}
' "$RUN_DIR/processed.top" > "$RUN_DIR/scaled.top"

for replica in 0 1 2 3; do
    replica_dir="$RUN_DIR/replica${replica}"
    mkdir -p "$replica_dir"
    cp "$RUN_DIR/conf.gro" "$replica_dir/conf.gro"
    cp "$RUN_DIR/md.mdp" "$replica_dir/md.mdp"
    lambda=$(awk -v replica="$replica" 'BEGIN {printf "%.6f", 1.0 - 0.1 * replica}')
    plumed partial_tempering "$lambda" < "$RUN_DIR/scaled.top" > "$replica_dir/topol.top"
    printf 'gen-seed = %d\n' "$((1000 + replica))" >> "$replica_dir/md.mdp"
    gmx_mpi grompp -f "$replica_dir/md.mdp" -c "$replica_dir/conf.gro" \
        -p "$replica_dir/topol.top" -o "$replica_dir/topol.tpr"
done

cd "$RUN_DIR"
mpirun -np "$SLURM_NTASKS" \
    --map-by "ppr:${SLURM_NTASKS_PER_NODE}:node:pe=${OMP_NUM_THREADS}" \
    --bind-to core \
    -x PATH \
    -x LD_LIBRARY_PATH \
    gmx_mpi mdrun \
        -multidir replica0 replica1 replica2 replica3 \
    -replex "$REPLEX" \
    -hrex \
    -plumed "$RUN_DIR/plumed.dat" \
    -dlb no \
    -notunepme \
    -ntomp "$OMP_NUM_THREADS" \
    -pin on \
    -nb gpu \
    -pme gpu
