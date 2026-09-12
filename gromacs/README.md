# GROMACS

## Pixi 工作流

项目目录：`/Volumes/Develop/git/szbl-hpc/pixies/gromacs`。

当前配置涉及下载、构建、目标平台和按后端区分的可执行文件命名；具体参数以 `pixi.toml` 为准。

## GROMACS 版本参数

构建 task 的第一个参数是 GROMACS 版本，当前支持 `2023.5`、`2024.6`、`2025.5` 和 `2026.3`。
版本参数会同时传递给下载、PLUMED patch、标准构建和 double-precision 构建。
PLUMED 和 GROMACS 的源码/build 目录按 Pixi 环境隔离，GROMACS 安装前缀按版本组织，task `outputs` 按环境、版本和 variant 隔离。
PLUMED 的安装目录也按环境隔离；GROMACS 的安装目录目前按版本共享，这是为了让 `switch.sh` 能自动发现版本，并不等于不同 MPI 环境的安装文件完全独立。

`_d_plumed` 使用 `curl -L -C -` 下载 `plumed-src-2.10.1.tgz` 到 `pkg/`。

`_d_gromacs` 使用 `curl -L -C -` 下载 `gromacs-{{ version }}.tar.gz` 到 `pkg/`。

`down` 依赖 `_d_plumed` 和 `_d_gromacs`。

`_mk_plumed` 将 PLUMED 2.10.1 解压到 `plumed-2.10.1/{{ pixi.environment.name }}/`，执行 `./configure --disable-python --disable-pycv` 和 `make -C src install`，并安装到 `local/plumed/{{ pixi.environment.name }}/`。
解压时会排除 archive 中会触发 Pixi 循环遍历错误的 `src/include/plumed -> ../` 符号链接。

`plumed-benchmark` 依赖当前 Pixi 环境的 `_mk_plumed`，在 `.pixi/plumed-benchmark/{{ pixi.environment.name }}/` 生成最小的 `plumed.dat`，然后运行 100 步、10 个原子的 PLUMED benchmark；输出文件也留在该临时目录，不会污染项目根目录。

`_p_gromacs` 将 `gromacs-{{ version }}` 解压到 `gromacs-{{ version }}/{{ pixi.environment.name }}/`，并使用当前环境的 `local/plumed/{{ pixi.environment.name }}/bin/plumed-patch` 执行 patch。

`_mk_gromacs` 接收 `version`、`variant` 和 `suffix` 参数；`variant` 可取 `single`、`double` 或 `ocl`。
它分别在 `gromacs-{{ version }}/{{ pixi.environment.name }}/build_single`、`build_double` 或 `build_ocl` 中执行 CMake、并行编译和安装到 `local/gromacs/{{ version }}/`。

`_batch_mk_gromacs` 接收一次 `version` 和 `suffix`，在通用配置中依赖两个 `_mk_gromacs`，分别构建 `single` 和 `double`；`double` 的 `_d` 在 batch task 中追加。Linux target 覆盖该 batch，再增加一个 `ocl` 依赖，并使用 `{{ suffix }}_ocl`。
`build` 只计算一次当前环境的 suffix 并依赖 `_batch_mk_gromacs`；因此 Linux 的 `build` 会自动构建 `single`、`double` 和 `ocl`，不再需要独立的 `mk_gromacs_ocl` task。

## 目录隔离与安装覆盖

PLUMED 的目录按环境完全隔离。以 `mpi5` 为例，源码/build 位于 `plumed-2.10.1/mpi5/`，安装前缀位于 `local/plumed/mpi5/`；`mpis` 和 `default` 使用各自的目录。不同 MPI 环境不会共用 PLUMED 的 configure、对象文件、生成文件或安装库。

GROMACS 的源码和 build 目录也按环境隔离。对于版本 `2023.5`，实际目录是：

```text
gromacs-2023.5/default/
gromacs-2023.5/mpi5/
gromacs-2023.5/mpis/
```

每个目录下还有独立的 `build_single`、`build_double` 和 Linux 专用的 `build_ocl`。PLUMED patch 产生的 `runner.cpp.preplumed` 也位于对应环境的源码目录中，因此不同环境不会重复 patch 同一份源码。

