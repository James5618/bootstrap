#!/bin/sh

# James's Auto-Rice Bootstrapping Script - FreeBSD edition
# For FreeBSD 15. Arch-based systems are handled by bootstrap.sh and the RHEL
# family by bootstrap-rhel.sh; bootstrap.sh hands off to this script
# automatically when it finds itself on FreeBSD.
# License: GNU GPLv3

### CONFIGURATION ###

dotfilesrepo="https://github.com/james5618/dotfiles.git"
repobranch="freebsd"
progsfile="https://raw.githubusercontent.com/james5618/bootstrap/freebsd/progs-freebsd.csv"

rssurls="https://www.freebsd.org/news/feed.xml \"tech\"
https://forums.freebsd.org/forums/-/index.rss \"tech\"
https://github.com/james5618/dotfiles/commits/freebsd.atom \"~dotfiles\""

# whiptail needs a usable TERM, but forcing "ansi" makes it mis-size itself and
# draw the dialogs into a corner of the console, so only set it when the
# inherited TERM is unusable.
case "$TERM" in
"" | dumb | unknown) export TERM=ansi ;;
esac

### HELPER FUNCTIONS ###

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

info() {
	# Show a progress message while the script works.
	whiptail --title "Bootstrap Installation" --infobox "$1" 9 70
}

ask() {
	# Prompt for a line of input, e.g.: ask [--nocancel] --inputbox "Question"
	whiptail "$@" 10 60 3>&1 1>&2 2>&3 3>&1
}

faillog="/tmp/bootstrap-failed.log"
buildlog="/tmp/bootstrap-build.log"
pkglog="/tmp/bootstrap-pkg.log"

# Never let git stop and ask for credentials: a repository that has moved or
# gone private answers with 401, and an unattended install would sit at a
# username prompt forever instead of skipping it.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true
export GIT_SSH_COMMAND="ssh -oBatchMode=yes"

# pkg(8) must never stop to ask a question during an unattended install.
export ASSUME_ALWAYS_YES=yes
export IGNORE_OSVERSION=yes

# Ports and packages live under /usr/local, which is not on the compiler's
# default search path, and the suckless builds link against libraries there.
export CPPFLAGS="-I/usr/local/include $CPPFLAGS"
export LDFLAGS="-L/usr/local/lib $LDFLAGS"
export PKG_CONFIG_PATH="/usr/local/libdata/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

installpkg() {
	# Install $1 from the package repository, quietly, recording what did not
	# install: a silent failure is how a missing compositor or font goes
	# unnoticed until first login.
	pkg install -y "$1" >>"$pkglog" 2>&1 && return 0
	# Python packages carry the ports tree's default interpreter version in
	# their name, and that moves between releases, so a py311- prefix written
	# here goes stale. Try the same package under any python before giving up.
	case "$1" in
	py3*-*) pkg install -y -g "py3*-${1#*-}" >>"$pkglog" 2>&1 && return 0 ;;
	esac
	echo "$1" >>"$faillog"
	return 1
}

### USER DIALOGUES ###

