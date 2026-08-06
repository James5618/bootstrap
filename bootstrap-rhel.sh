#!/bin/sh

# James's Auto-Rice Bootstrapping Script - RHEL-family edition
# For Fedora, CentOS Stream, Rocky and AlmaLinux. Arch-based systems are
# handled by bootstrap.sh, which hands off to this script automatically.
# License: GNU GPLv3

### CONFIGURATION ###

dotfilesrepo="https://github.com/james5618/dotfiles.git"
repobranch="master"
progsfile="https://raw.githubusercontent.com/james5618/bootstrap/rhel/progs-rhel.csv"

rssurls="https://fedoramagazine.org/feed/ \"tech\"
https://github.com/james5618/dotfiles/commits/master.atom \"~dotfiles\""

# whiptail needs a usable TERM, but forcing "ansi" makes it mis-size itself and
# draw the dialogs into a corner of a Linux virtual console, so only set it
# when the inherited TERM is unusable.
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

# Never let git stop and ask for credentials: a repository that has moved or
# gone private answers with 401, and an unattended install would sit at a
# username prompt forever instead of skipping it.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true
export GIT_SSH_COMMAND="ssh -oBatchMode=yes"

# Programs built from source install under /usr/local, and several of them are
# libraries that the later builds have to find: mpc needs libmpdclient and
# newsboat needs stfl, neither of which is packaged here.
export PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
export CPPFLAGS="-I/usr/local/include $CPPFLAGS"
export LDFLAGS="-L/usr/local/lib64 -L/usr/local/lib $LDFLAGS"

installpkg() {
	# Install $1 from the enabled repos, quietly, recording what did not
	# install: package names differ across this family and a silent failure
	# is how a missing compositor or font goes unnoticed until first login.
	dnf -y install "$1" >/dev/null 2>&1 || {
		echo "$1" >>"$faillog"
		return 1
	}
}

### USER DIALOGUES ###

welcomemsg() {
	whiptail --title "Welcome!" \
		--msgbox "Welcome to James's Auto-Rice Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured Linux desktop, configured the way I use my main machine.\\n\\n-James" 10 60

	whiptail --title "Important Note!" --yes-button "All ready!" \
		--no-button "Return..." \
		--yesno "Be sure the computer you are using has current updates applied.\\n\\nIf it does not, the installation of some programs might fail." 8 70
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
		--msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n-James" 13 80
}

### INSTALLATION FUNCTIONS ###

adduserandpass() {
	# Add user `$name` with password $pass1.
	info "Adding user \"$name\"..."
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
		usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name:wheel" /home/"$name"
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name:wheel" "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

setuprepos() {
	# Enable EPEL and CRB (neither needed on Fedora proper), the LibreWolf
	# vendor repository, and refresh metadata. CRB carries many of the -devel
	# packages the suckless programs and picom need to build, and is disabled
	# by default on the RHEL rebuilds.
	info "Enabling extra repositories and refreshing package metadata..."
	if [ "$ID" != "fedora" ]; then
		dnf -y install epel-release dnf-plugins-core >/dev/null 2>&1
		dnf config-manager --set-enabled crb >/dev/null 2>&1 ||
			dnf config-manager --set-enabled powertools >/dev/null 2>&1
	fi
	[ -f /etc/yum.repos.d/librewolf.repo ] ||
		curl -fsL "https://rpm.librewolf.net/librewolf-repo.repo" \
			>/etc/yum.repos.d/librewolf.repo 2>/dev/null
	dnf -y makecache >/dev/null 2>&1
}

maininstall() {
	# Install $1 from the main repos.
	info "Installing \`$1\` ($n of $total). $1 $2"
	installpkg "$1"
}

nerdfontinstall() {
	# The Nerd Font patched variants are not packaged on this family, but the
	# status bar and terminal expect their icon glyphs, and without the font
	# fontconfig falls through the monospace list to an icon font and renders
	# all text as dingbats.
	fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && return 0
	info "Installing the JetBrainsMono Nerd Font..."
	installpkg unzip
	fontdir="/usr/local/share/fonts/JetBrainsMonoNerd"
	tmpdir="$(mktemp -d)"
	curl -fLs -o "$tmpdir/JetBrainsMono.zip" \
		"https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" || {
		rm -rf "$tmpdir"
		return 1
	}
	mkdir -p "$fontdir"
	unzip -oq "$tmpdir/JetBrainsMono.zip" -d "$fontdir" >/dev/null 2>&1
	rm -rf "$tmpdir"
	fc-cache -f >/dev/null 2>&1
}

libertinusinstall() {
	# The Libertinus family is what fontconfig asks for as serif and sans, and
	# it is not packaged here. Its release assets carry the version in the
	# filename, so there is no fixed URL to fetch: ask the API for the latest.
	fc-list 2>/dev/null | grep -qi "Libertinus Serif" && return 0
	info "Installing the Libertinus fonts..."
	installpkg unzip
	url="$(curl -fsL --max-time 30 \
		"https://api.github.com/repos/alerque/libertinus/releases/latest" |
		grep -oE '"browser_download_url": *"[^"]+\.zip"' |
		head -1 | cut -d'"' -f4)"
	[ -n "$url" ] || return 1
	tmpdir="$(mktemp -d)"
	curl -fLs --max-time 120 -o "$tmpdir/libertinus.zip" "$url" || {
		rm -rf "$tmpdir"
		return 1
	}
	mkdir -p /usr/local/share/fonts/Libertinus
	unzip -oqj "$tmpdir/libertinus.zip" '*.otf' \
		-d /usr/local/share/fonts/Libertinus >/dev/null 2>&1
	rm -rf "$tmpdir"
	fc-cache -f >/dev/null 2>&1
	fc-list 2>/dev/null | grep -qi "Libertinus Serif"
}