GROMACS 的安装前缀目前是共享的：

```text
local/gromacs/2023.5/
```

GROMACS suffix 由 `build` task 计算并作为 `suffix` 参数传给 `_batch_mk_gromacs`，系统平台与 environment 保持正交。
当前命名为：

```text
default: gmx、libgromacs、无 suffix（所有系统）
mpi5:    gmx_mpi、libgromacs_mpi（所有系统）
mpis:    Linux 为 gmx_mpi、libgromacs_mpi；macOS 为 gmx_ompi、libgromacs_ompi
```

Linux 的 `_batch_mk_gromacs` 会额外构建 OCL GPU variant，使用 `${suffix}_ocl` 后缀，
不改变 standard build 的 environment suffix。

当前只有 `mpi5` 的 standard 构建保留 GROMACS API。`_mk_gromacs` 的 Jinja 条件会对 `default`、`mpis`、`double` 和 `ocl` 传入 `-DGMXAPI=OFF`；因此只有 `mpi5` standard 对应的主库生成 `libgmxapi`、`gmxapi-config.cmake` 和 `resourceassignment.h`。standard 主库使用 `libgromacs_mpi`，Linux OpenCL variant 则使用 `libgromacs_mpi_ocl`。

`-DGMXAPI=OFF` 会关闭整个 gmxapi，而不只是跳过两个文件；它同时不安装 gmxapi headers、CMake export 和 `libgmxapi`。该 API 若有使用需求，只能从 `mpi5` standard prefix 中使用。

关闭这些构建的原因是它们原本会生成内容不同、但安装路径相同的 gmxapi 文件。`resourceassignment.h` 中的 `GMX_LIB_MPI` 在 default 中为 `0`，在 MPI 构建中为 `1`；`gmxapi-config.cmake` 在 default 中设置 `MPI "none"`，在 MPI 构建中设置 `MPI "library"`。此外，`gmxapi.cmake` 和 CMake export target 会引用实际的库后缀：mpi5 standard 引用 `gromacs_mpi`，mpis 引用 `gromacs_ompi`，mpi5 double 和 OCL 构建还会引用各自的 `_mpi_d` 或 OCL suffix。

这些文件分别安装为共享 prefix 下的 `include/gmxapi/mpi/resourceassignment.h`、`share/cmake/gmxapi/gmxapi-config.cmake` 和 `share/cmake/gmxapi/gmxapi.cmake`，没有按 MPI 或 variant 添加目录后缀。后一次安装会覆盖前一次的配置，导致 gmxapi package metadata 指向错误的 MPI 库。因此现在关闭 default、mpis、double 和 ocl 的 GMXAPI，只让 mpi5 standard 生成与其实际主库 suffix 一致的一组 API 文件。

不过安装清单中仍有共享路径，例如 `bin/GMXRC`、`bin/GMXRC.bash`、`bin/gmx-completion.bash`、`share/gromacs/`、公共 headers、man pages 以及部分无 suffix 的第三方库。这些文件可能被同一版本的后一次 `make install` 重写。因此当前设计可以避免核心 GROMACS 可执行文件和主库因 suffix 发生覆盖，但不能声称安装目录完全独立。

同一版本的不同环境或 `single`/`double` variant 不应并行执行安装步骤。若需要物理上完全隔离的安装产物，应把 prefix 改为 `local/gromacs/{{ version }}/{{ pixi.environment.name }}/`，并相应修改 `switch.sh` 的版本扫描逻辑；当前配置为了保留按版本自动发现功能，选择了共享的版本 prefix。

当前 `default`、`mpis`、`double` 和 `ocl` 构建都设置 `GMXAPI=OFF`，只有 `mpi5` standard 构建保留 GMXAPI。因此表格中的 gmxapi 文件差异是关闭 GMXAPI 之前各配置本来会生成的内容，用于说明为什么共享安装 prefix 会发生冲突；现在这些构建不再生成对应文件，潜在覆盖不会发生。

