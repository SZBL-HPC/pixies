import os
import platform
import pkgconfig
from setuptools import setup, Extension
from cffi import FFI

# 1. Configuration and Dependency Discovery
samver = "1.15.1"
file_directory = os.path.dirname(os.path.realpath(__file__))
src_dir = os.path.join(file_directory, 'Clair3', 'src')

# Use pkg-config to find htslib and its dependencies (curl, crypto, bz2, etc.)
if not pkgconfig.exists('htslib'):
    raise RuntimeError("htslib not found. Please install it or set PKG_CONFIG_PATH.")

# pkgconfig.parse returns a dict with 'libraries', 'library_dirs', 'include_dirs', etc.
hts_config = pkgconfig.parse('htslib')

# 2. Setup Compiler Flags
extra_compile_args = ['-std=c99', '-O3']
extra_link_args = []

if platform.machine() in {"aarch64", "arm64"}:
    if platform.system() != "Darwin":
        extra_compile_args.append("-march=armv8-a+simd")
else:
    extra_compile_args.append("-mtune=haswell")
    # If using Conda, ensure rpath is set so libraries are found at runtime
    if 'CONDA_PREFIX' in os.environ:
        extra_link_args.append(f"-Wl,-rpath,{os.environ['CONDA_PREFIX']}/lib")

# 3. CFFI Builder Configuration
ffibuilder = FFI()

# Define source code and link configurations
ffibuilder.set_source(
    "libclair3",
    r"""
    #include "kvec.h"
    #include "khash.h"
    #include "levenshtein.h"
    #include "medaka_bamiter.h"
    #include "medaka_common.h"
    #include "medaka_khcounter.h"
    #include "clair3_pileup.h"
    #include "clair3_full_alignment.h"
    """,
    # Merge pkg-config results with local source paths
    libraries=hts_config['libraries'],
    library_dirs=hts_config['library_dirs'],
    include_dirs=[src_dir] + hts_config['include_dirs'],
    sources=[
        os.path.join(src_dir, x) for x in (
            'levenshtein.c', 'medaka_bamiter.c', 'medaka_common.c',
            'medaka_khcounter.c', 'clair3_pileup.c', 'clair3_full_alignment.c'
        )
    ],
    extra_compile_args=extra_compile_args,
    extra_link_args=extra_link_args,
)

# 4. Process Headers for cdef
cdef = [
    "typedef struct { ...; } bam_fset;",
    "bam_fset* create_bam_fset(char* fname, char* fasta_path);",
    "void destroy_bam_fset(bam_fset* fset);"
]

for header in ('clair3_pileup.h', 'clair3_full_alignment.h'):
    header_path = os.path.join(src_dir, header)
    with open(header_path, 'r') as fh:
        # Strip preprocessor directives for CFFI parser
        lines = ''.join(x for x in fh.readlines() if not x.strip().startswith('#'))
        cdef.append(lines)

ffibuilder.cdef('\n\n'.join(cdef))

# 5. Integration with Setuptools
if __name__ == "__main__":
    setup(
        name="clair3-cffi",
        version="1.0",
        ext_modules=[ffibuilder.distutils_extension()],
        zip_safe=False,
    )
