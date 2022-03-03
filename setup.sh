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
	read -p "${*} [y/n] " -r
	printf "\n"
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 1
	fi
}

# Usage: isRequired NAME EXECUTABLE
#
# Asks the user permission to install NAME and then runs EXECUTABLE
isRequired() {
	local name=${1}
	local executable=${2}

	log "It appears that ${name} is not installed and is required to continue."
	yesno "Would you like to install it?"

	log "Installing ${name}..."
	${executable}
	success "${name} was successfully installed"
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
	"{$tmpDir}"/result/bin/darwin-installer

	# nix-darwin manages nix itself, so we can remove the global version now
	log "Removing redundant nix version..."
	/usr/bin/sudo -i nix-env -e nix

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
	if bw status | grep "locked"; then
		export BW_SESSION="$(bw unlock --raw)"
	elif bw status | grep "unauthenticated"; then
		export BW_SESSION="$(bw login --raw)"
	elif [[ -z "${BW_SESSION}" ]]; then
		die "Unknown bitwarden status"
	fi
}

# need a scratch space for downloading files
tmpDir=$(mktemp -d -t dev-setup-XXXXXXXXXX)
if [[ ! -d "$tmpDir" ]]; then
	die "Failed creating a temporary directory; cannot continue"
fi

# xcode is needed for building most software from source
if ! /usr/bin/xcode-select -p &>/dev/null; then
	isRequired 'xcode' 'installXcode'
else
	log "xcode detected, skipping install"
fi

# rosetta is needed for running x86_64 applications
if ! /usr/bin/pgrep oahd &>/dev/null; then
	isRequired 'rosetta' 'softwareupdate --install-rosetta'
else
	log "rosetta detected, skipping install"
fi

# a rudimentary check to see if the nix binary is available
if ! command -v nix &>/dev/null; then
	isRequired 'nix' 'installNix'
else
	log "nix detected, continuing"
fi

# a more full-featured check to validate it's actually installed correctly
if ! nix doctor &>/dev/null; then
	error 'nix doctor reports an unhealthy nix installation'
	isRequired 'nix' 'installNix'

	log "Please run this installer script again to continue"
	exit 1
else
	log "nix is healthy, continuing"
fi

# installing nix-darwin adds the darwin-rebuild command into $PATH
if ! command -v darwin-rebuild &>/dev/null; then
	isRequired 'nix-darwin' 'installNixDarwin'
else
	log "nix-darwin detected, skipping install"
fi

if ! command -v bw &>/dev/null; then
	isRequired 'bitwarden-cli' 'nix-env -i bitwarden-cli'
else
	log "bitwarden-cli detected, skipping install"
fi

if ! command -v brew &>/dev/null; then
	isRequired 'brew' 'installBrew'
else
	log "brew detected, skipping install"
fi

log "Logging into bitwarden..."
bwUnlock

log "Fetching dotfiles..."
nix shell nixpkgs#chezmoi -c chezmoi init "${dotfiles}"

log "Applying dotfiles..."
nix shell nixpkgs#chezmoi -c chezmoi apply

log "Initializing GPG..."
gpg-agent --daemon

success 'Done!'