在以下表格中，“文件内容相同”是指使用同一个 GROMACS 版本、相同 GPU/精度/PLUMED 等非 MPI 选项，仅切换 MPI 环境时的情况。关闭 GMXAPI 前，使用当前 CMake 3.31.8 临时 configure 验证：`mpi5` 和 `mpis` 的 `resourceassignment.h` 内容完全相同，均为 `GMX_LIB_MPI=1`；两者的 `gmxapi-config.cmake` 内容也完全相同，均设置 `MPI "library"`。`default` 分别为 `GMX_LIB_MPI=0` 和 `MPI "none"`，因此与两个 MPI 环境不同。

| Pixi environment | MPI 状态 | 文件内容相同 | 文件名不同 | 文件名相同但文件内容不同 |
| --- | --- | --- | --- | --- |
| `default` | `GMX_MPI=OFF`、`GMX_THREAD_MPI=OFF`、无 MPI，suffix 为空 | `GMXRC*`、`demux.pl`、`xplor2gmx.pl`、`share/gromacs/` 数据、通用 `gmx-completion.bash`、大部分静态 public headers | `gmx`、`libgromacs`、`gmx-completion-gmx.bash`、无 suffix 的 CMake/pkg-config 目标 | `gmxapi-config.cmake` 设置 `MPI "none"`；`gmxapi.cmake` 和生成的 `gmxapi/mpi/resourceassignment.h` 使用无 MPI 配置 |
| `mpi5` | `GMX_MPI=ON`、`GMX_THREAD_MPI=OFF`，suffix 为 `_mpi` | 同上；`resourceassignment.h` 和 `gmxapi-config.cmake` 与 `mpis` 相同 | `gmx_mpi`、`libgromacs_mpi`、`gmx-completion-gmx_mpi.bash`、`share/cmake/gromacs_mpi/` 和对应 pkg-config 文件 | `gmxapi-config.cmake` 设置 `MPI "library"`；`gmxapi.cmake` 和相关导出目标引用 `gromacs_mpi`，`resourceassignment.h` 使用 `GMX_LIB_MPI=1` |
| `mpis` | `GMX_MPI=ON`、`GMX_THREAD_MPI=OFF`，Linux suffix 为 `_mpi`，macOS 使用 Open MPI 并特殊改为 `_ompi` | 同上；`resourceassignment.h` 和 `gmxapi-config.cmake` 与 `mpi5` 相同 | Linux 为 `gmx_mpi`、`libgromacs_mpi`；macOS 为 `gmx_ompi`、`libgromacs_ompi`，completion/CMake/pkg-config 路径同步使用对应 suffix | `gmxapi-config.cmake` 设置 `MPI "library"`；`gmxapi.cmake` 和相关导出目标引用实际 suffix，`resourceassignment.h` 使用 `GMX_LIB_MPI=1` |
| `double` variant | 继承所在环境的 MPI 状态，suffix 在环境 suffix 后追加 `_d` | `GMXRC*`、拓扑数据、通用 completion 和公共 headers 与对应 standard 构建相同 | `mpi5` 生成 `gmx_mpi_d`、`libgromacs_mpi_d`；`mpis` 生成 `gmx_ompi_d`、`libgromacs_ompi_d`；CMake/pkg-config 目录也使用相应 suffix | 关闭 GMXAPI 前会生成与所在环境 MPI 状态一致的 `gmxapi-config.cmake` 和 `resourceassignment.h`，而 `gmxapi.cmake` 会引用 `_mpi_d` 或 `_ompi_d`；当前 double variant 已关闭 GMXAPI |

因此在关闭 GMXAPI 之前，`default`、`mpi5` 和 `mpis` 的 gmxapi 文件会因内容或 export target 不同而互相覆盖；现在只有 `mpi5` standard 生成这组文件，已经避免了这部分冲突。`GMXRC*`、拓扑数据和通用 completion 仍可能被重写，但通常只是相同内容的覆盖。

CUDA 和 OpenCL 不会改变 `resourceassignment.h` 的 MPI 配置内容；但当前 `ocl` variant 已关闭 gmxapi，因此不会生成这两个文件。GPU 差异仍会体现在 `config.h`、核心库和链接依赖中，不能据此认为 CUDA 和 OpenCL 的整个安装 prefix 可以安全共用。

## Pixi 激活与 GMXRC

`pixi.toml` 的 `[activation].env` 和 GROMACS 生成的 `GMXRC.bash` 负责不同层次的环境设置。