welcomemsg() {
	whiptail --title "Welcome!" \
		--msgbox "Welcome to James's Auto-Rice Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured FreeBSD desktop, configured the way I use my main machine.\\n\\n-James" 10 60

	whiptail --title "Important Note!" --yes-button "All ready!" \
		--no-button "Return..." \
		--yesno "Be sure the computer you are using has a current package repository (\`pkg update\`).\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

getuserandpass() {
	# Prompt for the name and password of the new user account.
	name=$(ask --inputbox "First, please enter a name for the user account.") || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(ask --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _.")
	done
	pass1=$(ask --nocancel --passwordbox "Enter a password for that user.")
	pass2=$(ask --nocancel --passwordbox "Retype password.")
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(ask --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again.")
		pass2=$(ask --nocancel --passwordbox "Retype password.")
	done
}

usercheck() {
	# Warn before overwriting the dotfiles of an existing user.
	! { id -u "$name" >/dev/null 2>&1; } ||
		whiptail --title "WARNING" --yes-button "CONTINUE" \
			--no-button "No wait..." \
			--yesno "The user \`$name\` already exists on this system. The script can install for an already existing user, but it will OVERWRITE any conflicting settings/dotfiles on the user account.\\n\\nIt will NOT overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that it will change $name's password to the one you just gave." 14 70
}

askhostname() {
	# bsdinstall leaves the hostname empty when that step is skipped, and the
	# machine then calls itself "Amnesiac" at the login prompt. It is worth
	# fixing rather than ignoring: the shell prompt shows nothing after the @,
	# and sudo complains it cannot resolve the host on every call.
	case "$(hostname 2>/dev/null)" in
	"" | Amnesiac | localhost) ;;
	*) return 0 ;;
	esac
	newhostname=$(ask --inputbox "This machine has no hostname. Enter one (or leave it blank for \"freebsd\").")
	while [ -n "$newhostname" ] &&
		! echo "$newhostname" | grep -q "^[a-zA-Z0-9][a-zA-Z0-9.-]*$"; do
		newhostname=$(ask --nocancel --inputbox "Hostname not valid. Use letters, numbers, - and . only.")
	done
	[ -n "$newhostname" ] || newhostname="freebsd"
}

sethostname() {
	[ -n "$newhostname" ] || return 0
	info "Setting the hostname to \"$newhostname\"..."
	hostname "$newhostname"
	sysrc hostname="$newhostname" >/dev/null 2>&1
	# Give the name something to resolve to, or every lookup of it waits for
	# DNS to time out first.
	grep -q "[[:space:]]$newhostname\$" /etc/hosts 2>/dev/null ||
		printf '127.0.0.1\t%s\n::1\t\t%s\n' "$newhostname" "$newhostname" >>/etc/hosts
}

preinstallmsg() {
	whiptail --title "Let's get this party started!" --yes-button "Let's go!" \
		--no-button "No, nevermind!" \
		--yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || {
		clear
		exit 1
	}
}

finalize() {
	whiptail --title "All done!" \
		--msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically on ttyv0).\\n\\n-James" 13 80
}

### INSTALLATION FUNCTIONS ###

adduserandpass() {
	# Add user `$name` with password $pass1. FreeBSD manages accounts with
	# pw(8); there is no useradd, and the shell has to be given by full path
	# because zsh comes from ports.
	info "Adding user \"$name\"..."
	zshpath="/usr/local/bin/zsh"
	[ -x "$zshpath" ] || zshpath="/bin/sh"
	pw useradd -n "$name" -m -d "/home/$name" -G wheel,video,operator \
		-s "$zshpath" >/dev/null 2>&1 ||
		pw usermod -n "$name" -G wheel,video,operator -s "$zshpath" >/dev/null 2>&1
	mkdir -p "/home/$name"
	chown "$name:wheel" "/home/$name"
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name:wheel" "$(dirname "$repodir")"
	echo "$pass1" | pw usermod "$name" -h 0 >/dev/null 2>&1
	unset pass1 pass2
}

setuprepos() {
	# The quarterly branch is the default and can be months behind; the rice
	# wants current versions of picom, pipewire and the fonts, so switch to
	# the latest branch.
	#
	# Derive the override from the system's own repository definition rather
	# than writing a fresh one. A definition that sets only a url drops the
	# mirror type, the signature type and the fingerprint path that came with
	# it, and the pkg+http:// scheme is not usable without the first of those:
	#
	#   packagesite URL error for pkg+http://... -- pkg+:// implies SRV mirror type
	#
	# Copying the file and changing only the branch keeps all of that intact,
	# and picks up any extra repository (FreeBSD-base) the release ships.
	info "Pointing pkg at the latest branch and refreshing the catalogue..."
	conf="/usr/local/etc/pkg/repos/FreeBSD.conf"
	if [ ! -e "$conf" ] && [ -f /etc/pkg/FreeBSD.conf ]; then
		mkdir -p /usr/local/etc/pkg/repos
		sed 's|/quarterly|/latest|' /etc/pkg/FreeBSD.conf >"$conf"
	fi

	pkg update -f >>"$pkglog" 2>&1 && return 0

	# That override is the only thing this script changes about pkg's
	# configuration, so if the catalogue will not update, take it back out and
	# try again with the system's own repository. This also repairs the
	# machine after an earlier run of this script left a bad override behind.
	[ -e "$conf" ] || return 1
	info "The \"latest\" package branch is not usable here; going back to the default one."
	rm -f "$conf"
	pkg update -f >>"$pkglog" 2>&1
}

maininstall() {
	# Install $1 from the package repository.
	info "Installing \`$1\` ($n of $total). $1 $2"
	installpkg "$1"
}

