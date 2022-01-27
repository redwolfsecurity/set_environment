#!/bin/bash -x

# This is OS-family specific script to continue installing "set_environment" project.

# Source OS-specific install functions
. src/architecture/linux/continue_install.functions.sh || { error "Failed to source OS-specific install functions."; exit 1; }

# Before installer change directory multiple times let's preserve absolute path to the project's root
# directory, so we can preserve soruces as one of the last steps after installation.
PROJECT_ROOT_DIR="${PWD}"

# Install basic components. Note: on errror: function aborts (no need to error check)
install_set_environment_baseline || { error "Failed to install_set_environment_baseline. Details: return code was: $?"; exit 1; }

# Install additional components
# TODO: if any arguments passed to installer, call corresponding installer (pass control to nodejs instller portion)
# Check if parameters present
# if [ "$#" == "0" ]; then
#   # node /some/path/to/node/instller/portion
# fi

# Preserve project source folder (only in case the project was downloaded/cloned into other than ff_agent/projects/set_environment/ folder)
pushd "${PROJECT_ROOT_DIR}" || { error "Error: failed to change directory into the project root ${PROJECT_ROOT_DIR}" >&2; exit 1; }

# Make sure ${AGENT_HOME} is set
[ -z "${AGENT_HOME}" ] && { error "Error: AGENT_HOME is not set." >&2; exit 1; }

# All projects sources got preserved in this folder
PRESERVED_PROJECTS_DIR="${AGENT_HOME}/projects"

# Current project-specific name and preserved location
PROJECT_NAME='set_environment'
PRESERVED_PROJECT_DIR="${PRESERVED_PROJECTS_DIR}/${PROJECT_NAME}"

# Check if installer running from unexpected folder
if [ "${PWD}" != "${PRESERVED_PROJECT_DIR}" ]; then
    # Current installer run from unexpected place (like some temporary folder) - need to preserve installed project source folder.
    # Check if previously preserved folder exists, then remove it.
    if [ -d "${PRESERVED_PROJECT_DIR}" ]; then
        # Remove old project source folder
        rm -fr "${PRESERVED_PROJECT_DIR}" || { error "failed_to_remove_old_project_source_folder"; exit 1; }
    fi
    # Copy newly installed source folder (to preserve it)
    cp -a "${PWD}" "${PRESERVED_PROJECTS_DIR}" || { error "failed_to_preseve_project_source_folder"; exit 1; }
fi
# Restore
popd || { error "failed_to_popd_after_preserving_source_folder"; exit 1; }

# Report sucess
set_state 'install_set_environment' 'success'
