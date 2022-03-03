#! /usr/bin/env bash
#
# Author: Joshua Gilman <joshuagilman@gmail.com>
#
#/ Usage: setup.sh
#/
#/ A simple installation script for configuring my personal development
#/ environment on an M1 based Apple MacBook.
#/
# shellcheck disable=SC2155

set -o errexit  # abort on nonzero exitstatus
set -o nounset  # abort on unbound variable
set -o pipefail # don't hide errors within pipes

readonly yellow='\e[0;33m'
readonly green='\e[0;32m'
readonly red='\e[0;31m'
readonly reset='\e[0m'

readonly dotfiles='https://github.com/jmgilman/dotfiles'

# Nix
readonly nixVer='2.6.1'
readonly nixReleaseBase='https://releases.nixos.org'

# Brew
readonly brewRepo='https://raw.githubusercontent.com/Homebrew/install'
readonly brewCommitSha='e8114640740938c20cc41ffdbf07816b428afc49'
readonly brewChecksum='98a0040bd3dc4b283780a010ad670f6441d5da9f32b2cb83d28af6ad484a2c72'

# Usage: log MESSAGE
#
# Prints all arguments on the standard output stream
log() {
	printf "${yellow}>> %s${reset}\n" "${*}"
}

# Usage: success MESSAGE
#
# Prints all arguments on the standard output stream
success() {
	printf "${green} %s${reset}}\n" "${*}"
}

# Usage: error MESSAGE
#
# Prints all arguments on the standard error stream
error() {
	printf "${red}!!! %s${reset}\n" "${*}" 1>&2
}

# Usage: die MESSAGE
# Prints the specified error message and exits with an error status
die() {
	error "${*}"
	exit 1
}

# Usage: yesno MESSAGE
#
# Asks the user to confirm via y/n syntax. Exits if answer is no.
yesno() {
	read -p "${*} [y/n] " -n 2 -r
	printf "\n"
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 1
	fi
}

# Usage: tryInstall NAME EXECUTABLE
#
# Asks the user permission to install NAME and then runs EXECUTABLE
tryInstall() {
	local name=${1}
	local executable=${2}

	log "It appears that ${name} is not installed and is required to continue."
	yesno "Would you like to install it?"

	log "Installing ${name}..."
	${executable}
	success "${name} was successfully installed"
}

# Usage: checkDep NAME CONDITION EXECUTABE
#
# Checks CONDITION, if not true asks user to run EXECUTABLE
checkDep() {
	local name=${1}
	local condition=${2}
	local executable=${3}

	if ! ${condition} -p &>/dev/null; then
		tryInstall "${name}" "${executable}"
	else
		log "${name} detected, skipping install"
	fi
}

# Usage: installXcode
#
# Downloads and installs the xcode command line tools
# Source: https://github.com/Homebrew/install/blob/master/install.sh#L846
chomp() {
	printf "%s" "${1/"$'\n'"/}"
}
installXcode() {
	log "Searching online for the Command Line Tools"

	# This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
	clt_placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
	/usr/bin/sudo /usr/bin/touch "${clt_placeholder}"

	clt_label_command="/usr/sbin/softwareupdate -l |
                        grep -B 1 -E 'Command Line Tools' |
                        awk -F'*' '/^ *\\*/ {print \$2}' |
                        sed -e 's/^ *Label: //' -e 's/^ *//' |
                        sort -V |
                        tail -n1"
	clt_label="$(chomp "$(/bin/bash -c "${clt_label_command}")")"

	if [[ -n "${clt_label}" ]]; then
		log "Installing ${clt_label}"
		/usr/bin/sudo "/usr/sbin/softwareupdate" "-i" "${clt_label}"
		/usr/bin/sudo "/usr/bin/xcode-select" "--switch" "/Library/Developer/CommandLineTools"
	fi

	/usr/bin/sudo "/bin/rm" "-f" "${clt_placeholder}"
}

# Usage: installNix
#
# Downloads and executes the nix installer script
installNix() {
	local nixURL="${nixReleaseBase}/nix/nix-${nixVer}/install"
	local checksumURL="${nixReleaseBase}/nix/nix-${nixVer}/install.sha256"
	local sha="$(curl "${checksumURL}")"

	log "Downloading install script from ${nixURL}..."
	curl "${nixURL}" -o "${tmpDir}/nix.sh" &>/dev/null

	log "Validating checksum..."
	if ! echo "${sha}  ${tmpDir}/nix.sh" | shasum -a 256 -c; then
		die "Checksum validation failed; cannot continue"
	fi

	log "Running nix installer..."
	bash "${tmpDir}/nix.sh"
	success "Nix installed successfully"

	# nix shell requires nix-command which is experimental
	# we also need to add flakes so we can run our development flakes
	log 'Adding experimental features: nix-command flakes'
	mkdir -p ~/.config/nix
	echo 'experimental-features = nix-command flakes' >>~/.config/nix/nix.conf

	log 'Configuring environment...'
	# shellcheck disable=SC1091
	source /etc/bashrc
}

