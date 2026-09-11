# GROMACS

## Pixi 工作流

项目目录：`/Volumes/Develop/git/szbl-hpc/pixies/gromacs`。

当前配置涉及下载、构建、目标平台和按后端区分的可执行文件命名；具体参数以 `pixi.toml` 为准。

## GROMACS 版本参数

构建 task 的第一个参数是 GROMACS 版本，当前支持 `2023.5`、`2024.6`、`2025.5` 和 `2026.3`。
版本参数会同时传递给下载、PLUMED patch、标准构建和 double-precision 构建。
PLUMED 和 GROMACS 的源码/build 目录按 Pixi 环境隔离，GROMACS 安装前缀按版本组织，task `outputs` 按环境、版本和 variant 隔离。

`_d_plumed` 使用 `curl -L -C -` 下载 `plumed-src-2.10.1.tgz` 到 `pkg/`。

`_d_gromacs` 使用 `curl -L -C -` 下载 `gromacs-{{ version }}.tar.gz` 到 `pkg/`。

`down` 依赖 `_d_plumed` 和 `_d_gromacs`。

`_mk_plumed` 将 PLUMED 2.10.1 解压到 `plumed-2.10.1/{{ pixi.environment.name }}/`，执行 `./configure --disable-python --disable-pycv` 和 `make -C src install`，并安装到 `local/plumed/{{ pixi.environment.name }}/`。
解压时会排除 archive 中会触发 Pixi 循环遍历错误的 `src/include/plumed -> ../` 符号链接。

`_p_gromacs` 将 `gromacs-{{ version }}` 解压到 `gromacs-{{ version }}/{{ pixi.environment.name }}/`，并使用当前环境的 `local/plumed/{{ pixi.environment.name }}/bin/plumed-patch` 执行 patch。

`_mk_gromacs` 接收第二个参数 `variant`，可取 `single`、`double` 或 `ocl`。
它分别在 `gromacs-{{ version }}/{{ pixi.environment.name }}/build_single`、`build_double` 或 `build_ocl` 中执行 CMake、并行编译和安装到 `local/gromacs/{{ version }}/`。

`build` 对同一个 `_mk_gromacs` task 分别传入 `single` 和 `double` 两个 `variant`；Linux 的 `mk_gromacs_ocl` 则直接调用 `_mk_gromacs` 的 `ocl` variant。

从项目根目录执行完整构建：

```bash
cd /Volumes/Develop/git/szbl-hpc/pixies/gromacs
pixi run build
```

构建其他版本时直接传入版本参数，例如：

```bash
pixi run build 2024.6
pixi run build 2025.5
pixi run build 2026.3
```

激活环境会把 `local/bin` 加入 `PATH`，并加载 `local/bin/GMXRC.bash`。

## DGROMACS 参数

使用 target-specific activation environment 设置 `DGROMACS_GPU`、`DGROMACS_GPU_Toolchain` 和按平台区分的 `GMX_SUFFIX`，再由公共的 `DGROMACS_Common` 补充 MPI、PLUMED 和 HWLOC 参数；task 根据 `$GMX_SUFFIX` 生成 CMake 的 binary/library suffix 参数，安装前缀由版本参数直接传给 CMake。

当前 target 与可执行文件命名约定如下：

| Pixi target | 计算后端 | 精度 | MPI | 主程序 |
| --- | --- | --- | --- | --- |
| `centos75` | CUDA | single | Open MPI | `gmx_mpi` |
| `gpu-linux-64` | CUDA | single | Open MPI | `gmx_mpi` |
| `osx-arm64` | OpenCL | single | MPICH | `gmx_mpi` |

`gpu-linux-64` 是带 CUDA `12.4` 和 glibc `2.17` 约束的 Linux target；`centos75` 是带 glibc `2.17` 和 Linux `3.10` 约束的 Linux target。
两个 Linux target 都匹配 `target.linux-64.activation.env` 和 `target.linux-64.dependencies`，因此当前都使用 CUDA、Open MPI 和相同的 CUDA 依赖；差异只在 Pixi 的虚拟平台约束。

