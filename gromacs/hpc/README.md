# HPC Runtime Environment

该目录是集群运行环境的最小 Pixi workspace，只支持 `linux-64`。
它不包含编译器、CMake、CUDA toolkit 或其他构建依赖；安装本地构建的 `gromacs-plumed` package 后，Pixi 只解析其运行时依赖。

OpenMPI 使用 conda-forge `mpi-external` label 中的 external package，实际运行时由集群上的 OpenMPI 5 module 和 `activate_mpi.sh` 提供。
`activate_mpi.sh` 是一个 `mode=755` 的普通文件，固定加载 `openmpi/5.0.8-gcc14.2.0`；如果当前机器没有对应的 module 系统，脚本会跳过 module 激活而不阻止环境加载。

## 安装

在包含 `hpc/` 和 `output/` 的项目目录中执行：

```bash
cp -srv hpc/ /path/to/target
cd /path/to/target
pixi add `readlink -f output/linux-64/gromacs-plumed-2023.5-mpi_openmpi_1.conda`
pixi install
```

上面的 `pixi add` 安装包含 `gmx_mpi`、`gmx_mpi_d` 和 `gmx_mpi_ocl` 三个可执行文件的合并 package。
`readlink -f` 需要在执行命令的目录中能够找到 `output/linux-64/`；如果 package 位于其他目录，可以直接把它替换为该 `.conda` 文件的绝对路径。

安装后从目标目录运行 `pixi shell`，或使用 `pixi run` 执行已安装的 GROMACS 命令。

## 运行测试

先在目标目录执行 `pixi shell`，再直接运行以下脚本：

```bash
./test-plumed.sh
./test-mdrun.sh
./test-mdrun.sh gpu
./test-hrex.sh
```

`test-mdrun.sh` 默认运行 CPU+MPI 测试，传入 `gpu` 时运行 CUDA GPU+MPI 测试。
`test-hrex.sh` 运行两个 replica 的 PLUMED Hamiltonian replica exchange，要求 GROMACS binary 提供 `mdrun -hrex`；当前 2023.5 和 2024.6 支持，2025.5 不支持。
测试输入和输出默认写入目标目录下的 `.test/`，可以通过 `HPC_TEST_ROOT` 指定其他目录。

## HREX 原理与运行步骤

HREX（Hamiltonian Replica Exchange，Hamiltonian replica exchange）同时运行多个相互关联的分子动力学模拟。每个模拟称为一个 **replica**，它们使用相同的初始体系和温度，但使用略有不同的 Hamiltonian（势能函数）。在本目录的 demo 中，4 个 replica 使用不同的 `lambda`：`1.0`、`0.9`、`0.8` 和 `0.7`；PLUMED `partial_tempering` 根据这些值生成各自的 topology。

之所以需要多个 replica，是因为单个 MD 模拟可能长时间困在某个局部构象或能垒一侧。不同 Hamiltonian 的 replica 具有不同的构象采样难度：较“软”的 Hamiltonian 更容易跨越能垒，而较完整的 Hamiltonian 保留目标体系的物理细节。程序定期尝试交换相邻 replica 的构象，并按 Hamiltonian replica exchange 的 Metropolis 接受概率决定是否接受。这样同一个构象可以逐步在不同 Hamiltonian 之间移动，最终回到目标 Hamiltonian，从而提高目标体系的构象采样效率。交换的是构象和相应的状态标签，不是把多个体系拼成一个更大的体系。

HREX demo 的实际步骤如下：

1. 从 `hrex-data/` 读取官方 PLUMED Masterclass alanine dipeptide in water 数据；保留官方 `conf.gro`、`topol.top` 和 `grompp.mdp` 作为输入，不直接修改它们。
2. 用较短的 `nsteps` 和与交换周期一致的输出周期生成 demo 专用 `md.mdp`。`HREX_NSTEPS` 和 `HREX_REPLEX` 可以覆盖默认值 `10000` 和 `100`。
3. 先执行一次 `gmx_mpi grompp` 生成预处理 topology，再标记 Protein 的 22 个溶质原子，分别通过 `plumed partial_tempering` 生成 4 份 replica topology，并为每个 replica 生成自己的 `topol.tpr`。
4. 使用 `-multidir replica0 replica1 replica2 replica3` 启动 4 个相互关联的模拟。每个目录对应一个 replica，MPI rank 数必须与目录数一致；本 demo 由 Slurm 分配双节点、每节点 2 个 task，每个 task 使用 16 个 OpenMP threads 和 1 张 GPU。
5. `-replex 100` 表示每 100 个 MD step 尝试一次 replica exchange；`-hrex` 启用 Hamiltonian replica exchange，`-dlb no` 保证各 replica 的步进和交换保持同步，`-notunepme` 避免 GPU PME 自动调优造成交换初期的数值差异。
6. 所有模拟完成后检查每个 `replica*/md.log`。模拟目录写入 `ROOT/test/hrex-${SLURM_JOB_ID}`，Slurm 日志和临时文件写入共享目录 `ROOT/tmp/`；`hrex-data/` 中的官方输入文件不会被覆盖。