picominstall() {
	# picom is not in EPEL, so if no repository provides it, build it from
	# source with meson. Without a compositor there are no rounded window
	# corners, transparency or fading.
	[ -x "$(command -v picom)" ] && return 0
	# A plain dnf attempt first: a miss here is expected and handled by the
	# source build below, so do not record it as a failed package.
	dnf -y install picom >/dev/null 2>&1
	[ -x "$(command -v picom)" ] && return 0
	info "picom is not packaged for this release; building it from source..."
	for x in meson ninja-build gcc pkgconf-pkg-config libxcb-devel \
		xcb-util-devel xcb-util-image-devel xcb-util-renderutil-devel \
		pixman-devel libev-devel libconfig-devel dbus-devel pcre2-devel \
		uthash-devel libepoxy-devel libglvnd-devel mesa-libGL-devel \
		mesa-libEGL-devel libX11-devel libXext-devel; do
		installpkg "$x"
	done
	# Everything here logs to $picomlog: a silent failure leaves the desktop
	# with no compositor and no clue why.
	picomlog="/tmp/bootstrap-picom.log"
	dir="$repodir/picom"
	{
		echo "=== picom build $(date) ==="
		sudo -u "$name" git -C "$repodir" clone --single-branch \
			"https://github.com/yshui/picom.git" "$dir" ||
			sudo -u "$name" git -C "$dir" pull --force
		# Build the newest release rather than the tip of the development
		# branch, so behaviour matches the packaged picom on other distros.
		# Ask git as the owning user: root reading a user-owned repository
		# trips git's dubious-ownership check and prints nothing, which then
		# turns into a checkout of an empty pathspec.
		tag="$(sudo -u "$name" git -C "$dir" describe --tags --abbrev=0 2>/dev/null)"
		[ -n "$tag" ] && sudo -u "$name" git -C "$dir" checkout -q "$tag"
		cd "$dir" &&
			sudo -u "$name" rm -rf build &&
			sudo -u "$name" meson setup --buildtype=release build &&
			sudo -u "$name" ninja -C build &&
			ninja -C build install
	} >>"$picomlog" 2>&1
	cd /tmp || return 1
	[ -x "$(command -v picom)" ] || return 1
}

xwallpaperinstall() {
	# xwallpaper is not packaged for this family either; build it from source
	# so setbg behaves the same here as it does on Arch.
	[ -x "$(command -v xwallpaper)" ] && return 0
	# A plain dnf attempt first: a miss here is expected and handled by the
	# source build below, so do not record it as a failed package.
	dnf -y install xwallpaper >/dev/null 2>&1
	[ -x "$(command -v xwallpaper)" ] && return 0
	info "xwallpaper is not packaged for this release; building it from source..."
	for x in autoconf automake libtool autoconf-archive pkgconf-pkg-config \
		libxcb-devel xcb-util-image-devel pixman-devel \
		libjpeg-turbo-devel libpng-devel libXpm-devel libseccomp-devel; do
		installpkg "$x"
	done
	dir="$repodir/xwallpaper"
	{
		echo "=== xwallpaper build $(date) ==="
		sudo -u "$name" git -C "$repodir" clone --single-branch \
			"https://github.com/stoeckmann/xwallpaper.git" "$dir" ||
			sudo -u "$name" git -C "$dir" pull --force
		cd "$dir" &&
			sudo -u "$name" ./autogen.sh &&
			# seccomp sandboxing is optional; do not fail the build over it
			{ sudo -u "$name" ./configure ||
				sudo -u "$name" ./configure --without-seccomp; } &&
			sudo -u "$name" make &&
			make install
	} >>"/tmp/bootstrap-xwallpaper.log" 2>&1
	cd /tmp || return 1
	[ -x "$(command -v xwallpaper)" ] || return 1
}

