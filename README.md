# Auto-Rice Bootstrapping Script

Installs my full Arch/Artix desktop — my builds of dwm, st, dmenu and
dwmblocks, plus my [dotfiles](https://github.com/james5618/dotfiles) — on a
fresh install.

## Usage

As root on a fresh Arch or Artix install:

```sh
curl -LO https://raw.githubusercontent.com/james5618/bootstrap/master/bootstrap.sh
sh bootstrap.sh
```

## Files

- `bootstrap.sh` — the installer; the repos it deploys are set in its
  CONFIGURATION block
- `progs.csv` — the list of programs to install: `tag,program,comment`
  (blank tag = pacman, `A` = AUR, `G` = git+make, `P` = pip)