`[activation].env` 在 `/Volumes/Develop/git/szbl-hpc/pixies/gromacs/pixi.toml` 设置项目级参数：把 `local/bin` 加入 `PATH`，设置包含 `-DGMX_DEFAULT_SUFFIX=OFF` 的公共 `DGROMACS_Common` 和编译器 warning flags。`-DGMX_MPI=OFF/ON`、`-DGMXAPI=OFF` 和 GROMACS suffix 都不再放在 activation environment 中，而是在 `_mk_gromacs` task 中按 environment/variant 计算。Linux 的 standard suffix 为 `mpi5`/`mpis` 的 `_mpi`，macOS 的 `mpis` 在 task 中特殊使用 `_ompi`。

`local/bin/GMXRC.bash` 是 `switch.sh` 链接到当前版本安装目录的 GROMACS 脚本。以 GROMACS 2023.5 为例，它在 `local/gromacs/2023.5/bin/GMXRC.bash:53-72` 设置并导出 `GMXBIN`、`GMXLDLIB`、`GMXMAN`、`GMXDATA`、`GMXTOOLCHAINDIR`、`GROMACS_DIR`、`PATH`、`DYLD_LIBRARY_PATH`、`PKG_CONFIG_PATH` 和 `MANPATH`。

该脚本还会移除旧 GROMACS 版本的路径，避免切换版本后路径重复，并在支持的 shell 中加载 GROMACS completion。因此 `scripts = ["local/bin/GMXRC.bash"]` 不是对 `[activation].env` 的重复，可以继续保留。

如果删除 `activation.scripts`，Pixi 只会把 `local/bin` 加入 `PATH`，不会自动把 `local/gromacs/<version>/bin` 加入 `PATH`，也不会设置 GROMACS 的运行时库、数据目录、pkg-config 路径和 completion。只有明确要求用户手动 `source local/bin/GMXRC` 时，才可以删除该 activation script。

## PLUMED 配置与依赖

PLUMED 2.10.1 release archive 中包含 `src/include/plumed -> ../` 循环符号链接。Pixi 的 task walker 会跟随该链接，并且不使用 `.gitignore` 过滤，因此 `.gitignore` 和 `pixi run --no-symbolic-links` 都不能解决这个问题。`_mk_plumed` 解包时使用 `tar --exclude='plumed-2.10.1/src/include/plumed'`；删除或不解包该链接不会影响 `configure` 或 `make -C src install`。

PLUMED 的构建只使用 `make -C src install`，并通过 `--disable-python --disable-pycv` 禁止 Python/PyCV；不会进入顶层的 Python 和 Vim 构建目录。无条件的 `make clean` 也没有必要，因为 task cache miss 时会重新解包独立的环境目录，cache hit 时不会执行构建。

PLUMED 2.10.1 对 zlib、GSL 和 FFTW 使用头文件及直接链接检查，不依赖 `pkg-config`。当前配置保留：

```text
CPPFLAGS=-I$CONDA_PREFIX/include
LDFLAGS=-L$CONDA_PREFIX/lib -Wl,-rpath,$CONDA_PREFIX/lib
```

`--enable-zlib`、`--enable-gsl` 和 `--enable-fftw` 默认就是开启，显式写出用于记录构建意图。`zlib` 是需要直接声明的开发依赖；GSL 会带入 BLAS provider，当前环境由 OpenBLAS 同时提供 BLAS/LAPACK，因此不需要额外声明 `blas` 或独立的 `lapack` 包。

`--enable-rpath` 保留用于支持该选项的平台；它会尝试把安装目录和 `LIBRARY_PATH` 加入 shared library 的搜索路径。当前 macOS configure 找不到 `readelf`，该自动逻辑不会生效，所以 `LDFLAGS` 中针对 `$CONDA_PREFIX/lib` 的显式 `-Wl,-rpath` 仍必须保留。`LIBRARY_PATH` 不需要再设置为安装 prefix，`-Wl,-rpath-link` 也不加入跨平台公共配置，因为 Apple linker 不支持 GNU linker 的该选项。

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

验证当前环境的 PLUMED 是否已正确构建和链接：

```bash
pixi run -e mpi5 plumed-benchmark
```