dunstinstall() {
	# dunst is not packaged for this family, and without it nothing that uses
	# notify-send works: the calendar popup, volume changes, wallpaper
	# changes and every module's help text are all notifications.
	[ -x "$(command -v dunst)" ] && return 0
	# A plain dnf attempt first: a miss here is expected and handled by the
	# source build below, so do not record it as a failed package.
	dnf -y install dunst >/dev/null 2>&1
	[ -x "$(command -v dunst)" ] && return 0
	info "dunst is not packaged for this release; building it from source..."
	for x in make gcc pkgconf-pkg-config dbus-devel libX11-devel \
		libXinerama-devel libXrandr-devel libXScrnSaver-devel \
		glib2-devel pango-devel cairo-devel gdk-pixbuf2-devel \
		libnotify-devel perl-podlators; do
		installpkg "$x"
	done
	dir="$repodir/dunst"
	{
		echo "=== dunst build $(date) ==="
		sudo -u "$name" git -C "$repodir" clone --single-branch \
			"https://github.com/dunst-project/dunst.git" "$dir" ||
			sudo -u "$name" git -C "$dir" pull --force
		# As above: the tag lookup has to run as the repository's owner.
		tag="$(sudo -u "$name" git -C "$dir" describe --tags --abbrev=0 2>/dev/null)"
		[ -n "$tag" ] && sudo -u "$name" git -C "$dir" checkout -q "$tag"
		cd "$dir" &&
			# X11 only: the Wayland backend needs libraries this family
			# does not ship and the rice is an X11 setup anyway.
			sudo -u "$name" make WAYLAND=0 &&
			make WAYLAND=0 install
	} >>"/tmp/bootstrap-dunst.log" 2>&1
	cd /tmp || return 1
	[ -x "$(command -v dunst)" ] || return 1
}

lfinstall() {
	# lf is a single Go binary; this family does not package it, but upstream
	# publishes release binaries.
	[ -x "$(command -v lf)" ] && return 0
	dnf -y install lf >/dev/null 2>&1
	[ -x "$(command -v lf)" ] && return 0
	info "lf is not packaged for this release; installing the upstream binary..."
	case "$(uname -m)" in
	x86_64) lfarch="amd64" ;;
	aarch64) lfarch="arm64" ;;
	*) return 1 ;;
	esac
	tmpdir="$(mktemp -d)"
	curl -fLs -o "$tmpdir/lf.tar.gz" \
		"https://github.com/gokcehan/lf/releases/latest/download/lf-linux-$lfarch.tar.gz" || {
		rm -rf "$tmpdir"
		return 1
	}
	tar -xzf "$tmpdir/lf.tar.gz" -C "$tmpdir" >/dev/null 2>&1 &&
		install -m 755 "$tmpdir/lf" /usr/local/bin/lf
	rm -rf "$tmpdir"
	[ -x "$(command -v lf)" ] || return 1
}

browserinstall() {
	# LibreWolf publishes no build for this family, which leaves the system
	# with no browser at all. Install Firefox instead and expose it under the
	# name the dotfiles expect, since $BROWSER and the keybindings both say
	# "librewolf" and those files are shared with the Arch install.
	[ -x "$(command -v librewolf)" ] && return 0
	installpkg firefox || return 1
	ln -sf "$(command -v firefox)" /usr/local/bin/librewolf
}

coprinstall() {
	# Install from a COPR repository; $1 is owner/project:package.
	repo="${1%%:*}"
	pkg="${1##*:}"
	info "Installing \`$pkg\` ($n of $total) from COPR ($repo). $2"
	dnf -y copr enable "$repo" >/dev/null 2>&1 || {
		echo "$pkg (could not enable COPR $repo)" >>"$faillog"
		return 1
	}
	installpkg "$pkg"
}

