# GROMACS

## Pixi 工作流

项目目录：`/Volumes/Develop/git/szbl-hpc/pixies/gromacs`。

当前配置提交为 `53e816e Update GROMACS Pixi configuration`，涉及下载、构建和目标平台参数。

`_d_plumed` 使用 `curl -L -C -` 下载 `plumed-src-2.10.1.tgz` 到 `pkg/`。

`_d_gromacs` 使用 `curl -L -C -` 下载 `gromacs-2023.5.tar.gz` 到 `pkg/`。

`down` 依赖 `_d_plumed` 和 `_d_gromacs`。

`_mk_plumed` 解压 PLUMED 2.10.1，执行 `./configure --prefix="$(pwd)/../local" && make install`，并生成 `local/bin/plumed` 和 `local/bin/plumed-patch`。

`_p_gromacs` 解压 GROMACS 2023.5，并执行 `plumed-patch -e gromacs-2023.5 -p`。

`_mk_gromacs` 在 `gromacs-2023.5/build` 中执行 CMake、并行编译和安装。

`build` 依赖 `_mk_plumed` 和 `_mk_gromacs`。

从项目根目录执行完整构建：

```bash
cd /Volumes/Develop/git/szbl-hpc/pixies/gromacs
pixi run build
```

激活环境会把 `local/bin` 加入 `PATH`，并加载 `local/bin/GMXRC.bash`。

## DGROMACS 参数

使用 target-specific activation environment 设置 `DGROMACS`，可以用同一个 Pixi task 切换不同平台的 CMake 参数。

macOS `osx-arm64` 当前使用：

```text
-DGMX_GPU=OpenCL -DGMX_THREAD_MPI=OFF -DGMX_MPI=ON -DCMAKE_INSTALL_PREFIX=$PIXI_PROJECT_ROOT/local
```

Linux 当前使用：

```text
-DGMX_GPU=CUDA -DGMX_THREAD_MPI=OFF -DGMX_MPI=ON -DCMAKE_INSTALL_PREFIX=$PIXI_PROJECT_ROOT/local
```

Pixi task 内的 `cmake .. $DGROMACS` 可以正常展开为多个 `-D` 参数。

在 build 目录手工重新配置时，必须让变量在 Pixi shell 中展开：

```bash
cd /Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/build
pixi run sh -c 'cmake .. $DGROMACS'
```

不要直接使用 `pixi run cmake .. $DGROMACS`，因为外层 shell 会先展开 `$DGROMACS`，导致参数为空。

重新配置后可以继续增量构建：

```bash
pixi run cmake --build . --parallel 2
```

切换 GROMACS 版本或大幅切换 CMake 选项时，建议使用新的 build 目录，避免旧 `CMakeCache.txt` 保留旧源码路径、安装前缀或编译选项。

当前 GROMACS 2023.5 build 的关键配置为 `GMX_GPU=OpenCL`、`GMX_MPI=ON`、`GMX_OPENMP=ON` 和 `GMX_THREAD_MPI=OFF`，安装前缀为 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/local`。

## CMake 与并行

GROMACS 2023.5 的最低 CMake 版本是 `3.18.4`，Pixi 约束为 `cmake >=3.18.4,<4`，当前 lock 解析到 CMake `3.31.8`。

GROMACS 2023.5 默认开启 OpenMP；`GMX_THREAD_MPI=OFF` 只关闭内置 thread-MPI，`GMX_MPI=ON` 使用外部 MPI，并不关闭 OpenMP。

典型的 MPI 与 OpenMP 配置如下：

```bash
OMP_NUM_THREADS=8 mpirun -np 4 gmx_mpi mdrun -ntomp 8
```

这里的 `-np 4` 是 MPI rank 数量，`-ntomp 8` 是每个 rank 的 OpenMP 线程数，总 CPU 线程数为 32。

同时设置 `OMP_NUM_THREADS` 和 `-ntomp` 时，两者必须一致，否则 GROMACS 会报错。

## 构建输出诊断

在 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/build` 执行 `pixi run make -j2` 后，构建已到 `[100%]`，`libgromacs`、`gmxapi`、`gmx` 和 `nblib` 均已成功生成。

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

用 `gromacs-2025.0` patch 处理 GROMACS 2025.5 时，`local/lib/plumed/patches/gromacs-2025.0.diff/src/gromacs/CMakeLists.txt` 的 hunk 没有打上并不必然是问题。

干净源码测试显示，GROMACS 2025.5 上游已经包含该 CMake hunk 的结构，因此 patch 会报告 `Ignoring previously applied (or reversed) patch`，而其他 PLUMED 相关 hunk 可以应用。

但 patch 过程出现 `.rej` 仍必须检查，因为 `local/lib/plumed/scripts/patch.sh` 没有用 `set -e`，部分 patch reject 不一定会让 task 失败。

当前配置改用 GROMACS 2023.5，并使用同版本的 `plumed-patch -e gromacs-2023.5 -p`，这是更稳妥的组合。

## MdrunOutputTests

运行指定测试：

```bash
cd /Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/build
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

构建生成的 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/build/bin/gmx_mpi` 会报告：

```text
GROMACS version: 2023.5-plumed_2.10.1
MPI library: MPI
OpenMP support: enabled
GPU support: OpenCL
```

macOS 上直接运行 `./bin/gmx_mpi --version` 时，MPICH/libfabric 可能在 `MPI_Finalize` 阶段报告 `MPIDI_OFI ... OFI Input/output`。

这属于运行时 MPI provider 问题，不是 make 失败；当前 `pixi.toml` 的 `osx-arm64` 环境设置了 `FI_PROVIDER=tcp`，可以避免该 finalize 问题。

## Linux 约束

自定义 `gpu-linux-64` target 声明 `cuda = "12.4"` 和 `glibc = "2.17"`。

当前 lock 中该 target 使用 `__glibc=2.17`，实际 CUDA toolkit 解析为 12.6.3。

只降低 CUDA 版本而不约束 Pixi 的 glibc virtual package，不能保证解析到 glibc 2.17；CUDA 包本身也可能声明更高的 glibc 下限。