gitmakeinstall() {
	# Clone the git repo $1 and build and install it with make. The suckless
	# Makefiles are written for GNU make, so use gmake where it is available
	# and fall back to the base system's bmake.
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	branch="${3:-freebsd}"
	info "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q -b "$branch" "$1" "$dir" ||
		sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
			--no-tags -q "$1" "$dir" ||
		{
			cd "$dir" || return 1
			sudo -u "$name" git pull --force
		}
	cd "$dir" || exit 1
	makecmd="$(command -v gmake || command -v make)"
	{ $makecmd && $makecmd install; } >>"$buildlog" 2>&1 ||
		echo "$progname (make)" >>"$faillog"
	cd /tmp || return 1
}

pipinstall() {
	# Install the Python package $1 with pip. Python on FreeBSD refuses to
	# install into the system prefix without this flag.
	info "Installing the Python package \`$1\` ($n of $total). $1 $2"
	[ -x "$(command -v "pip")" ] || installpkg py311-pip >/dev/null 2>&1
	yes | pip install --break-system-packages "$1" >>"$buildlog" 2>&1 ||
		echo "$1 (pip)" >>"$faillog"
}

installationloop() {
	# Read the progs file and install each program the way its tag requires.
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
	total=$(wc -l </tmp/progs.csv)
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		echo "$comment" | grep -q "^\".*\"$" &&
			comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
		"A") ;; # AUR entries are Arch-only; skip them here.
		"G") gitmakeinstall "$program" "$comment" ;;
		"P") pipinstall "$program" "$comment" ;;
		*) maininstall "$program" "$comment" ;;
		esac
	done </tmp/progs.csv
}

putgitrepo() {
	# Download the git repo $1 into $2, only overwriting conflicting files.
	info "Downloading and installing config files..."
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name:wheel" "$dir" "$2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 \
		--single-branch --no-tags -q --recursive -b "$branch" \
		--recurse-submodules "$1" "$dir"
	# BSD cp has no -T; the trailing /. copies the contents of the directory,
	# dotfiles included, rather than the directory itself.
	sudo -u "$name" cp -Rf "$dir/." "$2/"
}

vimplugininstall() {
	# Install neovim plugins.
	info "Installing neovim plugins..."
	mkdir -p "/home/$name/.config/nvim/autoload"
	curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" >"/home/$name/.config/nvim/autoload/plug.vim"
	chown -R "$name:wheel" "/home/$name/.config/nvim"
	sudo -u "$name" nvim -c "PlugInstall|q|q"
}

makeuserjs() {
	# Get the Arkenfox user.js and prepare it.
	arkenfox="$pdir/arkenfox.js"
	overrides="$pdir/user-overrides.js"
	userjs="$pdir/user.js"
	ln -fs "/home/$name/.config/firefox/user-overrides.js" "$overrides"
	[ ! -f "$arkenfox" ] && curl -sL "https://raw.githubusercontent.com/arkenfox/user.js/master/user.js" >"$arkenfox"
	cat "$arkenfox" "$overrides" >"$userjs"
	chown "$name:wheel" "$arkenfox" "$userjs"
}

browserinstall() {
	# LibreWolf has no FreeBSD package, which would leave the system with no
	# browser at all. Install Firefox instead and expose it under the name the
	# dotfiles expect, since $BROWSER and the keybindings both say "librewolf"
	# and those files are shared with the Arch install.
	[ -x "$(command -v librewolf)" ] && return 0
	installpkg firefox || return 1
	ln -sf "$(command -v firefox)" /usr/local/bin/librewolf
}

nerdfontinstall() {
	# The packaged nerd-fonts collection is enormous; try it, and fall back to
	# fetching just JetBrainsMono from upstream. Without the icon glyphs the
	# status bar renders as boxes.
	fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && return 0
	info "Installing the JetBrainsMono Nerd Font..."
	installpkg unzip
	fontdir="/usr/local/share/fonts/JetBrainsMonoNerd"
	tmpdir="$(mktemp -d)"
	if curl -fLs -o "$tmpdir/JetBrainsMono.zip" \
		"https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"; then
		mkdir -p "$fontdir"
		unzip -oq "$tmpdir/JetBrainsMono.zip" -d "$fontdir" >/dev/null 2>&1
	fi
	rm -rf "$tmpdir"
	fc-cache -f >/dev/null 2>&1
	fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && return 0
	# Last resort: the packaged collection. It is left until now because it is
	# a metaport of every nerd font there is and pulls gigabytes.
	pkg install -y nerd-fonts >/dev/null 2>&1
	fc-cache -f >/dev/null 2>&1
	fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"
}