gitmakeinstall() {
	# Clone the git repo $1 and build and install it with make.
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	info "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{
			cd "$dir" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$dir" || exit 1
	{ make && make install; } >>"$buildlog" 2>&1 || echo "$progname (make)" >>"$faillog"
	ldconfig >/dev/null 2>&1
	cd /tmp || return 1
}

mesoninstall() {
	# Clone the git repo $1 and build it with meson: the music player daemon
	# and its client library use it and are not packaged for this family.
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	info "Installing \`$progname\` ($n of $total) from source with \`meson\`. $2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		sudo -u "$name" git -C "$dir" pull --force
	cd "$dir" || return 1
	{
		echo "=== $progname build $(date) ==="
		sudo -u "$name" rm -rf build
		sudo -u "$name" meson setup --prefix=/usr/local \
			--buildtype=release build &&
			sudo -u "$name" ninja -C build &&
			ninja -C build install
	} >>"$buildlog" 2>&1 || echo "$progname (meson)" >>"$faillog"
	ldconfig >/dev/null 2>&1
	cd /tmp || return 1
}

cmakeinstall() {
	# Clone the git repo $1 and build it with cmake.
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	info "Installing \`$progname\` ($n of $total) from source with \`cmake\`. $2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		sudo -u "$name" git -C "$dir" pull --force
	cd "$dir" || return 1
	{
		echo "=== $progname build $(date) ==="
		sudo -u "$name" rm -rf build
		sudo -u "$name" cmake -B build -DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX=/usr/local &&
			sudo -u "$name" cmake --build build &&
			cmake --install build
	} >>"$buildlog" 2>&1 || echo "$progname (cmake)" >>"$faillog"
	ldconfig >/dev/null 2>&1
	cd /tmp || return 1
}

autotoolsinstall() {
	# Clone the git repo $1 and build it with autotools. Many programs this
	# family does not package build this way; a plain `make` is not enough
	# because the configure script has to be generated and run first.
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	info "Installing \`$progname\` ($n of $total) from source. $(basename "$1") $2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		sudo -u "$name" git -C "$dir" pull --force
	cd "$dir" || return 1
	{
		echo "=== $progname build $(date) ==="
		# Generate configure when the repo ships only the autotools sources.
		[ -x ./configure ] || sudo -u "$name" ./autogen.sh ||
			sudo -u "$name" autoreconf -fi
		sudo -u "$name" ./configure --prefix=/usr/local &&
			sudo -u "$name" make &&
			make install
	} >>"$buildlog" 2>&1 || echo "$progname (autotools)" >>"$faillog"
	ldconfig >/dev/null 2>&1
	cd /tmp || return 1
}

pipinstall() {
	# Install the Python package $1 with pip.
	info "Installing the Python package \`$1\` ($n of $total). $1 $2"
	[ -x "$(command -v "pip")" ] || installpkg python3-pip >/dev/null 2>&1
	yes | pip install "$1"
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
		"C") coprinstall "$program" "$comment" ;;
		"G") gitmakeinstall "$program" "$comment" ;;
		"S") autotoolsinstall "$program" "$comment" ;;
		"M") mesoninstall "$program" "$comment" ;;
		"K") cmakeinstall "$program" "$comment" ;;
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
	sudo -u "$name" cp -rfT "$dir" "$2"
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

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Sanity check: this script is for the RHEL family only.
[ -f /etc/os-release ] && . /etc/os-release
case " $ID $ID_LIKE " in
*fedora* | *rhel* | *centos*) ;;
*) error "This script is for RHEL-family systems (Fedora/CentOS/Rocky/Alma). Use bootstrap.sh on Arch-based systems." ;;
esac

# Check that the user is root; install whiptail for dialogs.
dnf -y install newt ||
	error "Are you sure you're running this as the root user and have an internet connection?"

# Welcome the user and remind them to update before running.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

rm -f "$faillog"

setuprepos ||
	error "Error setting up the package repositories."

# Install the tools needed for the rest of the installation, including the
# devel headers the suckless builds need (Arch ships these inside its
# regular library packages, the RHEL family splits them out).
info "Installing build tools for compiling the suckless programs..."
dnf -y group install "Development Tools" >/dev/null 2>&1 ||
	dnf -y groupinstall "Development Tools" >/dev/null 2>&1
