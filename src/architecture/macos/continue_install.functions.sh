#!/bin/bash -
# This script is a part of "set_environment" installer and should not be called directry.
# It got sourced from src/architecture/linux/continue_install.sh
#

# This installs homebrew on the mac
function set_macos_environment_variables () {
	VARIABLES=(
		HOMEBREW_PREFIX="${FF_AGENT_HOME}/homebrew/"
	)

	for VARIABLE in ${VARIABLES[@]}
	do
		eval export ${VARIABLE}
	done
}

function homebrew_install () {
	echo "debug homebrew_install"
	echo "HOMEBREW_PREFIX=${HOMEBREW_PREFIX}"

	mkdir -p "${HOMEBREW_PREFIX}"

	cd "$HOMEBREW_PREFIX"
 
    	git clone https://github.com/mxcl/homebrew.git .

	PATH="${HOMEBREW_PREFIX}/bin:${PATH}"

	brew update

	# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

        # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

	# Add Homebrew to your PATH in ~/ff_agent/.ff_profile
	#echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
	#eval "$(/opt/homebrew/bin/brew shellenv)"

	# echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
	# eval "$(/opt/homebrew/bin/brew shellenv)"
}

function homebrew_uninstall (){
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
}

function brew_update () {
	brew update
}


function brew_upgrade () {
	brew upgrade
}

function brew_install () {
	PACKAGE="${1}"
	brew install "${PACKAGE}"
}

function install_desired_components () {
	# See available packages on  https://formulae.brew.sh/formula/
	PACKAGES=(
		cask		# Allow homebrew to install gui applications
		curl		# Latest curl
		docker		# Container manager
		htop		# Nice task watcher
		mas		# Install macstore apps from terminal
		powershell	# Microsoft powershell
		wget		# A nice web get program
		virtualbox	# Virtual machine tools
	)

	for PACKAGE in ${PACKAGES[@]}
	do
		homebrew_install "${PACAGE}"
	done
}

function install_build_environment () {
	PACKAGES=(
		gcc
	)

        for PACKAGE in ${PACKAGES[@]}
        do
                homebrew_install "${PACAGE}"
        done

}

function install_developer_environment () {
	PACKAGES=(
		mosh		# A relaible ssh for wifi and mobile
		visual-studio-code
		firefox
		speedtest-cli	# Check network speed from CLI
	)
}

# Invoke

set_macos_environment_variables

homebrew_install

#install_desired_components
#install_build_environment
#install_developer_environment