`_mk_gromacs` 的 task `outputs` 是按环境、版本、`variant` 和 MPI suffix 展开的 `local/gromacs/{{ version }}/bin/gmx{{ GMX_SUFFIX }}`；`double` variant 会在 suffix 后追加 `_d`。
Linux 专用的 `mk_gromacs_ocl` 输出位于 `local/gromacs/{{ version }}/bin/gmx{{ GMX_SUFFIX }}` 和对应环境的 `build_ocl/bin/`。

macOS 的 `mpi5` 环境使用 MPICH 和 `_mpi` suffix；`mpis` 环境使用 Open MPI，并将 standard/double 构建的 suffix 改为 `_ompi`/`_ompi_d`，避免多个 MPI 版本共用文件名。

安装后，用 `switch.sh` 选择 GROMACS 版本和 PLUMED 环境：

```bash
./switch.sh gromacs 2023.5
./switch.sh plumed mpi5
./switch.sh --list
```

脚本会把 `local/bin/GMXRC` 和 `local/bin/GMXRC.bash` 链接到所选版本的 `local/gromacs/<version>/bin/`，并把 `plumed`、`plumed-config`、`plumed-patch` 链接到所选环境的 `local/plumed/<environment>/bin/`。
Pixi activation 继续加载 `local/bin/GMXRC.bash`，手工使用时可以执行 `source local/bin/GMXRC`。

macOS `osx-arm64` 当前使用：

```text
-DGMX_GPU=OpenCL -DGMX_DOUBLE=OFF
-DOpenCL_INCLUDE_DIR=$PIXI_PROJECT_ROOT/.pixi/envs/default/include
-DOpenCL_LIBRARY=$PIXI_PROJECT_ROOT/.pixi/envs/default/lib/libOpenCL.dylib
```

Linux `gpu-linux-64` 和 `centos75` 当前使用：

```text
-DGMX_GPU=CUDA
-DCMAKE_INSTALL_LIBDIR=lib
-DCUDA_NVCC_EXECUTABLE=$PIXI_PROJECT_ROOT/.pixi/envs/default/bin/nvcc
-DCMAKE_CUDA_COMPILER=$PIXI_PROJECT_ROOT/.pixi/envs/default/bin/nvcc
```

Linux 专用的 `mk_gromacs_ocl` 会覆盖 GPU 后端为 OpenCL，并额外使用：

```text
-DGMX_GPU=OpenCL
-DGMX_DEFAULT_SUFFIX=OFF
-DGMX_BINARY_SUFFIX=$GMX_SUFFIX
-DGMX_LIBS_SUFFIX=$GMX_SUFFIX
```

三种 target 都额外继承公共参数：

```text
-DGMX_USE_PLUMED=ON -DGMX_THREAD_MPI=OFF -DGMX_MPI=ON
-DGMX_HWLOC=ON
-DCMAKE_INSTALL_PREFIX=$PIXI_PROJECT_ROOT/local/gromacs/{{ version }}
```

Pixi task 内的 `cmake .. $DGROMACS_Common $DGROMACS_GPU $DGROMACS_GPU_Toolchain` 会显式设置 `GMX_DEFAULT_SUFFIX=OFF`，并由 `$GMX_SUFFIX` 生成 `GMX_BINARY_SUFFIX` 和 `GMX_LIBS_SUFFIX`；double variant 会在该 suffix 后再追加 `_d`。

在 build 目录手工重新配置时，必须让变量在 Pixi shell 中展开：

```bash
cd /Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/mpi5/build_single
pixi run sh -c 'cmake .. $DGROMACS_Common $DGROMACS_GPU $DGROMACS_GPU_Toolchain'
```