不要直接运行不带参数的 `plumed benchmark`，因为 PLUMED 默认读取当前目录的 `plumed.dat`；项目根目录没有这个输入文件时会以 `file plumed.dat cannot found` 失败。需要使用自定义输入时，显式传入 `--plumed <path>`。

激活环境会把 `local/bin` 加入 `PATH`，并加载 `local/bin/GMXRC.bash`。

## DGROMACS 参数

使用 target-specific activation environment 设置 `DGROMACS_GPU`、`DGROMACS_GPU_Toolchain`，再由公共的 `DGROMACS_Common` 补充默认 suffix、PLUMED 和 HWLOC 参数；`_mk_gromacs` 的 Jinja 条件决定 `-DGMX_MPI=OFF/ON`、是否加入 `-DGMXAPI=OFF`，environment 决定 standard build 的 suffix，task 根据 `suffix` 参数生成 binary/library suffix，安装前缀由版本参数直接传给 CMake。

当前 target 与可执行文件命名约定如下：

| Pixi target | 计算后端 | 精度 | MPI | 主程序 |
| --- | --- | --- | --- | --- |
| `centos75` | CUDA | single | Open MPI | `gmx_mpi` |
| `gpu-linux-64` | CUDA | single | Open MPI | `gmx_mpi` |
| `osx-arm64` | OpenCL | single | MPICH | `gmx_mpi` |

`gpu-linux-64` 是带 CUDA `12.4` 和 glibc `2.17` 约束的 Linux target；`centos75` 是带 glibc `2.17` 和 Linux `3.10` 约束的 Linux target。
两个 Linux target 都匹配 `target.linux-64.activation.env` 和 `target.linux-64.dependencies`，因此当前都使用 CUDA、Open MPI 和相同的 CUDA 依赖；差异只在 Pixi 的虚拟平台约束。

`_mk_gromacs` 的 task `outputs` 使用 task 参数 `suffix` 展开为 `local/gromacs/{{ version }}/bin/gmx{{ suffix }}`；outputs 不依赖 activation environment。
`double` 的 suffix 已在 `_batch_mk_gromacs` 中变为 `{{ suffix }}_d`；Linux target 的 batch 依赖还会为 OCL variant 传入 `{{ suffix }}_ocl`。

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

Linux target 的 `_batch_mk_gromacs` 第三个依赖会让 `_mk_gromacs` 覆盖 GPU 后端为 OpenCL，并额外使用：

```text
-DGMX_GPU=OpenCL
-DGMX_BINARY_SUFFIX=${suffix}_ocl
-DGMX_LIBS_SUFFIX=${suffix}_ocl
```

三种 target 都额外继承公共参数：

```text
-DGMX_USE_PLUMED=ON -DGMX_THREAD_MPI=OFF
-DGMX_HWLOC=ON
-DCMAKE_INSTALL_PREFIX=$PIXI_PROJECT_ROOT/local/gromacs/{{ version }}
```

Pixi task 内的 `cmake .. $DGROMACS_Common $DGROMACS_GPU $DGROMACS_GPU_Toolchain` 会通过公共参数显式设置 `GMX_DEFAULT_SUFFIX=OFF`，并由 `_mk_gromacs` 的 Jinja 条件生成 `GMX_MPI=OFF/ON`、按需加入 `-DGMXAPI=OFF`，再由 `suffix` 参数生成 `GMX_BINARY_SUFFIX` 和 `GMX_LIBS_SUFFIX`；double 的 `_d` 已由 `_batch_mk_gromacs` 追加。

在 build 目录手工重新配置时，必须让变量在 Pixi shell 中展开：

```bash
cd /Volumes/Develop/git/szbl-hpc/pixies/gromacs/gromacs-2023.5/mpi5/build_single
pixi run sh -c 'cmake .. $DGROMACS_Common -DGMX_MPI=ON $DGROMACS_GPU $DGROMACS_GPU_Toolchain'
```

不要直接使用 `pixi run cmake .. $DGROMACS_Common $DGROMACS_GPU $DGROMACS_GPU_Toolchain`，因为外层 shell 会先展开这些变量，导致参数为空；手工配置时需要显式选择 `-DGMX_MPI=ON` 或 `-DGMX_MPI=OFF`。

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

