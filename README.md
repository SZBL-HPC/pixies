# pixies
repo for Pixi toml files.

Install [Pixi](https://pixi.prefix.dev/) first: `curl -fsSL https://pixi.sh/install.sh | sh`

Then clone this repo as: `git clone https://github.com/SZBL-HPC/pixies.git`

## rmats-turbo

Uses multiple environments to allow **rMATS** to run with Python 3, while **DARTS** runs with Python 2 via **Rscript**.

```bash
cd rmats-turbo
pixi run install
pixi run test
pixi run help
```

You can symlink `./rmats-turbo/rmats` to a directory in your `PATH` so that the `rmats` command can be run directly from anywhere.