setupx() {
	# X needs evdev to reach the keyboard and mouse through libinput, and the
	# device nodes only appear once the receiver mask is set. Without this the
	# desktop starts with dead input.
	info "Configuring the graphical stack..."
	sysrc dbus_enable=YES >/dev/null 2>&1
	sysrc devd_enable=YES >/dev/null 2>&1
	sysrc moused_enable=YES >/dev/null 2>&1
	grep -q "^kern.evdev.rcpt_mask" /etc/sysctl.conf 2>/dev/null ||
		echo "kern.evdev.rcpt_mask=12" >>/etc/sysctl.conf
	sysctl kern.evdev.rcpt_mask=12 >/dev/null 2>&1

	# Xorg looks here for input and video configuration.
	mkdir -p /usr/local/etc/X11/xorg.conf.d
	[ -f /usr/local/etc/X11/xorg.conf.d/10-input.conf ] ||
		printf 'Section "InputClass"
	Identifier "libinput keyboard catchall"
	MatchIsKeyboard "on"
	MatchDevicePath "/dev/input/event*"
	Driver "libinput"
EndSection

Section "InputClass"
	Identifier "libinput touchpad catchall"
	MatchIsTouchpad "on"
	MatchDevicePath "/dev/input/event*"
	Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection\n' >/usr/local/etc/X11/xorg.conf.d/10-input.conf

	# In a virtual machine there is usually no accelerated driver at all, so a
	# framebuffer driver has to be named. Which one works depends on how the
	# machine booted, and getting it wrong is not a soft failure: scfb draws
	# on the EFI framebuffer, so under a legacy BIOS boot it probes, finds
	# nothing, and Xorg dies with "no screens found". vesa is the one that
	# works there.
	#
	# An earlier version of this script pinned scfb either way; clear that.
	rm -f /usr/local/etc/X11/xorg.conf.d/20-scfb.conf
	videoconf="/usr/local/etc/X11/xorg.conf.d/20-video.conf"
	case "$(sysctl -n machdep.bootmethod 2>/dev/null)" in
	UEFI) fbdriver="scfb" ;;
	*) fbdriver="vesa" ;;
	esac

	case "$(sysctl -n kern.vm_guest 2>/dev/null)" in
	"" | none) ;;
	vmware)
		# The guest tools resize the display with the window, share the
		# clipboard and keep the clock in step. service(8) enables each rc
		# script by its own rcvar, so none has to be named here.
		installpkg open-vm-tools && {
			for svc in vmware-kmod vmware-guestd; do
				service "$svc" enable >/dev/null 2>&1
				service "$svc" start >/dev/null 2>&1
			done
		}
		# The vmware driver, in its legacy path, talks to the SVGA adapter
		# directly and needs no DRM device: vmwgfx does not exist on FreeBSD
		# any more (it was dropped after 12.3, and graphics/drm-kmod carries
		# only the Intel and AMD modules), so there is no /dev/dri to wait
		# for here and never will be.
		#
		# It matters because it is the driver open-vm-tools resizes through.
		# On the generic framebuffer drivers the guest is stuck with whatever
		# the VESA mode table offers, which need not match the size of the
		# VMware window - and then the desktop is taller than what is
		# visible, with windows running off the bottom of it.
		if installpkg xf86-video-vmware; then
			videodriver="vmware"
		else
			videodriver="$fbdriver"
		fi
		;;
	*) videodriver="$fbdriver" ;;
	esac

	[ -n "$videodriver" ] && [ ! -f "$videoconf" ] &&
		printf 'Section "Device"
	Identifier "Card0"
	Driver "%s"
EndSection\n' "$videodriver" >"$videoconf"

	# Worth being able to look this up after the fact: a black screen at
	# first login is nearly always the wrong choice here.
	echo "video: driver=${videodriver:-autodetect} bootmethod=$(sysctl -n machdep.bootmethod 2>/dev/null) guest=$(sysctl -n kern.vm_guest 2>/dev/null)" >>"$buildlog"

	service dbus start >/dev/null 2>&1
}