不要直接使用 `pixi run cmake .. $DGROMACS_Common $DGROMACS_GPU $DGROMACS_GPU_Toolchain`，因为外层 shell 会先展开这些变量，导致参数为空。

重新配置后可以继续增量构建：

```bash
pixi run cmake --build . --parallel 2
```

切换 GROMACS 版本或大幅切换 CMake 选项时，建议使用新的 build 目录，避免旧 `CMakeCache.txt` 保留旧源码路径、安装前缀或编译选项。

当前 macOS GROMACS 2023.5 的标准 build 关键配置为 `GMX_GPU=OpenCL`、`GMX_DOUBLE=OFF`、`GMX_MPI=ON`、`GMX_HWLOC=ON`、`GMX_OPENMP=ON` 和 `GMX_THREAD_MPI=OFF`，安装前缀为 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/local/gromacs/2023.5`；`mpi5` 生成 `gmx_mpi`，`mpis` 生成 `gmx_ompi`。

## HWLOC 与 double precision

GROMACS 2023.5 的 CMake 公开选项是 `GMX_HWLOC`，不是 `GMX_USE_HWLOC`。
`GMX_USE_HWLOC` 是 CMake 根据 `GMX_HWLOC` 和 `FindHWLOC.cmake` 的检测结果生成的内部变量，不应从 `DGROMACS_Common` 手工传入。

如果传入 `-DGMX_USE_HWLOC=ON`，但没有同时启用 `GMX_HWLOC`，CMake 不会执行 `FindHWLOC.cmake`，也不会设置 `GMX_HWLOC_API_VERSION`。
此时生成的 `src/include/config.h` 会包含空的 `#define GMX_HWLOC_API_VERSION`，随后 `hardwaretopology.cpp` 中的版本判断会变成非法的预处理表达式：

```cpp
#if GMX_HWLOC_API_VERSION < 0x00020000
```

因此应使用：

```text
-DGMX_HWLOC=ON
```

当前 Pixi 环境检测到 `libhwloc` `2.12.2`，fresh 配置后的缓存包含 `GMX_HWLOC_API_VERSION=0x00020c00`，对应生成的 `config.h` 为：

```text
#define GMX_USE_HWLOC 1
#define GMX_HWLOC_API_VERSION 0x00020c00
```

`cmake --fresh` 会清理旧的 `CMakeCache.txt` 和 `CMakeFiles`，因此切换 hwloc 选项时应通过 `_mk_gromacs` 的 `double` variant 重新配置，而不要继续使用包含错误内部变量的旧缓存。

## 可执行文件与库后缀

`GMX_GPU` 决定 GPU 后端，后缀只决定安装文件名，二者是独立的配置。当前统一使用 `GMX_DEFAULT_SUFFIX=OFF`，由 task 显式设置 `GMX_BINARY_SUFFIX` 和 `GMX_LIBS_SUFFIX`；double variant 使用 `${GMX_SUFFIX}_d`，从而保留 MPI/OpenMPI/OpenCL suffix 并追加 double suffix。

因此当前三个 target 的 standard single-precision MPI 构建都使用显式 suffix 生成 `gmx_mpi`、`gmx_ompi` 或 `gmx_mpi_ocl`；它不会因为 `GMX_GPU=CUDA` 自动变成 `gmx_cuda`，也不会因为 `GMX_GPU=OpenCL` 自动变成 `gmx_ocl_mpi`。

`_mk_gromacs` 的 `double` variant 显式设置 `GMX_DOUBLE=ON`，并把 `GMX_BINARY_SUFFIX` 与 `GMX_LIBS_SUFFIX` 设置为 `${GMX_SUFFIX}_d`；仅修改 task output 名称是不够的。
Linux 专用的 `mk_gromacs_ocl` 显式关闭默认 suffix，并使用 target 中的 `GMX_SUFFIX`，生成 `gmx_mpi_ocl`。

