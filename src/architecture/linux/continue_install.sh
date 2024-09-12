#!/bin/bash -x

#
# This is OS-family specific script to continue installing "set_environment" project.
#

###############################################################################
#
# continue_install() is a function to continuation OS-specific portion of
# set environment installation.
#
function continue_install {
    # Source OS-specific install functions
    source src/architecture/linux/continue_install.functions.sh || { state_set "${FUNCNAME[0]}" "terminal_error_cant_source_os_specific_install_functions"; abort; }

    # Before installer change directory multiple times let's preserve absolute path to the project's root
    # directory, so we can preserve soruces as one of the last steps after installation.
    local PROJECT_ROOT_DIR="${PWD}"
    [ ! -z "${PROJECT_ROOT_DIR}" ] || { state_set "${FUNCNAME[0]}" "terminal_error_cant_get_current_working_directory"; abort; }

    # Ensure ff_agent/bin folder exists before installing baseline components
    set_environment_ensure_ff_agent_bin_exists || { state_set "${FUNCNAME[0]}" "terminal_error_failed_to_set_environment_ensure_ff_agent_bin_exists"; abort; }

    # Install basic components.
    install_set_environment_baseline || { state_set "${FUNCNAME[0]}" "terminal_error_failed_to_install_set_environment_baseline"; abort; }

    # Project installer preserves the project source code: instead of erasing the source folder,
    # the code must be preserved under ff_agent/git/[project-owner]/set_environment/ folder.
    set_environment_preserve_source_code "${PROJECT_ROOT_DIR}" || { state_set "${FUNCNAME[0]}" "terminal_error_failed_to_set_environment_preserve_source_code"; abort; }

    # Preserved "set environment" sources provide the installer linked by set_environment_install script, which must be in the PATH.
    set_environment_ensure_install_exists || { state_set "${FUNCNAME[0]}" "terminal_error_failed_to_set_environment_ensure_install_exists"; abort; }

    # Last step: run a selfcheck
    set_environment_is_working || { state_set "${FUNCNAME[0]}" "terminal_error_selfcheck_failed"; abort; }

    state_set "${FUNCNAME[0]}" 'success'
}

# Initialize terminal
terminal_initialize || { state_set "${FUNCNAME[0]}" "terminal_error_initialize_terminal"; abort; }

# Continue installation
# Note: no need to check errors here, the continue_install() f-n itself reports
# errors (all of which are "terminal" errors) and aborts/exits.
continue_install

# Install additional components
# TODO: if any arguments passed to installer, call corresponding installer (pass control to nodejs instller portion)
# Check if parameters present
# if [ "$#" == "0" ]; then
#   # node /some/path/to/node/instller/portion
# fi
