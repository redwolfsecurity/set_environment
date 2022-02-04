#!/bin/bash -x

# This is OS-family specific script to continue installing "set_environment" project.

# Source OS-specific install functions
. src/architecture/linux/continue_install.functions.sh || { error "Failed to source OS-specific install functions."; exit 1; }

###############################################################################
#
# continue_install() is a function to continuation OS-specific portion of set environment installation.
#
function continue_install {
    # Before installer change directory multiple times let's preserve absolute path to the project's root
    # directory, so we can preserve soruces as one of the last steps after installation.
    local PROJECT_ROOT_DIR="${PWD}"

    # Install basic components.
    install_set_environment_baseline || { error "Failed to install_set_environment_baseline. Details: return code was: $?"; exit 1; }

    # Project installer preserves the project source code: instead of erasing the source folder,
    # the code must be preserved under ff_agent/git/[project-owner]/set_environment/ folder.
    preserve_sources "${PROJECT_ROOT_DIR}" || { error "Failed to preserve_sources. Details: return code was: $?"; exit 1; }

    # Preserved "set environment" sources provide the installer linked by set_environment_install script, which must be in the PATH.
    ensure_ff_agent_bin_exists || { error "Failed to ensure_ff_agent_bin_exists. Details: return code was: $?"; exit 1; }
    ensure_set_environment_install_exists || { error "Failed to ensure_set_environment_install_exists. Details: return code was: $?"; exit 1; }
}

continue_install

# Install additional components
# TODO: if any arguments passed to installer, call corresponding installer (pass control to nodejs instller portion)
# Check if parameters present
# if [ "$#" == "0" ]; then
#   # node /some/path/to/node/instller/portion
# fi

# Report sucess
set_state 'install_set_environment' 'success'