当前配置的 suffix 状态如下：

```text
osx-arm64 mpi5: GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_mpi，GMX_LIBS_SUFFIX=_mpi，输出 gmx_mpi
osx-arm64 mpis: GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_ompi，GMX_LIBS_SUFFIX=_ompi，输出 gmx_ompi
gpu-linux-64:   GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_mpi_ocl，GMX_LIBS_SUFFIX=_mpi_ocl，输出 gmx_mpi_ocl
centos75:       GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_mpi_ocl，GMX_LIBS_SUFFIX=_mpi_ocl，输出 gmx_mpi_ocl
double build:   `GMX_BINARY_SUFFIX=${GMX_SUFFIX}_d`，`GMX_LIBS_SUFFIX=${GMX_SUFFIX}_d`
```

对应的库名称分别为 standard build 的 `libgromacs_mpi`、double build 的 `libgromacs_mpi_d` 和 Linux OpenCL build 的 `libgromacs_mpi_ocl`。
由于 suffix 和 CUDA 编译器路径都会写入 `CMakeCache.txt`，切换 target 或精度时应使用新的 build 目录，避免旧缓存保留前一个 target 的配置。

## 官方版本与 CUDA 编译器变量

已核对官方 `gromacs/gromacs` 仓库的 `v2024.6`、`v2025.5` 和 `v2026.3` tag。三个版本不是一次性完成变量替换，而是经历了从 legacy `FindCUDA` 到 CMake first-class CUDA language 的迁移。

GROMACS 2024.6 的顶层 `CMakeLists.txt` 仍设置 `CMP0146` 为 `OLD`，并明确注明 `We still use FindCUDA`。其 `cmake/gmxManageCuda.cmake` 调用 `find_package(CUDA)`，GROMACS 自己的编译器检查和 `gmxManageNvccConfig.cmake` 主要使用 `CUDA_NVCC_EXECUTABLE`，之后才调用 `enable_language(CUDA)`。

因此对 GROMACS 2023.5 和 2024.6，`CMAKE_CUDA_COMPILER` 不能单独替代 `CUDA_NVCC_EXECUTABLE`。前者控制 CMake 的 CUDA language，后者仍控制 GROMACS 的 legacy CUDA 检查。

GROMACS 2025.5 已改用 `find_package(CUDAToolkit)` 和 `CUDAToolkit_NVCC_EXECUTABLE`，然后调用 `enable_language(CUDA)`。但该版本的 `gmxManageCuda.cmake` 没有显式把 `CUDAToolkit_NVCC_EXECUTABLE` 赋给 `CMAKE_CUDA_COMPILER`，而 `gmxManageNvccConfig.cmake` 的初始兼容性检查仍残留 `CUDA_NVCC_EXECUTABLE` 和 `CUDA_HOST_COMPILER` 引用，因此属于过渡版本。

GROMACS 2026.3 在 `enable_language(CUDA)` 之前明确执行以下逻辑：

```cmake
if (NOT CMAKE_CUDA_COMPILER)
    set(CMAKE_CUDA_COMPILER "${CUDAToolkit_NVCC_EXECUTABLE}")
endif()
```

之后的编译器信息、CUDA 架构和 flag 检查都使用 `CMAKE_CUDA_COMPILER`、`CMAKE_CUDA_COMPILER_VERSION`、`CMAKE_CUDA_ARCHITECTURES` 以及 CMake 的 `check_compiler_flag(CUDA ...)`。这才是新变量成为标准入口的版本。

官方源码链接：

- `https://github.com/gromacs/gromacs/blob/v2024.6/CMakeLists.txt`
- `https://github.com/gromacs/gromacs/blob/v2024.6/cmake/gmxManageCuda.cmake`
- `https://github.com/gromacs/gromacs/blob/v2025.5/cmake/gmxManageCuda.cmake`
- `https://github.com/gromacs/gromacs/blob/v2025.5/cmake/gmxManageNvccConfig.cmake`
- `https://github.com/gromacs/gromacs/blob/v2026.3/cmake/gmxManageCuda.cmake`
- `https://github.com/gromacs/gromacs/blob/v2026.3/cmake/gmxManageNvccConfig.cmake`