setupaudio() {
	# Audio here is the base system's OSS: no daemon, no session manager and
	# nothing to autostart. mpd writes straight to /dev/dsp, the volume module
	# drives mixer(8), and every program opens the device directly - the
	# kernel mixes them itself through vchans.
	info "Configuring audio..."
	# GENERIC has the common drivers, but snd_driver pulls in the rest, which
	# is what makes a sound card in an older machine or an odd hypervisor
	# appear at all.
	sysrc kld_list+="snd_driver" >/dev/null 2>&1
	kldload snd_driver >/dev/null 2>&1

	# If there are several devices (HDMI as well as the speakers, say), the
	# first is not always the one you want; leave a pointer rather than
	# guessing on the user's behalf.
	if [ "$(sysctl -n dev.pcm.%parent 2>/dev/null | wc -w)" -gt 1 ]; then
		info "More than one sound device: if the wrong one plays, set hw.snd.default_unit (see \`cat /dev/sndstat\`)."
	fi

	# vt(4) beeps through the console; the rice does not want that.
	grep -q "^kern.vt.enable_bell" /etc/sysctl.conf 2>/dev/null ||
		echo "kern.vt.enable_bell=0" >>/etc/sysctl.conf
	sysctl kern.vt.enable_bell=0 >/dev/null 2>&1
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Sanity check: this script is for FreeBSD only.
[ "$(uname -s)" = "FreeBSD" ] ||
	error "This script is for FreeBSD. Use bootstrap.sh on Arch-based systems and bootstrap-rhel.sh on Fedora/RHEL."

[ "$(id -u)" = 0 ] || error "This script must be run as root."

# Bootstrap pkg itself if this is a truly fresh install.
pkg bootstrap -y >/dev/null 2>&1

# A failed run of an older version of this script could leave a repository
# override behind that pkg cannot use, and every install from here on would
# fail with it in place. Take it out before anything depends on the
# catalogue; setuprepos writes a good one later.
pkg update >>"$pkglog" 2>&1 || {
	rm -f /usr/local/etc/pkg/repos/FreeBSD.conf
	pkg update -f >>"$pkglog" 2>&1
}

# Install whiptail for the dialogs.
pkg install -y newt ||
	error "Could not install newt. Are you sure you have an internet connection and a working pkg repository? See $pkglog."

# Welcome the user and remind them to update before running.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Ask for a hostname if the machine has none; it is set further down.
askhostname

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

rm -f "$faillog"

setuprepos ||
	info "Could not refresh the package catalogue; continuing, and any package that will not install is reported at the end."

# Install the tools needed for the rest of the installation. Unlike Linux
# distributions, FreeBSD ships the compiler and make in the base system, so
# only the ports-supplied pieces are needed here.
# The X metaport itself is left to the program list; what is needed this early
# is only what the suckless programs link against.
for x in curl git zsh gmake pkgconf sudo \
	libX11 libXft libXinerama libXrandr libXext libxcb harfbuzz \
	fontconfig freetype2 ntp; do
	info "Installing \`$x\` which is required to install and configure other programs."
	installpkg "$x"
done

info "Synchronizing system time to ensure successful and secure installation of software..."
ntpdate -b pool.ntp.org >/dev/null 2>&1 || service ntpd onestart >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

sethostname

# Allow the user to run sudo without a password during the install; several
# build steps run as the user and then need root to install.
trap 'rm -f /usr/local/etc/sudoers.d/bootstrap-temp' HUP INT QUIT TERM EXIT
mkdir -p /usr/local/etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/usr/local/etc/sudoers.d/bootstrap-temp
chmod 440 /usr/local/etc/sudoers.d/bootstrap-temp

# The command that does all the installing: reads the progs file and installs
# each needed program the way required.
installationloop

nerdfontinstall ||
	info "Could not install the JetBrainsMono Nerd Font; the bar will fall back to a plain monospace font."

browserinstall ||
	info "Could not install a browser."

setupx
setupaudio

# Install the dotfiles in the user's home directory, but remove .git dir and
# other unnecessary files.
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -rf "/home/$name/.git/" "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"
chown -R "$name:wheel" "/home/$name"

# Write urls for newsboat if it doesn't already exist.
[ -s "/home/$name/.config/newsboat/urls" ] ||
	echo "$rssurls" | sudo -u "$name" tee "/home/$name/.config/newsboat/urls" >/dev/null

# Install vim plugins if not already present.
[ ! -f "/home/$name/.config/nvim/autoload/plug.vim" ] && vimplugininstall

# Shells from ports have to be listed in /etc/shells before chsh(1) will
# accept them, so this has to come first.
for shell in /usr/local/bin/zsh /usr/local/bin/dash; do
	[ -x "$shell" ] && ! grep -qx "$shell" /etc/shells 2>/dev/null &&
		echo "$shell" >>/etc/shells
done

# Make zsh the default shell for the user.
[ -x /usr/local/bin/zsh ] && chsh -s /usr/local/bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/abook/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# Note: the Arch script repoints /bin/sh at dash. Do not do that here - FreeBSD
# /bin/sh is already a small POSIX shell, and the whole base system's rc
# scripts depend on it being exactly what it is.

# All this below to get the browser installed with add-ons and non-bad
# settings.
info "Setting browser privacy settings and add-ons..."

# Start the browser headless so it generates a profile, then grab that
# profile. Where it lands depends on which browser is wearing the librewolf
# name: LibreWolf keeps its profile in ~/.librewolf, but the browser this
# script installs is Firefox, which keeps it in ~/.mozilla/firefox - so look
# for both rather than assuming. Creating it is not instant either, and the
# old fixed one-second wait was often not enough.
sudo -u "$name" librewolf --headless >/dev/null 2>&1 &
browserdir=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
	for d in "/home/$name/.librewolf" "/home/$name/.mozilla/firefox"; do
		[ -f "$d/profiles.ini" ] && browserdir="$d"
	done
	[ -n "$browserdir" ] && break
	sleep 1
done

if [ -n "$browserdir" ]; then
	profile="$(sed -n "/Default=.*.default-default/ s/.*=//p" "$browserdir/profiles.ini" 2>/dev/null)"
	pdir="$browserdir/$profile"
	# Both tests matter: an empty $profile would make $pdir the browser
	# directory itself, and user.js would land somewhere useless.
	[ -n "$profile" ] && [ -d "$pdir" ] && makeuserjs
fi

# Kill the now-unnecessary browser instance. It is Firefox underneath, so the
# process is not called librewolf and matching that name alone leaves it
# running - which is what makes the next launch report that the browser is
# already open. Clear the profile locks it may leave behind too.
pkill -u "$name" -f "librewolf|firefox" >/dev/null 2>&1
sleep 2
pkill -9 -u "$name" -f "librewolf|firefox" >/dev/null 2>&1
[ -n "$pdir" ] && rm -f "$pdir/lock" "$pdir/.parentlock"

# Allow wheel users to sudo with a password, and let a few system commands run
# without one. Paths differ from Linux: everything from ports is in
# /usr/local/{bin,sbin} and the base tools are in /sbin.
echo "%wheel ALL=(ALL:ALL) ALL" >/usr/local/etc/sudoers.d/00-bootstrap-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /sbin/shutdown,/sbin/reboot,/sbin/halt,/usr/sbin/acpiconf,/sbin/mount,/sbin/umount,/sbin/mount_msdosfs,/usr/local/bin/ntfs-3g,/sbin/geli,/usr/local/sbin/pkg update,/usr/local/sbin/pkg upgrade" >/usr/local/etc/sudoers.d/01-bootstrap-cmds-without-password
echo "Defaults editor=/usr/local/bin/nvim" >/usr/local/etc/sudoers.d/02-bootstrap-visudo-editor
chmod 440 /usr/local/etc/sudoers.d/00-bootstrap-wheel-can-sudo \
	/usr/local/etc/sudoers.d/01-bootstrap-cmds-without-password \
	/usr/local/etc/sudoers.d/02-bootstrap-visudo-editor

# Clean up the temporary passwordless-sudo rule.
rm -f /usr/local/etc/sudoers.d/bootstrap-temp

# Report anything that did not install. Package names vary between the
# quarterly and latest branches, so this is the list to work through after a
# run.
if [ -s "$faillog" ]; then
	sort -u "$faillog" -o "$faillog"
	whiptail --title "Skipped: $(wc -l <"$faillog") packages (saved in $faillog)" \
		--scrolltext --textbox "$faillog" 20 70
fi

# Last message! Install complete!
finalize