`GMX_GPU` 决定 GPU 后端，后缀只决定安装文件名，二者是独立的配置。当前统一使用 `GMX_DEFAULT_SUFFIX=OFF`，由 task 的 `suffix` 参数显式设置 `GMX_BINARY_SUFFIX` 和 `GMX_LIBS_SUFFIX`；`_batch_mk_gromacs` 为 double 传入 `${suffix}_d`，从而保留 MPI/OpenMPI/OpenCL suffix 并追加 double suffix。

因此 standard single-precision MPI 构建按 environment 生成 `gmx_mpi`，只有 macOS 的 `mpis` 特殊生成 `gmx_ompi`；Linux 的独立 OpenCL variant 生成 `gmx_mpi_ocl`。它不会因为 `GMX_GPU=CUDA` 自动变成 `gmx_cuda`，也不会因为 `GMX_GPU=OpenCL` 自动变成 `gmx_ocl_mpi`。

`_mk_gromacs` 的 `double` variant 显式设置 `GMX_DOUBLE=ON`；`_batch_mk_gromacs` 为它传入 `${suffix}_d`，因此仅修改 task output 名称不会改变实际二进制名。
Linux target 的 `_batch_mk_gromacs` 为 OCL 依赖传入 `${suffix}_ocl`，生成 `gmx_ocl`（default）或 `gmx_mpi_ocl`（MPI environment）。

当前配置的 suffix 状态如下：

```text
osx-arm64 mpi5: GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_mpi，GMX_LIBS_SUFFIX=_mpi，输出 gmx_mpi
osx-arm64 mpis: GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_ompi，GMX_LIBS_SUFFIX=_ompi，输出 gmx_ompi
linux-64 mpi5/mpis: GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_mpi，GMX_LIBS_SUFFIX=_mpi，输出 gmx_mpi
linux-64 default: GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=，GMX_LIBS_SUFFIX=，输出 gmx
Linux OCL variant: GMX_DEFAULT_SUFFIX=OFF，GMX_BINARY_SUFFIX=_mpi_ocl，GMX_LIBS_SUFFIX=_mpi_ocl，输出 gmx_mpi_ocl
double build:   `_batch_mk_gromacs` 传入 `suffix=${suffix}_d`，生成相应的 `GMX_BINARY_SUFFIX` 和 `GMX_LIBS_SUFFIX`
```

对应的库名称分别为 standard MPI build 的 `libgromacs_mpi`、macOS Open MPI build 的 `libgromacs_ompi`、double build 的对应 `${suffix}_d` 库，以及 Linux OpenCL build 的 `libgromacs_mpi_ocl`。
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

GROMACS 2023.5 默认开启 OpenMP；`GMX_THREAD_MPI=OFF` 只关闭内置 thread-MPI，MPI feature 根据 environment 设置 `GMX_MPI=ON` 或 `GMX_MPI=OFF`，并不关闭 OpenMP。

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

## GROMACS GPU/MPI Patch

当前 GROMACS 2023.5 使用的 GPU/MPI 修复对应 upstream commit
`0f7ac8c9984145cd7a7ba15e6833ef6a4761ffdc`，标题为
`Fix building with GPUs and GMX_THREAD_MPI=OFF`，用于修复
`GMX_THREAD_MPI=OFF` 时 CUDA 源码中未受保护的 MPI 调用。

该 commit 首次进入正式 release 是 **GROMACS 2024.3**（2024-08-29）。
GROMACS 2024.2 尚未包含该 commit，2024.3 及之后的 release 已包含。
上游 commit：
`https://github.com/gromacs/gromacs/commit/0f7ac8c9984145cd7a7ba15e6833ef6a4761ffdc`。

当前 2023.5 patch 文件为该 commit 的 backport：
`patches/gromacs_2023.5/0f7ac8c9984145cd7a7ba15e6833ef6a4761ffdc-fix-gpu-thread-mpi-off.patch`。
2023.5 的源码结构与上游 commit 时的版本不同，因此 patch 只应用
`pme_gpu_grid.cu` 和 `mdgraph_gpu_impl.cu` 中适用于 2023.5 的 CUDA guard；
上游两个 NVSHMEM 相关 `.cpp` hunk 不能直接套用。

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
