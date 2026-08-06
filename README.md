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



## FreeBSD

The `freebsd` branch installs the same desktop on FreeBSD 15. As root on a
fresh install:

```sh
fetch https://raw.githubusercontent.com/james5618/bootstrap/freebsd/bootstrap-freebsd.sh
sh bootstrap-freebsd.sh
```

`bootstrap.sh` also detects FreeBSD with `uname` and hands off to this script,
so the Arch entry point works there too.

What differs from the Arch install:

- packages come from `pkg(8)`, with the repository switched to the `latest`
  branch; the account is created with `pw(8)` and `sudoers.d` lives under
  `/usr/local/etc`
- the suckless programs are built from their **`freebsd` branches**, which fix
  the `/usr/local` include paths and, for dwmblocks, replace Linux's
  `signalfd(2)` with `sigwaitinfo(2)`
- the dotfiles come from their `freebsd` branch, where the statusbar modules
  read sysctls, `ifconfig` and `netstat` instead of `/proc` and `/sys`
- input needs `kern.evdev.rcpt_mask=12` for `xf86-input-libinput`, and a
  virtual machine needs a framebuffer driver named explicitly: `scfb` when the
  guest booted with UEFI, `vesa` when it booted with a legacy BIOS (scfb draws
  on the EFI framebuffer, so it finds no screen at all there), and
  `xf86-video-vmware` under VMware, but only when a `vmwgfx` DRM device
  exists, since without one that driver finds no screen either. The script
  picks from `machdep.bootmethod` and records the choice in
  `/tmp/bootstrap-build.log`
- VMware guests get `xf86-video-vmware` and `open-vm-tools`, which is what
  lets the display follow the size of the VMware window. The driver's legacy
  path needs no DRM device, which is just as well: `vmwgfx` was dropped after
  FreeBSD 12.3 and `drm-kmod` carries only the Intel and AMD modules. On the
  generic framebuffer drivers the guest is stuck with a VESA mode that need
  not match the window at all, and the desktop ends up taller than what you
  can see
- a machine with no hostname is asked for one: bsdinstall leaves it empty if
  that step is skipped, which leaves the shell prompt with nothing after the
  `@` and sudo unable to resolve the host
- audio is the base system's OSS: no pipewire, no pulseaudio and no session
  manager. mpd writes to `/dev/dsp`, the volume module drives `mixer(8)` and
  `mixertui` is what it opens on click
- LibreWolf has no FreeBSD build, so Firefox is installed and symlinked as
  `librewolf`, which is the name the dotfiles use
- `/bin/sh` is left alone: it is already a small POSIX shell and the base
  system's rc scripts depend on it

## Files

- `bootstrap-freebsd.sh` — the FreeBSD installer
- `progs-freebsd.csv` — the FreeBSD program list: `tag,program,comment`
  (blank tag = pkg, `G` = git+make, `P` = pip; `A`/AUR entries are skipped)
