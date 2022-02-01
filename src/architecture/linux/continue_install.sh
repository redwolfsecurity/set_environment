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

    # Install basic components. Note: on errror: function aborts (no need to error check)
    install_set_environment_baseline || { error "Failed to install_set_environment_baseline. Details: return code was: $?"; exit 1; }

    # Install additional components
    # TODO: if any arguments passed to installer, call corresponding installer (pass control to nodejs instller portion)
    # Check if parameters present
    # if [ "$#" == "0" ]; then
    #   # node /some/path/to/node/instller/portion
    # fi

    # As a preparation to preserve project source files (used during this installation), let's change directory to the project root directory.
    pushd "${PROJECT_ROOT_DIR}" || { error "Error: failed to change directory into the project root ${PROJECT_ROOT_DIR}" >&2; exit 1; }

    # Make sure ${FF_AGENT_HOME} is set
    [ -z "${FF_AGENT_HOME}" ] && { error "Error: FF_AGENT_HOME is not set." >&2; exit 1; }

    # Extract project owner
    local URL=$( git remote show origin | grep 'Fetch URL:' | awk -F'Fetch URL: ' '{print $2}' )
    [ -z "${URL}" ] && { error "Error: failed to extract project repository URL." >&2; exit 1; }
    local OWNER=$( parse_github_repository_url "${URL}" "OWNER" )
    [ -z "${OWNER}" ] && { error "Error: failed to extract project owner from URL='${URL}'." >&2; exit 1; }

    # All projects sources got preserved in this folder
    local PRESERVED_PROJECTS_DIR="${FF_AGENT_HOME}/git"

    # Current project-specific name and preserved location
    local PROJECT_NAME='set_environment'
    local PRESERVED_PROJECT_DIR="${PRESERVED_PROJECTS_DIR}/${OWNER}/${PROJECT_NAME}"

    # Check if installer running from unexpected folder
    if [ "${PWD}" != "${PRESERVED_PROJECT_DIR}" ]; then
        # Current installer run from unexpected place (like some temporary folder) - need to preserve installed project source folder.
        # Check if previously preserved folder exists, then remove it.
        if [ -d "${PRESERVED_PROJECT_DIR}" ]; then
            # Remove old project source folder
            rm -fr "${PRESERVED_PROJECT_DIR}" || { error "failed_to_remove_old_project_source_folder"; exit 1; }
        fi

        # Make sure target project "owner" folder exists before trying to copy (otherwise copy result will 
        # be incorrect - all the content of the current root project will be copied into "projects/"
        # folder without project-specific "owner" containing folder).
        if [ ! -d "${PRESERVED_PROJECTS_DIR}/${OWNER}" ]; then
            mkdir -p "${PRESERVED_PROJECTS_DIR}/${OWNER}" || { error "failed_to_create_projects_owner_folder"; exit 1; }
        fi

        # Copy newly installed source folder (to preserve it)
        cp -a "${PWD}" "${PRESERVED_PROJECTS_DIR}/${OWNER}" || { error "failed_to_preseve_project_source_folder"; exit 1; }
    fi
    # Restore
    popd || { error "failed_to_popd_after_preserving_source_folder"; exit 1; }

    # Report sucess
    set_state 'install_set_environment' 'success'
}

continue_install