# Usage: installNixDarwin
#
# Builds the nix-darwin installer and then executes it
installNixDarwin() {
	# nix-darwin complains if this file exists, so we back it up first
	/usr/bin/sudo mv /etc/nix/nix.conf /etc/nix/nix.conf.backup

	log 'Building nix-darwin installer...'
	cd "${tmpDir}" && nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer

	log 'Running nix-darwin installer...'
	cd "${tmpDir}" && "./result/bin/darwin-installer"

	# nix-darwin manages nix itself, so we can remove the global version now
	log "Removing redundant nix version..."
	/usr/bin/sudo -i nix-env -e nix

	log "Configuring environment..."
	# shellcheck disable=SC1091
	source /etc/bashrc

	# home-manager is required by the current configuration
	log "Adding home-manager channel..."
	nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
	nix-channel --update
}

# Usage installBrew
#
# Downloads and executes the brew installer script
installBrew() {
	local brewURL="${brewRepo}/${brewCommitSha}/install.sh"

	log "Downloading install script from ${brewURL}..."
	curl "${brewURL}" -o "${tmpDir}/brew.sh" &>/dev/null

	log "Validating checksum..."
	if ! echo "${brewChecksum}  ${tmpDir}/brew.sh" | shasum -a 256 -c; then
		die "Checksum validation failed; cannot continue"
	fi

	log "Running brew installer..."
	bash "${tmpDir}/brew.sh"

	log "Configuring environment..."
	# shellcheck disable=SC2016
	echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>"$HOME/.bash_profile"
	eval "$(/opt/homebrew/bin/brew shellenv)"
}

# Usage bwUnlock
#
# Attempts to login or unlock Bitwarden using the CLI
bwUnlock() {
	# Unlock -> login -> check if already unlocked -> die because unreachable
	if bw status | grep "locked" &>/dev/null; then
		export BW_SESSION="$(bw unlock --raw)"
	elif bw status | grep "unauthenticated" &>/dev/null; then
		export BW_SESSION="$(bw login --raw)"
	elif [[ -z "${BW_SESSION}" ]]; then
		die "Unknown bitwarden status"
	fi
}

# need a scratch space for downloading files
tmpDir="$(mktemp -d -t dev-setup-XXXXXXXXXX)"
if [[ ! -d "${tmpDir}" ]]; then
	die "Failed creating a temporary directory; cannot continue"
fi

# xcode is needed for building most software from source
checkDep 'xcode' '/usr/bin/xcode-select' 'installXcode'

# rosetta is needed for running x86_64 applications
checkDep 'rosetta' '/usr/bin/pgrep oahd' 'softwareupdate --install-rosetta'

# nix is needed to configure the entire system
checkDep 'nix' 'command -v nix' 'installNix'

# a better check to validate nix is actually installed correctly
if ! nix doctor &>/dev/null; then
	error 'nix doctor reports an unhealthy nix installation'
	tryInstall 'nix' 'installNix'

	log "Please run this installer script again to continue"
	exit 1
else
	log "nix is healthy, continuing"
fi

# nix-darwin is what actually does the configuration
checkDep 'nix-darwin' 'command -v darwin-rebuild' 'installNixDarwin'

# bitwarden-cli is needed to pull down secrets with chezmoi
checkDep 'bitwarden-cli' 'command -v bw' 'nix-env -i bitwarden-cli'

# brew is needed for installing GUI applications (casks)
checkDep 'brew' 'command -v brew' 'installBrew'

# needs to be unlocked before calling chezmoi
log "Logging into bitwarden..."
bwUnlock

if [[ ! -d "$HOME/.local/share/chezmoi" ]]; then
	log "Fetching dotfiles..."
	nix shell nixpkgs#chezmoi -c chezmoi init "${dotfiles}"
fi

# implicitely calls `nix-darwin rebuild`` and `brew bundle install``
log "Applying dotfiles..."
nix shell nixpkgs#chezmoi -c chezmoi apply

# creates the dotfile structure the first time it's run
if [[ ! -d "$HOME/.gnupg" ]]; then
	log "Initializing GPG..."
	gpg-agent --daemon
fi

success 'Done!'
