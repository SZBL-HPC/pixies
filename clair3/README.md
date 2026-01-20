# Clair3 GPU

## install

### For Linux with glibc 2.17

Conda-forge cuda packages are not aviliable for glibc < 2.28.

```bash
singularity pull docker://hkubal/clair3-gpu:latest
```

### For Linux with glibc 2.28

```bash
cd clair3
pixi run install
```
## Run

```bash
INPUT_DIR=/lenovofs1/home/xshu/git/pixies/clair3/data
OUTPUT_DIR=/lenovofs1/home/xshu/git/pixies/clair3/out
MODEL_NAME=hifi_revio
THREADS=32

singularity exec --nv -B ${INPUT_DIR},${OUTPUT_DIR} ~/clair3-gpu_latest.sif /opt/bin/run_clair3.sh --use_gpu --bam_fn=${INPUT_DIR}/BA041-chr10.bam --ref_fn=${INPUT_DIR}/resources_broad_hg38_v0_Homo_sapiens_assembly38.fasta --threads=${THREADS} --platform="hifi" --model_path="/opt/models/${MODEL_NAME}" --output=${OUTPUT_DIR}

./Clair3/run_clair3.sh --use_gpu --bam_fn=${INPUT_DIR}/BA041-chr10.bam --ref_fn=${INPUT_DIR}/resources_broad_hg38_v0_Homo_sapiens_assembly38.fasta --threads=${THREADS} --platform="hifi" --model_path="${CONDA_PREFIX}/bin/models/${MODEL_NAME}" --output=${OUTPUT_DIR}
```
