# 官方 HREX 示例数据

本目录来自 PLUMED Masterclass 22.10 的官方仓库：

`https://github.com/plumed/masterclass-22-10`

运行数据是 alanine dipeptide in water，包括 `conf.gro`、`topol.top`、`grompp.mdp` 和 `ala.pdb`。
`test.sbatch` 在服务器上的 `ROOT` 下直接读取本目录；模拟产生的 replica 和输出写入 `ROOT/test/hrex-${SLURM_JOB_ID}`，不会修改这些输入文件。

Slurm 的 `.out`、`.err` 日志和临时文件放在 `ROOT/tmp/`，其中 `ROOT=/lustre/software/pixi/gromacs-plumed-hpc`。
提交前先创建该目录，因为 Slurm 会在执行脚本之前打开日志文件：

```bash
mkdir -p /lustre/software/pixi/gromacs-plumed-hpc/tmp
sbatch /lustre/software/pixi/gromacs-plumed-hpc/test.sbatch
```