当前 Linux Pixi 配置同时设置以下两个变量，以兼容当前的 GROMACS 2023.5 legacy 流程和后续 GROMACS 版本的 CMake CUDA language 流程：

```text
-DCUDA_NVCC_EXECUTABLE=$PIXI_PROJECT_ROOT/.pixi/envs/default/bin/nvcc
-DCMAKE_CUDA_COMPILER=$PIXI_PROJECT_ROOT/.pixi/envs/default/bin/nvcc
```

两个变量都必须指向 Pixi 环境中的真实 wrapper `.../.pixi/envs/default/bin/nvcc`，不要指向 `.../targets/x86_64-linux/bin/nvcc`。后者可能无法正确定位 `nvcc.profile`，从而丢失 `targets/x86_64-linux/include`，最终出现 `cuda_runtime.h: No such file or directory`。

`CMAKE_CUDA_COMPILER` 需要在 build tree 第一次 CMake 配置时设置。切换该变量或切换 GROMACS 版本时，应使用新的 build 目录，避免旧 `CMakeCache.txt` 继续保存旧的 CUDA 编译器路径。

## CMake 与并行

GROMACS 2023.5 的最低 CMake 版本是 `3.18.4`，Pixi 约束为 `cmake >=3.18.4,<4`，当前 lock 解析到 CMake `3.31.8`。

GROMACS 2023.5 默认开启 OpenMP；`GMX_THREAD_MPI=OFF` 只关闭内置 thread-MPI，`GMX_MPI=ON` 使用外部 MPI，并不关闭 OpenMP。

典型的 MPI 与 OpenMP 配置如下：

```bash
OMP_NUM_THREADS=8 mpirun -np 4 gmx_mpi mdrun -ntomp 8
```

默认 `mpi5` target 使用 `gmx_mpi`，macOS 的 `mpis` 使用 `gmx_ompi`。这里的 `-np 4` 是 MPI rank 数量，`-ntomp 8` 是每个 rank 的 OpenMP 线程数，总 CPU 线程数为 32。

同时设置 `OMP_NUM_THREADS` 和 `-ntomp` 时，两者必须一致，否则 GROMACS 会报错。

## 构建输出诊断

在 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/mpi5/build_single` 执行 `pixi run make -j2` 后，构建已到 `[100%]`，`libgromacs`、`gmxapi`、`gmx` 和 `nblib` 均已成功生成。

并行构建时输出会交错，容易把 warning 看成 error；排查时可以使用串行构建：

```bash
pixi run cmake --build . --parallel 1 2>&1 | tee make.log
```

构建中出现的以下信息是 warning 或探测信息，不是编译失败：

- `c++: warning: no such include directory ... [-Wmissing-include-dirs]`
- `_real` 和 `sprintf` deprecated warning
- `duplicate -rpath ... ignored`
- OpenCL deprecated warning
- Doxygen 未找到
- GoogleTest 和 `FetchContent_Populate` 的 CMake deprecation warning
- `CMakeConfigureLog.yaml` 中的 `This is not x86`、`io.h not found` 和 `sched_getaffinity` 探测失败记录

判断真正的构建失败，应查找 `error:`、`fatal error`、`undefined reference` 或 `FAILED`，并以 `make` 的最终退出码为准。

## PLUMED Patch 版本

`plumed-patch` 使用上下文 diff，并不会对 GROMACS 版本做严格的完整版本校验。

邻近版本有时可以应用 patch，但不能因为都属于 `2025.x` 就认为行为和接口一定兼容；官方支持和可复现构建应使用 patch 文件名对应的精确 GROMACS release。

PLUMED 2.10 官方的 GROMACS 2025.0 patch 页面是：
`https://www.plumed.org/doc-v2.10/user-doc/html/gromacs-2025-0.html`。