提交服务器上的 GPU demo：

```bash
mkdir -p /lustre/software/pixi/gromacs-plumed-hpc/tmp
sbatch /lustre/software/pixi/gromacs-plumed-hpc/test.sbatch
```

脚本通过 `gromacs/hpc/pixi.toml` 激活集群 Open MPI 和 GROMACS 的 `GMXRC.bash`，因此命令直接使用 `gmx_mpi`，不需要额外的 `GMX_BIN` 变量。

## gpu01 GPU 后端实测记录

以下结果来自 2026-09-15 在 `gpu01` 上的实际运行。`gpu01` 有 2 张 Tesla V100-PCIE-32GB，Compute Capability 为 7.0，NVIDIA driver 为 `550.54.15`，driver 报告的 CUDA 版本为 `12.4`。

### CUDA package

`/lustre/software/pixi/gromacs-plumed-hpc2` 中安装的
合并 package 使用 `gmx_mpi`，并包含 `gmx_mpi_d` 和 `gmx_mpi_ocl`；CUDA binary 包含 `sm_70`、`sm_80`、`sm_89` 和 `sm_90` 的 native device code。用 `cuobjdump` 检查 `libgromacs_mpi.so.8` 时没有发现 PTX fallback。

使用集群 Open MPI 启动一个 MPI world 后，2 个 rank、2 张 V100、GPU PME 的测试成功：

```bash
mpirun -np 2 --map-by ppr:2:node:pe=16 --bind-to core \
    gmx_mpi mdrun -s topol.tpr -nsteps 10 -ntomp 16 \
    -pin off -nb gpu -pme gpu -gpu_id 01 \
    -multidir replica0 replica1
```

输出确认 `2 GPUs selected`、2 个 MPI rank 分别使用两张 GPU，并正常写出最终坐标。这个测试也确认 OpenMPI 的 `mpirun` 可以正常工作，不需要 `rsh`。

### OpenCL executable

OpenCL package 的可执行文件是 `gmx_mpi_ocl`，不是 `gmx_mpi`。测试使用的安装目录为
`/lustre/software/pixi/gromacs-plumed-hpc`。

OCL 测试先遇到一个独立的 ICD loader 配置问题。Pixi 环境中的 `ocl-icd` 默认读取：

```text
/lustre/software/pixi/gromacs-plumed-hpc/.pixi/envs/default/etc/OpenCL/vendors
```

而 NVIDIA ICD 文件位于：

```text
/etc/OpenCL/vendors/nvidia.icd
```

因此需要在 batch 或运行命令前设置：

```bash
export OCL_ICD_VENDORS=/etc/OpenCL/vendors
```

设置后，OpenCL loader 可以发现 2 张 V100，但 GROMACS 2023.5 自身的
`src/gromacs/hardware/device_management_ocl.cpp:110-136` 会把 NVIDIA Volta
标记为 `IncompatibleNvidiaVolta`，正常运行路径会拒绝该设备。

可以用下面的环境变量跳过这项检查：

```bash
export GMX_GPU_DISABLE_COMPATIBILITY_CHECK=1
```

之前的绕过检查测试确实已经进入 GPU 计算阶段，输出确认 2 张 GPU 被映射到 2 个 MPI rank：

```text
PP:0,PME:0,PP:1,PME:1
```

但随后立即出现 LINCS warnings，最后 segmentation fault。也就是说，之前的错误不是 ICD 找不到设备，也不是 `mpirun` 失败；绕过检查后暴露的是 GROMACS 2023.5 OpenCL backend 在 NVIDIA Volta 上的运行时/数值不稳定问题。`GMX_GPU_DISABLE_COMPATIBILITY_CHECK` 只跳过保护性检查，不会修复 backend、driver 或 device code 的兼容性，因此不应作为生产运行方案。

结论：CUDA package 已在 `gpu01` 上用 2 rank、2 GPU 和 GPU PME 验证成功；OpenCL package 只能通过 ICD 配置和兼容性检查绕过进入运行，但目前在 V100 上会在实际 MD 阶段失败。除非升级或修改 GROMACS 的 OpenCL Volta 支持，否则应优先使用 CUDA package 或 CPU package。