for x in curl ca-certificates git zsh dash chrony dnf-plugins-core \
	libX11-devel libXft-devel libXinerama-devel libXext-devel \
	libXrender-devel libxcb-devel harfbuzz-devel \
	fontconfig-devel freetype-devel; do
	info "Installing \`$x\` which is required to install and configure other programs."
	installpkg "$x"
done

info "Synchronizing system time to ensure successful and secure installation of software..."
chronyd -q 'server pool.ntp.org iburst' >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

# In virtual machines, X is often started without a logind session to grant
# device access, so give the user the video and input groups directly.
virt="$(systemd-detect-virt 2>/dev/null || grep -io hypervisor /proc/cpuinfo | head -1)"
case "$virt" in
"" | none) ;;
*) usermod -aG video,input "$name" ;;
esac

# Allow user to run sudo without password during the install; some builds
# run steps as the user that need root.
trap 'rm -f /etc/sudoers.d/bootstrap-temp' HUP INT QUIT TERM EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL
Defaults:%wheel,root runcwd=*" >/etc/sudoers.d/bootstrap-temp

# The command that does all the installing: reads the progs file and
# installs each needed program the way required.
installationloop

# The interface font has to come from upstream on this family.
nerdfontinstall ||
	info "Could not install the JetBrainsMono Nerd Font; the bar will fall back to a plain monospace font."

libertinusinstall ||
	info "Could not install the Libertinus fonts; serif and sans will fall back to DejaVu."

xwallpaperinstall ||
	info "Could not install xwallpaper; setbg will fall back to ImageMagick."

dunstinstall ||
	info "Could not install dunst; desktop notifications will not appear."

lfinstall ||
	info "Could not install the lf file manager."

browserinstall ||
	info "Could not install a browser."

# The compositor is not packaged for this family either.
picominstall || {
	whiptail --title "picom could not be installed" \
		--msgbox "picom is not packaged for this release and building it from source failed, so windows will have square corners and no transparency.\\n\\nThe build log is at /tmp/bootstrap-picom.log." 11 70
}

# Install the dotfiles in the user's home directory, but remove .git dir and
# other unnecessary files.
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -rf "/home/$name/.git/" "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Write urls for newsboat if it doesn't already exist.
[ -s "/home/$name/.config/newsboat/urls" ] ||
	echo "$rssurls" | sudo -u "$name" tee "/home/$name/.config/newsboat/urls" >/dev/null

# Install vim plugins if not already present.
[ ! -f "/home/$name/.config/nvim/autoload/plug.vim" ] && vimplugininstall

# Most important command! Get rid of the beep!
rmmod pcspkr >/dev/null 2>&1
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/abook/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# Note: the Arch script repoints /bin/sh at dash. Do not do that here - RPM
# scriptlets and much of the base system assume /bin/sh is bash, and swapping
# it can break dnf transactions.

# Enable NetworkManager so nmtui and the status bar's network module work.
systemctl enable NetworkManager >/dev/null 2>&1

# Enable tap to click on touchpads.
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

# All this below to get Librewolf installed with add-ons and non-bad settings.
info "Setting browser privacy settings and add-ons..."

browserdir="/home/$name/.librewolf"
profilesini="$browserdir/profiles.ini"

# Start librewolf headless so it generates a profile, then grab that profile.
sudo -u "$name" librewolf --headless >/dev/null 2>&1 &
sleep 1
profile="$(sed -n "/Default=.*.default-default/ s/.*=//p" "$profilesini" 2>/dev/null)"
pdir="$browserdir/$profile"

[ -d "$pdir" ] && makeuserjs

# Kill the now-unnecessary librewolf instance.
pkill -u "$name" librewolf

# Allow wheel users to sudo with password and allow several system commands
# (like `shutdown` to run without password).
echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-bootstrap-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,/usr/bin/dnf upgrade -y,/usr/bin/dnf upgrade --refresh -y" >/etc/sudoers.d/01-bootstrap-cmds-without-password
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d/02-bootstrap-visudo-editor
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" >/etc/sysctl.d/dmesg.conf

# Clean up the temporary passwordless-sudo rule.
rm -f /etc/sudoers.d/bootstrap-temp

# Report anything that did not install. Package names vary across this family,
# so this is the list to work through after a run.
if [ -s "$faillog" ]; then
	sort -u "$faillog" -o "$faillog"
	whiptail --title "Skipped: $(wc -l <"$faillog") packages (saved in $faillog)" \
		--scrolltext --textbox "$faillog" 20 70
fi

# Last message! Install complete!
finalize
