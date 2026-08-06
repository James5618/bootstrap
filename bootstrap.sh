#!/bin/sh

# James's Auto-Rice Bootstrapping Script
# License: GNU GPLv3

### CONFIGURATION ###
### Point these at your own repositories when ready.

dotfilesrepo="https://github.com/james5618/dotfiles.git"
repobranch="master"
progsfile="https://raw.githubusercontent.com/james5618/bootstrap/master/progs.csv"
aurhelper="yay"

rssurls="https://www.archlinux.org/feeds/news/ \"tech\"
https://artixlinux.org/feed.php \"tech\"
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

installpkg() {
	# Install $1 from the main repos, quietly.
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

### USER DIALOGUES ###

welcomemsg() {
	whiptail --title "Welcome!" \
		--msgbox "Welcome to James's Auto-Rice Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured Linux desktop, configured the way I use my main machine.\\n\\n-James" 10 60

	whiptail --title "Important Note!" --yes-button "All ready!" \
		--no-button "Return..." \
		--yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
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

refreshkeys() {
	# Refresh the keyring, and on Artix also enable the Arch repositories.
	case "$(readlink -f /sbin/init)" in
	*systemd*)
		info "Refreshing Arch Keyring..."
		pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
		;;
	*)
		info "Enabling Arch Repositories for a more extensive software collection..."
		pacman --noconfirm --needed -S \
			artix-keyring artix-archlinux-support >/dev/null 2>&1
		grep -q "^\[extra\]" /etc/pacman.conf ||
			echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		pacman -Sy --noconfirm >/dev/null 2>&1
		pacman-key --populate archlinux >/dev/null 2>&1
		;;
	esac
}

manualinstall() {
	# Install $1 by hand; used only for the AUR helper.
	# Must run after $repodir is created and owned by $name.
	pacman -Qq "$1" >/dev/null 2>&1 && return 0
	info "Installing \"$1\" manually."
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{
			cd "$repodir/$1" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	# Install $1 from the main repos.
	info "Installing \`$1\` ($n of $total). $1 $2"
	installpkg "$1"
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
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

aurinstall() {
	# Install $1 from the AUR with $aurhelper.
	info "Installing \`$1\` ($n of $total) from the AUR. $1 $2"
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	# Install the Python package $1 with pip.
	info "Installing the Python package \`$1\` ($n of $total). $1 $2"
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

installationloop() {
	# Read progs.csv and install each program the way its tag requires.
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
	total=$(wc -l </tmp/progs.csv)
	aurinstalled=$(pacman -Qqm 2>/dev/null)
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		echo "$comment" | grep -q "^\".*\"$" &&
			comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
		"A") aurinstall "$program" "$comment" ;;
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

# This script targets Arch-based systems; hand FreeBSD off to
# bootstrap-freebsd.sh and RHEL-family systems (Fedora/CentOS/Rocky/Alma) off
# to bootstrap-rhel.sh.
#
# FreeBSD is checked with uname before /etc/os-release is read at all: that
# file is generated at boot by the os-release service, so it is not something
# to depend on, and nothing below this point would work there anyway.
if [ "$(uname -s)" = "FreeBSD" ]; then
	bsdscript="$(dirname "$0")/bootstrap-freebsd.sh"
	[ -f "$bsdscript" ] || {
		bsdscript="/tmp/bootstrap-freebsd.sh"
		fetch -qo "$bsdscript" "https://raw.githubusercontent.com/james5618/bootstrap/freebsd/bootstrap-freebsd.sh" ||
			curl -Ls "https://raw.githubusercontent.com/james5618/bootstrap/freebsd/bootstrap-freebsd.sh" >"$bsdscript" ||
			error "Could not download bootstrap-freebsd.sh."
	}
	exec sh "$bsdscript"
fi

[ -f /etc/os-release ] && . /etc/os-release
case " $ID $ID_LIKE " in
*fedora* | *rhel* | *centos*)
	rhelscript="$(dirname "$0")/bootstrap-rhel.sh"
	[ -f "$rhelscript" ] || {
		rhelscript="/tmp/bootstrap-rhel.sh"
		curl -Ls "https://raw.githubusercontent.com/james5618/bootstrap/rhel/bootstrap-rhel.sh" >"$rhelscript" ||
			error "Could not download bootstrap-rhel.sh."
	}
	exec sh "$rhelscript"
	;;
esac

# Check that the user is root on an Arch distro; install whiptail for dialogs.
pacman --noconfirm --needed -Sy libnewt ||
	error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome the user and remind them to update before running.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys ||
	error "Error automatically refreshing Arch keyring. Consider doing so manually."

# Install the tools needed for the rest of the installation.
for x in curl ca-certificates base-devel git ntp zsh dash; do
	info "Installing \`$x\` which is required to install and configure other programs."
	installpkg "$x"
done

info "Synchronizing system time to ensure successful and secure installation of software..."
ntpd -q -g >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

# In virtual machines, X is often started without a logind session to grant
# device access, so give the user the video and input groups directly.
virt="$(systemd-detect-virt 2>/dev/null || grep -io hypervisor /proc/cpuinfo | head -1)"
case "$virt" in
"" | none) ;;
*) usermod -aG video,input "$name" ;;
esac

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
trap 'rm -f /etc/sudoers.d/bootstrap-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL
Defaults:%wheel,root runcwd=*" >/etc/sudoers.d/bootstrap-temp

# Make pacman colorful, enable concurrent downloads and add eye candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

manualinstall $aurhelper || error "Failed to install AUR helper."

# Make sure .*-git AUR packages get updated automatically.
$aurhelper -Y --save --devel

# The command that does all the installing: reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only
# after the user has been created and has privileges to run sudo without a
# password and all build dependencies are installed.
installationloop

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
rmmod pcspkr
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/abook/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# Make dash the default #!/bin/sh symlink.
ln -sfT /bin/dash /bin/sh >/dev/null 2>&1

# dbus UUID must be generated for Artix runit.
[ -e /var/lib/dbus/machine-id ] || dbus-uuidgen >/var/lib/dbus/machine-id

# Enable NetworkManager so nmtui and the status bar's network module work.
case "$(readlink -f /sbin/init)" in
*systemd*) systemctl enable NetworkManager >/dev/null 2>&1 ;;
esac

# Use system notifications for Brave on Artix.
# Only do it when systemd is not present.
[ "$(readlink -f /sbin/init)" != "/usr/lib/systemd/systemd" ] && echo "export \$(dbus-launch)" >/etc/profile.d/dbus.sh

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
profile="$(sed -n "/Default=.*.default-default/ s/.*=//p" "$profilesini")"
pdir="$browserdir/$profile"

[ -d "$pdir" ] && makeuserjs

# Kill the now-unnecessary librewolf instance.
pkill -u "$name" librewolf

# Allow wheel users to sudo with password and allow several system commands
# (like `shutdown` to run without password).
echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-bootstrap-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/pacman -S -y --config /etc/pacman.conf --,/usr/bin/pacman -S -y -u --config /etc/pacman.conf --" >/etc/sudoers.d/01-bootstrap-cmds-without-password
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d/02-bootstrap-visudo-editor
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" >/etc/sysctl.d/dmesg.conf

# Clean up the temporary passwordless-sudo rule.
rm -f /etc/sudoers.d/bootstrap-temp

# Last message! Install complete!
finalize
