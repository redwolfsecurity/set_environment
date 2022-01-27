#!/bin/bash -x

# This is OS-family specific script to continue installing "set_environment" project.

# Source OS-specific install functions
. src/architecture/linux/continue_install.functions.sh || { error "Failed to source OS-specific install functions."; exit 1; }

# Install basic components. Note: on errror: function aborts (no need to error check)
install_set_environment_baseline || { error "Failed to install_set_environment_baseline. Details: return code was: $?"; exit 1; }

# Install additional comonents
# TODO: if any arguments passed to installer, call corresponding installer (pass control to nodejs instller portion)
# Check if parameters present
# if [ "$#" == "0" ]; then
#   # node /some/path/to/node/instller/portion
# fi

# Check installation
is_set_environment_working || { error "is_set_environment_working return bad exit code: $?"; exit 1; }

# Report sucess
set_state 'install_set_environment' 'success'
