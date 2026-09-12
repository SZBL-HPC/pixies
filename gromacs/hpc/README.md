# HPC Runtime Environment

该目录是集群运行环境的最小 Pixi workspace，只支持 `linux-64`。
它不包含编译器、CMake、CUDA toolkit 或其他构建依赖；安装本地构建的 `gromacs-plumed` package 后，Pixi 只解析其运行时依赖。

OpenMPI 使用 conda-forge `mpi-external` label 中的 external package，实际运行时由集群上的 OpenMPI 5 module 和 `activate_mpi.sh` 提供。
`activate_mpi.sh` 是指向上级 `../activate_mpi.sh` 的符号链接；如果当前机器没有对应的 module 系统，脚本会跳过 module 激活而不阻止环境加载。

## 安装

在包含 `hpc/` 和 `output/` 的项目目录中执行：

```bash
cp -srv hpc/ /path/to/target
cd /path/to/target
pixi add `readlink -f output/linux-64/gromacs-plumed-2023.5-mpi_openmpi_cuda_0.conda`
pixi install
```

上面的 `pixi add` 使用 CUDA 单精度 package；也可以替换为同一目录中的 `mpi_openmpi_d` 或 `mpi_openmpi_ocl` package。
`readlink -f` 需要在执行命令的目录中能够找到 `output/linux-64/`；如果 package 位于其他目录，可以直接把它替换为该 `.conda` 文件的绝对路径。

安装后从目标目录运行 `pixi shell`，或使用 `pixi run` 执行已安装的 GROMACS 命令。