用 `gromacs-2025.0` patch 处理 GROMACS 2025.5 时，`local/plumed/mpi5/lib/plumed/patches/gromacs-2025.0.diff/src/gromacs/CMakeLists.txt` 的 hunk 没有打上并不必然是问题。

干净源码测试显示，GROMACS 2025.5 上游已经包含该 CMake hunk 的结构，因此 patch 会报告 `Ignoring previously applied (or reversed) patch`，而其他 PLUMED 相关 hunk 可以应用。

但 patch 过程出现 `.rej` 仍必须检查，因为 `local/plumed/mpi5/lib/plumed/scripts/patch.sh` 没有用 `set -e`，部分 patch reject 不一定会让 task 失败。

当前配置改用 GROMACS 2023.5，并使用同版本的 `plumed-patch -e gromacs-2023.5 -p`，这是更稳妥的组合。

## MdrunOutputTests

运行指定测试：

```bash
cd /Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/mpi5/build_single
pixi run ctest --output-on-failure -R '^MdrunOutputTests$'
```

测试结果为 12 个子测试中 11 个通过，唯一失败是 `MdrunTest.WritesHelp`。

`GTest IntegrationTest QuickGpuTest` 是 CTest labels，不是 3 个独立失败测试。

测试实现位于 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/src/programs/mdrun/tests/helpwriting.cpp:59-83`，它把 `gmx mdrun -h` 的输出与 reference data 比较。

PLUMED patch 在 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/src/gromacs/mdrun/legacymdrunoptions.h:134` 增加了 `-plumed`，在 `:353-354` 增加了 `-hrex`。

原始 reference data `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/src/programs/mdrun/tests/refdata/MdrunTest_WritesHelp.xml` 没有这两个选项，所以 `/Help string` 比较失败。

这是 PLUMED patch 改变命令行帮助后 upstream golden reference 没有同步，不是 GROMACS 编译或 PLUMED 功能初始化失败。

只在当前解压源码中更新 reference data，可以执行：

```bash
pixi run ./bin/mdrun-output-test \
  --gtest_filter=MdrunTest.WritesHelp \
  --ref-data update
```

该 XML 位于解压出来的 GROMACS 源码目录中，下一次重新执行 `_p_gromacs` 后会被重新解压覆盖。

如果需要可重复地让该测试通过，应把更新后的 reference data 纳入 PLUMED patch overlay，或者对 PLUMED patched source 跳过该测试，而不是直接忽略 `.rej`。

## MPI Runtime

构建生成的 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/local/gromacs/2023.5/bin/gmx_mpi` 会报告：

```text
GROMACS version: 2023.5-plumed_2.10.1
MPI library: MPI
OpenMP support: enabled
GPU support: OpenCL
```

macOS 上直接运行 `./bin/gmx_mpi --version` 时，MPICH/libfabric 可能在 `MPI_Finalize` 阶段报告 `MPIDI_OFI ... OFI Input/output`。

这属于运行时 MPI provider 问题，不是 make 失败；当前 `pixi.toml` 的 `osx-arm64` 环境设置了 `FI_PROVIDER=tcp`，可以避免该 finalize 问题。

## Linux 约束

自定义 `gpu-linux-64` target 声明 `cuda = "12.4"` 和 `glibc = "2.17"`；自定义 `centos75` target 声明 `glibc = "2.17"` 和 `linux = "3.10"`。

当前 lock 中该 target 使用 `__glibc=2.17`，实际 CUDA toolkit 解析为 12.6.3。

只降低 CUDA 版本而不约束 Pixi 的 glibc virtual package，不能保证解析到 glibc 2.17；CUDA 包本身也可能声明更高的 glibc 下限。
