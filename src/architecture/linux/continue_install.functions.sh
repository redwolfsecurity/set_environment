#!/bin/bash -
# This script is a part of "set_environment" installer and should not be called directry.
# It got sourced from src/architecture/linux/continue_install.sh
#

# Make installation output more verbose so we can audit all the steps
set -x

###############################################################################
#
# Function makes sure "${FF_AGENT_HOME}/bin" folder is created.
#
function ensure_ff_agent_bin_exists {

  set_state "${FUNCNAME[0]}" 'started'

  # Define required variables
  local REQUIRED_VARIABLES=(
    FF_AGENT_HOME
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done

  # Define target directory
  TARGET_DIR="${FF_AGENT_HOME}/bin"

  # Check if target directory exists
  [ -d "${TARGET_DIR}" ] || {
    # Does not exist. Create new.
    mkdir "${TARGET_DIR}" || { set_state "${FUNCNAME[0]}" 'failed_to_create_directory'; return 1; }
  }

  set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Function makes sure symlink exists (or create new one if missing).
#    ${FF_AGENT_HOME}/bin/set_environment_install -> ${FF_AGENT_HOME}/git/redwolfsecurity/set_environment/install
#
function ensure_set_environment_install_exists {

  set_state "${FUNCNAME[0]}" 'started'

  # Define required variables
  local REQUIRED_VARIABLES=(
    FF_AGENT_HOME
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done

  # Define symlink
  SYMLINK="${FF_AGENT_HOME}/bin/set_environment_install"

  # Define target file (which new symlink must point to)
  TARGET_FILE="${FF_AGENT_HOME}/git/redwolfsecurity/set_environment/install"
  
  # Check symlink exists. Note: -L returns true if the "file" exists and is a symbolic link (the linked file may or may not exist).
  [ -L "${SYMLINK}" ] || { 
      # SYMLINK is missing. Try to create new symlink.
      ln -s "${TARGET_FILE}" "${SYMLINK}" || { set_state "${FUNCNAME[0]}" 'failed_to_create_symlink'; return 1; }
  }

  # Check the target file is presend (symlink is not broken)
  [ -f "${TARGET_FILE}" ] || { set_state "${FUNCNAME[0]}" 'error_target_file_missing'; return 1; }

  # Check the target file is executable. Note: extra "-f" check added here since "-x" can say "yes, executable", but target points to directory.
  [[ -f "${TARGET_FILE}" && -x "${TARGET_FILE}" ]] || { set_state "${FUNCNAME[0]}" 'error_target_file_not_executable'; return 1; }

  set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Function installs docker. It takes 1 argement "minimum version", if not provided,
# then by default version 19 will be used.
#
# Supports Ubuntu 16.04, 18.04, 20.04
#
# Require environment variables set:
#   - FF_AGENT_USERNAME
#
function install_docker {

  set_state "${FUNCNAME[0]}" 'started'

  # Define required variables
  local REQUIRED_VARIABLES=(
    FF_AGENT_USERNAME
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done

  # Take MINIMUM_VERSION argument, if empty, then set default value
  MINIMUM_VERSION="${1}"
  if [ -z "${MINIMUM_VERSION}" ]; then
      MINIMUM_VERSION=19
  fi

  # Check if docker is installed and has version >= minimally required
  ACTUAL_VERSION="$( get_installed_docker_version )"
  if [ ! -z "${ACTUAL_VERSION}" ] && [ "${ACTUAL_VERSION}" -ge "${MINIMUM_VERSION}" ]; then
      set_state "${FUNCNAME[0]}" "no_action_already_installed"
      return 0
  fi

  # OK We install since we don't have the minimum version, or docker is not installed

  # Get ID, RELEASE and DISTRO and verify the values are actually set
  LSB_ID=$( get_lsb_id ) || { set_state "${FUNCNAME[0]}" "failed_to_get_lsb_id"; return 1; } # Ubuntu
  [ "${LSB_ID}" == "" ] && { set_state "${FUNCNAME[0]}" "failed_to_get_lsb_id"; return 1; } # Ubuntu

  RELEASE=$( get_lsb_release ) || { set_state "${FUNCNAME[0]}" "failed_to_get_lsb_release"; return 1; }  # 18.04, 20.04, ...
  [ "${RELEASE}" == "" ] && { set_state "${FUNCNAME[0]}" "failed_to_get_lsb_release"; return 1; }

  DISTRO=$( get_lsb_codename ) || { set_state "${FUNCNAME[0]}" "failed_to_get_lsb_codename"; return 1; }  # bionic, focal, ...
  [ "${DISTRO}" == "" ] && { set_state "${FUNCNAME[0]}" "failed_to_get_lsb_codename"; return 1; } 

  ARCHITECTURE=$( get_hardware_architecture ) || { set_state "${FUNCNAME[0]}" "error_getting_hardware_architecture"; return 1; }

  # Only Ubuntu for now
  if [ "${LSB_ID}" != "Ubuntu" ]; then
      set_state "${FUNCNAME[0]}" "error_docker_install_unsupported_operating_system"
      return 1
  fi

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  [ "${?}" != "0" ] && { set_state "${FUNCNAME[0]}" "failed_to_add_gpg_key"; return 1; }

  sudo add-apt-repository "deb [arch=${ARCHITECTURE}] https://download.docker.com/linux/ubuntu ${DISTRO} stable"
  [ "${?}" != "0" ] && { set_state "${FUNCNAME[0]}" "failed_to_add_repository"; return 1; }

  apt_update

  apt_install docker-ce || { set_state "${FUNCNAME[0]}" "failed_to_install_docker_ce"; return 1; }
  apt_install docker-compose || { set_state "${FUNCNAME[0]}" "failed_to_install_docker_compose"; return 1; }
  # containerd is available as a daemon for Linux and Windows. It manages the complete container lifecycle of its host system, from image transfer and storage to container execution and supervision to low-level storage to network attachments and beyond.
  apt_install containerd.io || { set_state "${FUNCNAME[0]}" "failed_to_install_containerd_io"; return 1; }

  # Add ourselves as a user to be able to run docker
  GROUP="docker"
  # Check the 'docker' group exists.
  if ! check_group_exists "${GROUP}"; then
    set_state "${FUNCNAME[0]}" "error_group_docker_does_not_exist"
    return 1
  fi

  # We might not have sudo, so we should request command to be run.
  # Check if user is in this group. If not, add them
  if [ ! is_user_in_group "${FF_AGENT_USERNAME}" "${GROUP}" ]; then
    # Not in group
    sudo usermod -aG "${GROUP}" "${FF_AGENT_USERNAME}"
    if [ "${?}" != "0" ]; then set_state "${FUNCNAME[0]}" "failed_to_modify_docker_user_group"; return 1; fi
    # Now check that we actually are in the group. This will work in current shell because it reads the groups file directly
    [ ! is_user_in_group "${FF_AGENT_USERNAME}" "${GROUP}" ] || { set_state "${FUNCNAME[0]}" "failed_postcondition_user_in_group"; return 1; }
  fi

  # Postcondition checks
  # Verify docker is properly set up
  # Note we are running via sudo, and if we added user to the ${GROUP} then it won't be applied in this shell.
  set_secret docker_release "$( sudo --user=${FF_AGENT_USERNAME} docker --version )" || { set_state "${FUNCNAME[0]}" "failed_to_run_docker_to_get_release"; return 1; }
  set_secret docker_compose_release "$( sudo --user=${FF_AGENT_USERNAME} docker-compose --version )" || { set_state "${FUNCNAME[0]}" "failed_to_run_docker_compose_to_get_release"; return 1; }

  # Check if installed docker version is less than minimally required
  if [ "$( get_installed_docker_version )" -lt "${MINIMUM_VERSION}" ]; then
    set_state "${FUNCNAME[0]}" "failed_to_install_did_not_pass_version_check"
    return 1
  fi

  set_state "${FUNCNAME[0]}" 'success'
}


###############################################################################
#
# Function installs "go" by certain version (see below) if it is not already installed.
#
# In case of successful install (or already at expected version) script return success code 0.
# In case of any errors script prints error to standard error stream and exit with code 1.
#
function install_go {
  set_state "${FUNCNAME[0]}" 'started'

  # Define required variables
  local REQUIRED_VARIABLES=(
    FF_CONTENT_URL
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done

  # The installation archives (size ~123MB) are located in the CDN by URL:
  # https://cdn.redwolfsecurity.com/ff/ff_agent/hotpatch/hotpatch_files/go1.16.2.linux-amd64.tar.gz
  # https://cdn.redwolfsecurity.com/ff/ff_agent/hotpatch/hotpatch_files/go1.17.1.linux-amd64.tar.gz
  
  #EXPECTED_VERSION="1.16.2"
  EXPECTED_VERSION="1.17.1"  # Updated go version on 09-Sep-2021
  EXPECTED_COMMAND="go"

  # ------------------------ don't edit below this line -------------------------

  # Define command to get version
  GET_VERSION_COMMAND="go version"

  # Define expected output of version command
  GET_VERSION_EXPECTED_OUTPUT="go version go${EXPECTED_VERSION} linux/amd64"

  # Check if go is installed and is in the PATH
  IS_INSTALLED="$( command_exists go )"

  # Check if go is already installed and has expected vesrion
  if [ "${IS_INSTALLED}" != "" ]; then
      # Yes, is installed. Check if installed 'go' version matches expected one.
      GET_VERSION_OUTPUT="$( ${GET_VERSION_COMMAND} )"
      
      # Compare to expected version
      if [ "${GET_VERSION_OUTPUT}" == "${GET_VERSION_EXPECTED_OUTPUT}" ]; then
        # Match. Version is up to date, nothing to do.
        return 0
      fi
  fi

  # Create temporary folder
  TEMP_DIR="$( mktemp --directory )"

  # Check temporary folder created and we can write to it
  TEMP_TEST_FILE="${TEMP_DIR}/test_file"
  touch "${TEMP_TEST_FILE}"
  TEMP_TEST_FILE_STATUS_CODE=$?
  if [ ${TEMP_TEST_FILE_STATUS_CODE} -ne 0 ]; then
      error "Failed to create test file in the temporary folder: '${TEMP_TEST_FILE}'"
      return 1
  fi

  # Define tarball name by given expected version
  TARBALL_FILENAME="go${EXPECTED_VERSION}.linux-amd64.tar.gz"

  # Download tarball (by curl with retries)
  URL="${FF_CONTENT_URL}/ff/ff_agent/hotpatch/hotpatch_files/${TARBALL_FILENAME}"
  curl \
        -sL \
        --retry 5 \
        --retry-delay 1 \
        --retry-max-time 60 \
        --max-time 55 \
        --connect-timeout 12 \
        -o "${TEMP_DIR}/${TARBALL_FILENAME}" \
        "${URL}"

  # Check if download succeed
  DOWNLOAD_STATUS_CODE=$?
  if [ ${DOWNLOAD_STATUS_CODE} -ne 0 ]; then
      echo "error: failed to download tarball by URL: '${URL}'" >&2
      exit 1
  fi

  # Install 'go'

  # Remove old 'go'
  sudo rm -fr /usr/local/go
  # To cleanup old "bad installations" of "go" let's do 3 things:
  # delete 2 symlinks and then delete few old directories before installing new 'go':
  #    1) rm -f  /usr/bin/go
  #    2) rm -f  /usr/lib/go
  #    3) rm -fr /usr/lib/go-*
  sudo rm -f  /usr/bin/go
  sudo rm -f  /usr/lib/go
  sudo rm -fr /usr/lib/go-*

  # Unzip downloaded archive
  sudo tar -C /usr/local -xzf "${TEMP_DIR}/${TARBALL_FILENAME}"
  if [ $? -ne 0 ]; then
      error "Failed to install tarball by command: sudo tar -C /usr/local -xzf ${TARBALL_FILENAME}  Current working directory: '$( pwd )'"
      return 1
  fi

  # Remove temporary folder
  rm -fr "${TEMP_DIR}" || { error "Failed to remove temporary folder: '${TEMP_DIR}'"; return 1; }

  # Inject path to 'go' into /etc/profile (for all users)
  # Check if profile already contain expected path
  EXPECTED_PROFILE_LINE='export PATH=$PATH:/usr/local/go/bin' # note: we don't want to expand variables in this string, thus single quites used.
  cat /etc/profile | grep --silent "${EXPECTED_PROFILE_LINE}"
  if [ ! $? -eq 0 ]; then
      # Expected profile line not found
      echo "" | sudo tee -a /etc/profile
      echo "# The path to 'go' inserted by $( pwd )/$( basename $0 ) on $( date --utc ) for 'go' version: 'go${EXPECTED_VERSION}'" | sudo tee -a /etc/profile
      echo "${EXPECTED_PROFILE_LINE}" | sudo tee -a /etc/profile
  fi

  # Also inject path to 'go' into current PATH (if missing in PATH)
  # do the export, so we don't have to relogin in order to call "go version"
  echo ${PATH} | grep -q /usr/local/go/bin
  if [ $? -ne 0 ]; then
    # Path to 'go' is missing from PATH environment variable. Inject it:
    export PATH=$PATH:/usr/local/go/bin
    # TODO: this also must be injected into ff_agent/profile
  fi

  # Check by running "go version"
  GET_VERSION_OUTPUT="$( $GET_VERSION_COMMAND )"
      
  # Compare to expected version
  if [ "${GET_VERSION_OUTPUT}" != "${GET_VERSION_EXPECTED_OUTPUT}" ]; then
      # Mismatch.
      error "Failed to get expected version output after installation. Expected output was '${GET_VERSION_EXPECTED_OUTPUT}', but instead we got '${GET_VERSION_OUTPUT}'."
      return 1
  fi
  
  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
# Continuation of the "set_environment". Installing baseline components.
# On errror: function aborts (so no need to errorcheck on caller side)
#
function install_set_environment_baseline {
  set_state "${FUNCNAME[0]}" 'started'

  # Discover environment (choose user, make sure it's home folder exists, check FF_CONTENT_URL is set etc.)
  discover_environment || { set_state "${FUNCNAME[0]}" "terminal_error_failed_to_discover_environment"; abort; }

  # Analyzes currently selected user and might call "background_install()" to re-run the installer under a different user
  # Note: it have a dependency: variable FF_AGENT_USERNAME - must be set (by calling choose_ff_agent_home)
  if [ "$( check_if_need_background_install )" == "true" ]; then
    background_install "${FF_AGENT_USERNAME}"
    return 0
    # Note: we can not "exit 0" here since installer might be sourced by "root"
  fi

  # Put logs in best location
  setup_logging || { set_state "${FUNCNAME[0]}" "terminal_error_failed_to_setup_logging"; abort; }

  # Install set of basic packages, bash functions, .bashrc and .profile files
  assert_clean_exit assert_basic_components || { set_state "${FUNCNAME[0]}" "terminal_error_failed_to_assert_basic_components"; abort; }

  set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Install set of basic packages (most installed by "apt", but some installed by
# different means (example: docker, n, npm, nodejs)), bash functions, .bashrc and .profile files.
#
function assert_basic_components {
  set_state "${FUNCNAME[0]}" 'started'

  # Install basic packages before installing anything else. This will install "curl", thus "set_state" will be able to POST JSON.
  assert_clean_exit apt_install_basic_packages
  
  # Install NTP and make sure timesyncd is disabled (not working in parallel)
  # assert_clean_exit replace_timesyncd_with_ntpd

  # Before installing locally (into local ff_agent/) packages, like "n / npm / nodejs" we need to put in place ff_agent .bashrc and .profile
  # TODO: DO WE REALLY DEPEND ON THIS BEFORE INSTALLING n/npm/nodejs??
  assert_clean_exit install_ff_agent_bashrc
  
  # Install docker (not using "apt")
  #assert_clean_exit install_docker

  # Install nodejs suite and all its fixings (not using "apt")
  assert_clean_exit install_nodejs_suite

  # Note: assert_clean_exit aborts on error
  assert_clean_exit install_ff_agent

  # Install pm2
  assert_clean_exit pm2_ensure

  # Note: assert_clean_exit aborts on error
  assert_clean_exit install_ff_agent

  set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Assert core credentials (npmrc, docker, ...)
#
function assert_core_credentials {
    set_state "${FUNCNAME[0]}" 'started'
    # TODO - we should be part of docker group. That's about it I think.
    set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Create .npmrc credentials
#
function create_npmrc_credentials {
  set_state "${FUNCNAME[0]}" 'started'

  # Define required variables
  local REQUIRED_VARIABLES=(
    HOME
    USER
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done

  # TODO: Get these credentials from secret manager
  # TODO: .npmrc can substitue environment variables -- that's at least a touch more secure if we run npm from our FF framework

  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
# Assert .npmrc credentials
#
function assert_npmrc_credentials {
  set_state "${FUNCNAME[0]}" 'started'

  # TODO: Make a more rigorous check -- can we actually use these .npmrc credentials? They might be wrong or out of date!

  NPMRC_FILE="${HOME}/.npmrc"
  if [ ! -e "${NPMRC_FILE}" ]; then
      set_state "${FUNCNAME[0]}" 'fatal_error_asserting_npmrc_credentials'; return 1;
      error "assert_npmrc_credentials can't find ${NPMRC_FILE} which is required."
      abort
  fi

  if file_contains_pattern "${NPMRC_FILE}" "development.acme.com"
  then
      :
  else
      set_state "${FUNCNAME[0]}" 'fatal_error_asserting_npmrc_credentials'
      error "assert_npmrc_credentials can't find credentials in ${NPMRC_FILE}"
      abort
  fi

  set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Install basic packages
#
#
function apt_install_basic_packages {

  set_state "${FUNCNAME[0]}" 'started'

  # Update apt index and installed components, before installing additional packages.
  assert_clean_exit apt_update
  assert_clean_exit apt_upgrade

  # Define list of all required packages (by category, comment why we need the package for non-obvious ones)
  local REQUIRED_PACKAGES=(
      apt-utils # apt-utils required to avoid error: debconf: delaying package configuration, since apt-utils is not installed
      apt-transport-https # APT transport for downloading via the HTTP Secure protocol (HTTPS)
      software-properties-common # Part of "apt": manage the repositories that you install software from 3rd party repos (i.e. add their repo + gpg key)

      # Curl must exist for this script and many others
      curl

      # The ff_bash_functions require jq
      jq

      # This script requires grep
      grep

      # Docker requires these
      gnupg2
      lsb-release

      # System: CA certificates
      ca-certificates # Common CA certificates - Docker requires
  )

  # Temporarily disabled because Dmitry broke it all
  # add_to_install_if_missing ${REQUIRED_PACKAGES[@]}

  apt_install ${REQUIRED_PACKAGES[@]} || { set_state "${FUNCNAME[0]}" 'error_failed_apt_install'; return 1; }

  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

# ##########################################################################################
# #
# # The following function defines the list of packages required to run "puppeteer" as a part
# # of unit tests on our porjects.
# # See the official "Puppeteer: Troubleshooting" page:
# # https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md
# #
# ##########################################################################################
# function apt_install_puppeteer_dependencies {
#   local REQUIRED_PACKAGES=(
#     ca-certificates
#     fonts-liberation
#     libappindicator3-1
#     libasound2
#     libatk-bridge2.0-0
#     libatk1.0-0
#     libc6
#     libcairo2
#     libcups2
#     libdbus-1-3
#     libexpat1
#     libfontconfig1
#     libgbm1
#     libgcc1
#     libglib2.0-0
#     libgtk-3-0
#     libnspr4
#     libnss3
#     libpango-1.0-0
#     libpangocairo-1.0-0
#     libstdc++6
#     libx11-6
#     libx11-xcb1
#     libxcb1
#     libxcomposite1
#     libxcursor1
#     libxdamage1
#     libxext6
#     libxfixes3
#     libxi6
#     libxrandr2
#     libxrender1
#     libxss1
#     libxtst6
#     lsb-release
#     wget
#     xdg-utils
#   )
# }


# ###############################################################################
# #
# # install_ntp disables timesyncd and installs ntp if missing
# #
# # The systemd-timesyncd is basically a small client-only NTP implementation more or less bundled with newer systemd releases.
# # It's more lightweight than a full ntpd but only supports time sync - i.e. it can't act as an NTP server for other machines.
# # We should not use both in parallel, as in theory they could pick different timeservers that have a slight delay between them,
# # leading to your system clock being periodically "jumpy".
# #
# # Comparing the ntp and systemd-timesyncd I found out that ntpd is much better solution:
# # systemd-timesyncd does no clock discipline: the clock is not trained or compensated, and internal clock drift over time is not reduced.
# # It has rudimentary logic to adjust poll interval but without disciplining the host will end up with uneven time forever as
# # systemd-timesyncd pushes or pulls at whatever interval it thinks the near-term drift requires. It also can't assess the
# # quality of the remote time source. You're unlikely to get accuracy much greater than 100ms. This is sufficient for simple
# # end user devices like laptops, but it could definitely cause problems for distributed systems that want greater time precision.
# # (source article: https://unix.stackexchange.com/questions/305643/ntpd-vs-systemd-timesyncd-how-to-achieve-reliable-ntp-syncing/464729#464729 )
# #
# # So install_ntp disables "systemd-timesyncd" and leaves only "ntpd".
# #
# # Return value: 0 = success, 1 = failure
# #
# # Note: f-n also uses set_state()
# #
# function replace_timesyncd_with_ntpd {
#     set_state "${FUNCNAME[0]}" 'started'

#     # Check if timesyncd is active (disable if active)
#     IS_TIMESYNCD_ACTIVE=$( systemctl status systemd-timesyncd.service | grep -i active | awk '{print $2}' )  # returns 'active' or 'inactive'

#     # Have to commend out the "if" statement below. Here's the reason why:
#     #   Noted IBM agents, where "timedatectl status" still reports non-ntpd time syncing is in place: "Network time on: yes"
#     #   BUT AT THE SAME TIME the "systemctl status systemd-timesyncd.service" output shows "Active: inactive (dead)"
#     #   and only after we run "sudo timedatectl set-ntp no" the output of "timedatectl status" will be finally expected: "Network time on: no"
#     #
#     # if [ "${IS_TIMESYNCD_ACTIVE}" == "active" ]; then

#         # timesyncd is active, need to deactivate it:
#         sudo timedatectl set-ntp no

#         # make sure timedatectl is not not active
#         IS_TIMESYNCD_ACTIVE=$( systemctl status systemd-timesyncd.service | grep -i active | awk '{print $2}' )  # returns 'active' or 'inactive'
#         if [ "${IS_TIMESYNCD_ACTIVE}" == "active" ]; then
#             # Still active! Error out
#             set_state "${FUNCNAME[0]}" 'failed_stop_timesyncd'
#             return 1
#         fi

#     #fi

#     # Check if ntpd is insatalled (install if missing)
#     IS_NTP_INSTALLED=$( dpkg --get-selections ntp | grep -v deinstall | grep install | awk '{print $2}' )  # returns 'install' if is installed or emptry string if not
#     if [ "${IS_NTP_INSTALLED}" != "install" ]; then
#         # ntp is not installed, install it
#         apt_install ntp

#         # Check if ntp is now installed
#         IS_NTP_INSTALLED=$( dpkg --get-selections ntp | grep -v deinstall | grep install | awk '{print $2}' )  # returns 'install' if is installed or emptry string if not
#         if [ "${IS_NTP_INSTALLED}" != "install" ]; then
#             # Still not isntalled! Error out
#             set_state "${FUNCNAME[0]}" 'failed_install_ntp'
#             return 1
#         fi
#     fi

#     # Enble NTP (this will make it to autostart on reboot)
#     sudo systemctl enable ntp
#     if [ $? -ne 0 ]; then
#         set_state "${FUNCNAME[0]}" 'failed'
#     fi

#     # Start NTP (note: it is safe to try to start in case it is already running - this might happen if ntp was not installed and was just added 1st time by apt)
#     sudo systemctl start ntp
#     if [ $? -ne 0 ]; then
#         set_state "${FUNCNAME[0]}" 'failed'
#     fi

#     # Last status check: query local ntpd
#     LOCAL_NTP_QUERY_STATUS=$( ntpq -pn )
#     LOCAL_NTP_QUERY_STATUS_EXIT_CODE=$?

#     if [ ${LOCAL_NTP_QUERY_STATUS_EXIT_CODE} -ne 0 ]; then
#         set_state "${FUNCNAME[0]}" 'failed'
#         return 1
#     fi

#     set_state "${FUNCNAME[0]}" 'success'
#     return 0
# }

###############################################################################
#
# Сreate a new ff_agent/.profile file and source it from the ~/.bashrc
# and ~/.profile files of the selected user.
#
# Require environment variables set:
#   - FF_AGENT_USERNAME
#   - FF_AGENT_HOME
#
function install_ff_agent_bashrc {
  set_state "${FUNCNAME[0]}" 'started'

  # Define required variables
  local REQUIRED_VARIABLES=( 
    FF_AGENT_USERNAME
    FF_AGENT_HOME
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done
  
  # Make sure ${FF_AGENT_HOME} folder exists
  if [ ! -d "${FF_AGENT_HOME}" ]; then
    # ${FF_AGENT_HOME} folder is missing. Don't try to create it (it is responsibility of ensure_ff_agent_home_exists()).
    # Report an error and abort.
    error "FF_AGENT_HOME='${FF_AGENT_HOME}' directory Does not exist. Aborting."
    abort
  fi

  # Define location of two profile files
  local HOME_PROFILE_FILE="${HOME}/.profile"
  FF_AGENT_PROFILE_FILE="${FF_AGENT_HOME}/.profile"    # example: /home/ubuntu/ff_agent/.profile  (Note: FF_AGENT_PROFILE_FILE is not local, but shell environment used in other install functions)

  # Define location of .bashrc file
  local HOME_BASHRC_FILE="${HOME}/.bashrc"

  # --------------------------------------------------------------------
  # Inject sourcing ff_agent/.profile into files:
  TARGET_FILES=( "${HOME_BASHRC_FILE}" "${HOME_PROFILE_FILE}" )

  # Iterate target files
  for TARGET_FILE in "${TARGET_FILES[@]}"; do
    # Create TARGET_FILE if missing
    if [ ! -f "${TARGET_FILE}" ]; then
      (
        cat <<EOT
# File ${TARGET_FILE} created by set_environment ${FUNCNAME[0]}() on $(date --utc).
EOT
      ) > "${TARGET_FILE}" || { set_state "${FUNCNAME[0]}" "failed_to_create_file"; return 1; }
    fi
    
    PATTERN="^source \"${FF_AGENT_PROFILE_FILE}\""
    INJECT_CONTENT=$(
      cat <<EOT
# Sourcing ${FF_AGENT_PROFILE_FILE} injected by set_environment ${FUNCNAME[0]}() on $(date --utc).
source "${FF_AGENT_PROFILE_FILE}"
EOT
    )
    ERROR_CODE='error_injecting_source_custom_profile'
      
    # Do injection and check result
    inject_into_file "${TARGET_FILE}" "${PATTERN}" "${INJECT_CONTENT}" || { set_state "${FUNCNAME[0]}" "${ERROR_CODE}"; return 1; }
  done
  #
  # --------------------------------------------------------------------


  # --------------------------------------------------------------------
  # Inject sourcing ff_bash_functions

  # Define path to the installed ff_bash_functions
  local FF_BASH_FUNCTIONS_PATH="${FF_AGENT_HOME}/git/redwolfsecurity/set_environment/src/ff_bash_functions"
  
  # Inject into the custom .profile to source ff_bash_functions (if missing)
  # Search expected line
  TARGET_FILE="${FF_AGENT_PROFILE_FILE}"
  PATTERN="^source \"${FF_BASH_FUNCTIONS_PATH}"
  INJECT_CONTENT=$(
    cat <<EOT    
# Sourcing bash functions library from ${FF_BASH_FUNCTIONS_PATH} injected by set_environment ${FUNCNAME[0]}() on $(date --utc).
source "${FF_BASH_FUNCTIONS_PATH}"
EOT
  ) 
  ERROR_CODE='error_injecting_source_ff_bash_functions'

  # Create TARGET_FILE if missing
  if [ ! -f "${TARGET_FILE}" ]; then
    (
      cat <<EOT
# File ${TARGET_FILE} created by set_environment ${FUNCNAME[0]}() on $(date --utc).
EOT
    ) > "${TARGET_FILE}" || { set_state "${FUNCNAME[0]}" "failed_to_create_file"; return 1; }
  fi

  # Do injection and check result
  inject_into_file "${TARGET_FILE}" "${PATTERN}" "${INJECT_CONTENT}" || { set_state "${FUNCNAME[0]}" "${ERROR_CODE}"; return 1; }
  #
  # --------------------------------------------------------------------
  

  # --------------------------------------------------------------------
  # Inject call to "discover_environment" into the custom .profile
  TARGET_FILE="${FF_AGENT_PROFILE_FILE}"
  PATTERN="^discover_environment"
  INJECT_CONTENT=$(
      cat <<EOT    
discover_environment
EOT
  )
  ERROR_CODE='error_injecting_discover_environment_call_to_custom_profile'

  # Do injection and check result
  inject_into_file "${TARGET_FILE}" "${PATTERN}" "${INJECT_CONTENT}" || { set_state "${FUNCNAME[0]}" "${ERROR_CODE}"; return 1; }
  #
  # --------------------------------------------------------------------
  

  # --------------------------------------------------------------------
  # Inject ${FF_AGENT_BIN} into PATH in .profile and modify current PATH if needed. 
  
  # Define the path to ff_agent/bin folder, which we will inject into PATH
  local FF_AGENT_BIN="${FF_AGENT_HOME}/bin"

  # Update PATH variable (if it not yet contains expected string)
  printenv PATH | grep --quiet "${FF_AGENT_BIN}"
  if [ ${?} -ne 0 ]; then
    export PATH="${FF_AGENT_BIN}:${PATH}" || { set_state "${FUNCNAME[0]}" 'error_modifying_path'; return 1; }
  fi

  TARGET_FILE="${FF_AGENT_PROFILE_FILE}"
  PATTERN="^export PATH=\"${FF_AGENT_BIN}"
  INJECT_CONTENT=$(
      cat <<EOT   
export PATH="${FF_AGENT_BIN}:\${PATH}"
EOT
  )
  ERROR_CODE='error_injecting_ff_agent_bin_path_to_custom_profile'

  # Do injection and check result
  inject_into_file "${TARGET_FILE}" "${PATTERN}" "${INJECT_CONTENT}" || { set_state "${FUNCNAME[0]}" "${ERROR_CODE}"; return 1; }
  #
  # --------------------------------------------------------------------
  
  # Chage state and return success
  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
# Install @ff/ff_agent -> ff_agent/bin
#
function install_ff_agent {
  set_state "${FUNCNAME[0]}" 'started'

  # Define the version of ff_agent npm package to install from CDN
  VERSION='latest'

  # If we are on arm64, we likely need to install some extra packages
  # This is done as a case, just in case we have other such architectural changes for other architectures.
  case $( get_hardware_architecture ) in
    arm64)
      PACKAGES_TO_INSTALL=(
        libcurl4-openssl-dev
        build-essential
      )
      apt_install ${PACKAGES_TO_INSTALL[@]} || { set_state "${FUNCNAME[0]}" 'terminal_error_unable_to_install_ff_agent_dependencies'; abort; }
    ;;
    *)
    ;;
  esac
  
  # Install ff_agent
  npm install --global "${FF_CONTENT_URL}/ff/npm/ff-ff_agent-${VERSION}.tgz" || { set_state "${FUNCNAME[0]}" 'terminal_error_failed_to_install_ff_agent'; abort; }

  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
# Install nodejs latest environment
function install_nodejs_suite {
  set_state "${FUNCNAME[0]}" 'started'

  install_node_ubuntu                     || { set_state "${FUNCNAME[0]}" 'terminal_error_install_node'; abort; }

  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
function install_node_ubuntu {
  set_state "${FUNCNAME[0]}" 'started'

  local APPROACH='n'
  
  # Get expected nodejs version
  local VERSION="$( get_expected_nodejs_version )"
  [ -z "${VERSION}" ] && { set_state "${FUNCNAME[0]}" 'failed_to_get_expected_nodejs_version'; abort; }

  case ${APPROACH} in
      nvm)
          install_nvm_ubuntu
          export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
          [ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"
          nvm install lts/*
      ;;
      n)
          # # We need to stop pm2 before replacing location of nodejs, otherwise any pm2 command would faild
          # stop_pm2
          #uninstall_n_outside_ff_agent_home  || { set_state "${FUNCNAME[0]}" 'terminal_error_uninstall_n_outside_ff_agent_home'; abort; }
          install_n || { set_state "${FUNCNAME[0]}" 'terminal_error_install_n'; abort; }
          n install "${VERSION}" || { set_state "${FUNCNAME[0]}" 'terminal_error_switching_node_version'; abort; }
      ;;
  esac

  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
# Installations of "n" based on the tutorial:
#  "Getting started with n (node version management)"
#   https://zacharytodd.com/posts/n-version-manager/
# 
#
# Require environment variables set:
#   - FF_AGENT_PROFILE_FILE
#   - FF_AGENT_HOME
#
# Official n github page:
#   https://github.com/tj/n
#   https://github.com/tj/n#installation
#
function install_n {
  set_state "${FUNCNAME[0]}" "installing"

  # Define required variables
  local REQUIRED_VARIABLES=(
    FF_AGENT_PROFILE_FILE
    FF_AGENT_HOME
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done

  # Check custom .profile file exists
  if [ ! -f "${FF_AGENT_PROFILE_FILE}" ]; then
    # Let's not try to re-create it if missing.
    # It should have been created by existing f-n install_ff_agent_bashrc() (defined in project: "set_environment", see file: src/ff_bash_functions)
  	set_state "${FUNCNAME[0]}" "error_custom_ff_agent_profile_does_not_exist"
    return 1
  fi

  # Create tmp folder and change directory into it
  TMPDIR="$( mktemp -d )"
  pushd "${TMPDIR}" || { set_state "${FUNCNAME[0]}" 'error_pushd_to_tmp_directory'; return 1; }

  # Attempt 1: download 'n' from FF_CONTENT_URL
  # Try FF_CONTENT_URL first because it gives more control over what version of 'n' will be executed.
  # The magour update on the github might introduce some breaking change, let's leave it for 2nd attept only.
  SAVE_AS='n'
  URL="${FF_CONTENT_URL}/ff/ff_agent/hotpatch/hotpatch_files/${SAVE_AS}"
  curl \
    -sL \
    --retry 5 \
    --retry-delay 1 \
    --retry-max-time 60 \
    --max-time 55 \
    --connect-timeout 12 \
    -o "${SAVE_AS}" \
    "${URL}"
  
  # Check curl exit code
  if [ ${?} -ne 0 ]; then
      set_state "${FUNCNAME[0]}" 'failed_to_download_n_from_content_server'
      
      # Attempt 2: download 'n' from from github
      URL="https://raw.githubusercontent.com/tj/n/master/bin/n"
      curl \
        -sL \
        --retry 5 \
        --retry-delay 1 \
        --retry-max-time 60 \
        --max-time 55 \
        --connect-timeout 12 \
        -o "${SAVE_AS}" \
        "${URL}"
      
      # Check curl exit code
      if [ ${?} -ne 0 ]; then
        # The 2nd attempt failed too, giving up.
        # Error: clean up tmp folder, report an error and return error code 1
        popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }
        set_state "${FUNCNAME[0]}" 'warning_failed_to_download_n_from_github'
        return 1
      fi      
  fi
  
  # Export 2 env variables we need for "n" to operate properly:  and NODE_PATH

  # ------------------ Export N_PREFIX and inject that export into FF_AGENT_PROFILE_FILE (begin) ----------------
  export N_PREFIX="${FF_AGENT_HOME}/.n"  # example: /home/ubuntu/ff_agent/.n

  # Add '# Export N_PREFIX' into the custom .profile file if in was not injected earlier.
  # TODO: add into ff_bash_funcitons a function to add/edit/remove our custom profile file.
  TARGET_FILE="${FF_AGENT_PROFILE_FILE}"
  PATTERN="^export N_PREFIX=\"${FF_AGENT_HOME}/.n\""
  EXPECTED_LINE="export N_PREFIX=\"${FF_AGENT_HOME}/.n\""
  if ! file_contains_pattern "${TARGET_FILE}" "${PATTERN}"; then
    # Expected line is missing, Inject text
    (
      cat <<EOT
# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)
${EXPECTED_LINE}
EOT
    ) >> "${TARGET_FILE}" || {
        # Error: clean up tmp folder, report an error and return error code 1
        popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }
        set_state "${FUNCNAME[0]}" 'error_injecting_export_n_prefix_to_ff_agent_profile'; return 1;
    }
  fi
  # ------------------ Export N_PREFIX and inject that export into FF_AGENT_PROFILE_FILE (begin) ----------------


  # ------------------ Export NODE_PATH and inject that export into FF_AGENT_PROFILE_FILE (begin) ----------------
  # We set NODE_PATH, so npm can load modules. Details: https://stackoverflow.com/questions/12594541/npm-global-install-cannot-find-module
  export NODE_PATH="${FF_AGENT_HOME}/.n/lib/node_modules"

  # Add '# Export NODE_PATH' into the custom .profile file if in was not injected earlier.
  # TODO: add into ff_bash_funcitons a function to add/edit/remove our custom profile file.
  TARGET_FILE="${FF_AGENT_PROFILE_FILE}"
  PATTERN="^export NODE_PATH=\"${FF_AGENT_HOME}/.n/lib/node_modules\""
  EXPECTED_LINE="export NODE_PATH=\"${FF_AGENT_HOME}/.n/lib/node_modules\""
  if ! file_contains_pattern "${TARGET_FILE}" "${PATTERN}"; then
    # Expected line is missing, Inject text
    (
      cat <<EOT
# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)
${EXPECTED_LINE}
EOT
    ) >> "${TARGET_FILE}" || {
        # Error: clean up tmp folder, report an error and return error code 1
        popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }
        set_state "${FUNCNAME[0]}" 'error_injecting_export_node_path_to_ff_agent_profile'; return 1;
    }
  fi
  # ------------------ Export NODE_PATH and inject that export into FF_AGENT_PROFILE_FILE (end) ----------------
  

  # ------------------ Inject "ff_agent/.n/bin" into PATH and inject that export into FF_AGENT_PROFILE_FILE (begin) ----------------

  # Update PATH variable (if it not yet contains expected string)
  printenv PATH | grep --quiet "${N_PREFIX}/bin"
  if [ ${?} -ne 0 ]; then
    export PATH="${N_PREFIX}/bin:${PATH}" || {
        # Error: clean up tmp folder, report an error and return error code 1
        popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }
        set_state "${FUNCNAME[0]}" 'error_modifying_path'; return 1; 
    }
  fi

  # Note: we escape "\$" in front of the PATH, so it does not get expanded
  TARGET_FILE="${FF_AGENT_PROFILE_FILE}"
  PATTERN="^export PATH=\"${N_PREFIX}/bin:\${PATH}\""
  EXPECTED_LINE="export PATH=\"${N_PREFIX}/bin:\${PATH}\""
  if ! file_contains_pattern "${TARGET_FILE}" "${PATTERN}"; then
    # Expected line is missing, Inject text
    (
      cat <<EOT
# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)
${EXPECTED_LINE}
EOT
    ) >> "${TARGET_FILE}" || {
        # Error: clean up tmp folder, report an error and return error code 1
        popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }
        set_state "${FUNCNAME[0]}" 'error_injecting_n_prefix_bin_to_ff_agent_profile'; return 1;
    }
  fi
  # ------------------ Inject "ff_agent/.n/bin" into PATH and inject that export into FF_AGENT_PROFILE_FILE (end) ----------------


  # Install 'npm' using dowloaded into TMPDIR 'n' ('npm' will be installed into ff_agent/.n)
  bash n lts || { 
    # Error: clean up tmp folder, report an error and return error code 1
    popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }
    set_state "${FUNCNAME[0]}" 'error_installing_npm'; return 1; 
  }

  # Install 'n' into ff_agent/.n  (yes, we have downloaded 'n' into TMPDIR,
  # then used it to install 'npm', and now we use 'npm' to install "globally" n.
  # The proper installed 'n' will reisde under ff_agent/.n/ folder)
  npm install --global n || { 
    # Error: clean up tmp folder, report an error and return error code 1
    popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }
    set_state "${FUNCNAME[0]}" 'error_installing_n'; return 1; 
  }

  # Clean up tmp folder
  popd || { set_state "${FUNCNAME[0]}" 'error_popd'; return 1; }; rm -fr "${TMPDIR}"  || { set_state "${FUNCNAME[0]}" 'failed_to_remove_tmpdir'; return 1; }

  # Chage state and return success
  set_state "${FUNCNAME[0]}" 'success'
  return 0
}


###############################################################################
# Category: process
# is_pm2_running_as_me
# Will return 0 if it is, 1 if it is not
function is_pm2_running_as_me () {
    set_state "${FUNCNAME[0]}" 'started'
    # Process will look like PM2 v4.5.5: God Daemon (/home/user/.pm2)
    local PATTERN="PM2 .*: God Daemon"

    # Check if process is running as local user.
    is_process_running_as_me "${PATTERN}"
    STATUS=$?

    set_state "${FUNCNAME[0]}" 'success'

    return ${STATUS}
}
export -f is_pm2_running_as_me

###############################################################################
# Category: process
# pm2_install
# Will install pm2 if there is no command 'pm2'
# Will not start it
function pm2_install () {
    set_state "${FUNCNAME[0]}" 'started'

    local NPM_PACKAGE="pm2"
    local VERSION="latest"

    # We will try to stop it. But that won't stop us from uninstalling it.
    is_pm2_running_as_me && stop_pm2

    local PM2=$( command_exists "${NPM_PACKAGE}" )
    [ "${PM2}" != "" ] && { set_state "${FUNCNAME[0]}" 'success_no_action_already_installed'; return 0; }

    local NPM=$( command_exists npm)
    [ "${NPM}" = "" ] && { set_state "${FUNCNAME[0]}" 'error_dependency_not_met_npm'; return 1; }

    # Actually install it -- globally
    ${NPM} install --global "${NPM_PACKAGE}@${VERSION}"  || { set_state "${FUNCNAME[0]}" 'error_installing_pm2_npm'; return 1; }

    # Verify command actually exists in path after we have installed it
    local PM2=$( command_exists "${NPM_PACKAGE}" )
    [ "${PM2}" == "" ] && { set_state "${FUNCNAME[0]}" 'error_installing_pm2_command_not_found'; return 0; }

    set_state "${FUNCNAME[0]}" 'success'
}
export -f pm2_install

###############################################################################
# Category: process
# pm2_configure
# Configures pm2 the way we want it configured
function pm2_configure () {
    set_state "${FUNCNAME[0]}" 'started'
    # Now it is installed, and command is in path. So we shall configure it
    # Configure it to automatically save state
    timeout 30 pm2 set pm2:autodump true            || { set_state "${FUNCNAME[0]}" "pm2_configure_autodump_error"; return 1; }

    # Configure it to rotate logs
    timeout 45 pm2 install pm2-logrotate            || { set_state "${FUNCNAME[0]}" "pm2_install_logrotate_error"; return 1; }
    timeout 30 pm2 set pm2-logrotate:max_size 20M   || { set_state "${FUNCNAME[0]}" "pm2_configure_logrotate_error"; return 1; }
    timeout 30 pm2 set pm2-logrotate:retain 7       || { set_state "${FUNCNAME[0]}" "pm2_configure_logrotate_error"; return 1; }
    timeout 30 pm2 set pm2-logrotate:compress true  || { set_state "${FUNCNAME[0]}" "pm2_configure_logrotate_error"; return 1; }

    # configure it to rotate logs every hour
    timeout 30 pm2 set pm2-logrotate:rotateInterval '0 0 * * * *'  || { set_state "${FUNCNAME[0]}" "pm2_configure_logrotate_error"; return 1; }
    timeout 30 pm2 update || { set_state "${FUNCNAME[0]}" "pm2_update_error"; return 1; }

    set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
# Category: process
# pm2_uninstall
# Removes PM2
function pm2_uninstall () {
    set_state "${FUNCNAME[0]}" 'started'

    local PACKAGE="pm2"

    # If it is not installed, we are done.
    is_pm2_installed || { set_state "${FUNCNAME[0]}" 'success_no_action_not_installed'; return 1; }

    # It's installed, so we will try to remove it
    local NPM=$( command_exists npm)
    [ "${NPM}" = "" ] && { set_state "${FUNCNAME[0]}" 'error_dependency_not_met_npm'; return 1; }
    ${NPM} remove --global "${PACKAGE}" || { set_state "${FUNCNAME[0]}" 'error_uninstalling_package'; return 1; }

    # Verify it is removed. If this returns 1, it is not found. If it returns 0, we still have it.
    is_pm2_installed || { set_state "${FUNCNAME[0]}" 'success'; return 0; }

    set_state "${FUNCNAME[0]}" 'error_validating_uninstallation'
}
export -f pm2_uninstall


###############################################################################
# Category: process
# is_pm2_installed
# Checks if pm2 is installed
# Returns 0 if it is, 1 if it isn't
function is_pm2_installed () {
    set_state "${FUNCNAME[0]}" 'started'
    local STATUS=0
    local PACKAGE="pm2"
    local NPM=$( command_exists npm) || { set_state "${FUNCNAME[0]}" 'error_dependency_not_met_npm'; return 1; }

    # If it not installed, set STATUS=1
    ${NPM} list "${PACKAGE}" --global >/dev/null || STATUS=1

    set_state "${FUNCNAME[0]}" 'success'
    return ${STATUS}
}
export is_pm2_installed

###############################################################################
# Category: process
# pm2_start
function pm2_start () {
    set_state "${FUNCNAME[0]}" 'started'

    # Check if it is running. If it is, we're happy.
    is_pm2_running_as_me && { set_state "${FUNCNAME[0]}" 'success_no_action_pm2_not_running'; return 1; }

    local PM2=$( command_exists pm2 )
    [ -z "${PM2}" ] && { set_state "${FUNCNAME[0]}" 'error_dependency_not_met_pm2_command'; return 0; }
    $PM2 start

    # Check if it is running. If it is, we're happy.
    # Note: pm2 can start and still return non-zero (i.e. it started but there was no ecosystem.config.js
    # So it is not sufficient to test for return code, but if it is running as me, then it is at least started
    is_pm2_running_as_me && { set_state "${FUNCNAME[0]}" 'success'; return 1; }

    set_state "${FUNCNAME[0]}" 'error_failed_to_start_pm2'
}
export -f pm2_start

###############################################################################
# Category: process
# pm2_stop stops the running pm2 daemon running as the current user.
# does not stop any root level or other user pm2 daemons.
#
function pm2_stop () {
    set_state "${FUNCNAME[0]}" 'started'

    # Check if it is running. If it isn't, we finish.
    is_pm2_running_as_me || { set_state "${FUNCNAME[0]}" 'success_no_action_pm2_not_running'; return 1; }

    # Check if we have the pm2 command. We need it to be able to stop pm2
    local PM2=$( command_exists pm2 ) || { set_state "${FUNCNAME[0]}" 'error_pm2_command_not_found'; return 1; }

    # Try and kill pm2
    # Todo: do this with timeout - sometimes pm2 hangs. We ask it to kill itself, but sometimes the cat comes back :)
    $PM2 kill || { set_state "${FUNCNAME[0]}" 'error_pm2_kill_failed'; return 1; }

    # Verify that it is actually stopped. If it is still running after we killed it, it is a problem.
    is_pm2_running_as_me || { set_state "${FUNCNAME[0]}" 'error_unable_to_validate_pm2_daemon_gone_postcondition_pm2_still_running'; return 1; }

    # We have stopped it, and it is not running.
    set_state "${FUNCNAME[0]}" 'success'
}
export -f pm2_stop

###############################################################################
# Category: process
# pm2_ensure
# This ensures that pm2 is running, and working as we wish. aborts otherwise.
# If it is not installed, we install it.
function pm2_ensure () {
    set_state "${FUNCNAME[0]}" 'started'

    # We are good if pm2 is running as me
    # This is the fastest check we can do, so we do it first
    is_pm2_running_as_me && { set_state "${FUNCNAME[0]}" 'success_no_action_already_running'; return 0; }

    # It is not running, so it might not be installed.
    # Is pm2 installed? If not, install it
    is_pm2_installed || pm2_install || { set_state "${FUNCNAME[0]}" 'error_failed_to_install'; abort; }

    # Now it has to at least be installed, and not running, so we try to start it.
    pm2_start

    is_pm2_running_as_me || { set_state "${FUNCNAME[0]}" 'error_not_running_as_user'; return 1; }

    # Now it is running, so let's configure it
    pm2_configure || { set_state "${FUNCNAME[0]}" 'error_configuring'; return 1; }

    # If all above works, we have it running
    set_state "${FUNCNAME[0]}" 'success'
}
export -f pm2_ensure

###############################################################################
#
# Return information if package is installed in system, dpkg depend
# @param $1 string package name
# @param ${2} array  package list to append
# @return  Success if value exists, Failure otherwise
# Usage: add_to_install_if_missing "vim" PACKAGES
#
function add_to_install_if_missing {

	declare -n PACKAGES_TO_INSTALL=${2}

	local CHECK_PKG_MSG="INFO: Checking availability of ${FONT_STYLE_BOLD}%s${FONT_STYLE_NORMAL} package in system"
	local   ADD_PKG_MSG="DEBUG: Adding ${FONT_STYLE_BOLD}%s${FONT_STYLE_NORMAL} to required packages to install"
	local  HAVE_PKG_MSG="INFO: Package ${FONT_STYLE_BOLD}%s${FONT_STYLE_NORMAL} already installed, skipping"

	#log "${CHECK_PKG_MSG/\%s/$1}"

	# Grep exit code 0=installed, 1=not installed.
	# Note we use grep to cover case "Status: deinstall ok config-files" when package was uninstalled.
	dpkg --status ${1} 2>/dev/null | grep --silent "installed"
	INSTALLED=${?}

    # Check exit code
	if [[ ${INSTALLED} != 0 ]]; then
		PACKAGES_TO_INSTALL+=(${1})
	# 	log "${ADD_PKG_MSG/\%s/$1}"
	# else
	# 	log "${HAVE_PKG_MSG/\%s/$1}"
	fi

	return ${INSTALLED}
}

###############################################################################
#
# Function analyzes currently selected user and might call "background_install()" to
# re-run the installer under a different user.
#
# We may need, for various reasons, to launch a background install.
#
# Return value:
#    - function prints "true" to standard output only if we need to background_install as "${FF_AGENT_USERNAME}"
#    - function returns/prints nothing if no need to background install
#    - on error function aborts (no need to errorcheck by the caller)
#
#
# Dependency:
#   FF_AGENT_USERNAME - must be set
#
function check_if_need_background_install {

  # Define required variables
  local REQUIRED_VARIABLES=(
    FF_AGENT_USERNAME
  )

  # Check required environment variables are set
  for VARIABLE_NAME in "${REQUIRED_VARIABLES[@]}"; do
    ensure_variable_not_empty "${VARIABLE_NAME}" || { return 1; }  # Note: the error details were already reported by ensure_variable_not_empty()
  done

  # It might already exist, but not be writable due to chmod changes
  if [ -f "${FF_AGENT_HOME}" ] && [ ! -w "${FF_AGENT_HOME}" ]; then
      # TODO: The ${USER} environment is NOT set when running as 'root' in docker. Improve this.
      error "FF_AGENT_HOME at ${FF_AGENT_HOME} is not writable by user $( whoami ). Aborting."
      abort
  fi

  DO_BACKGROUND_INSTALL=false

  # Suppose I'm not the best user, but I can sudo to become the best! e.g. If I am root - I'm not the best user.
  if [ "${USER}" != "${FF_AGENT_USERNAME}" ]; then
      if can_sudo "${USER}"; then
          DO_BACKGROUND_INSTALL=true
      fi
  fi

  # Am I effectively root?
  if [ "${EUID}" -eq 0 ]; then
      DO_BACKGROUND_INSTALL=true
  fi

  if [ "${DO_BACKGROUND_INSTALL}" == "true" ]; then
    echo "true"
    ## background_install "${FF_AGENT_USERNAME}"
    ## We can not exit, since "set_environment" installer is sourced: ". ./install.sh"
    ##exit 0
  fi

  # Otherwise we continue happily through this instance of the script. No need to change user.
  # i.e. I am not root, and I have sudo priveleges.
}

###############################################################################
#
# background_install: run installer again under different user.
#
# Background install involves:
#   - Writing a copy of the set_environment into temporary location and changing permissions to the target user.
#   - Running that script as correct target user.
#
# TODO: it seems the tmp directory created by "mktemp" never got deleted.
function background_install {

  # Take the only argument: target username to "run as"
  USER_TO_RUN_AS="${1}"

  # Check argument is not empty string
  [ "${USER_TO_RUN_AS}" == "" ] && { error "background_install error: missing argument"; abort; }

  # Check if target user can sudo
  can_sudo "${USER_TO_RUN_AS}" || { error "background_install needs to sudo to user ${USER_TO_RUN_AS} but user ${USER} does not have sudo privileges"; abort; }

  # Create temporary folder
  TEMP_DIR=$( mktemp -d ) || { error "background_install tried to create directory ${TEMP_DIR}."; abort; }
  
  # Check if folder created
  [ ! -d "${TEMP_DIR}" ] && { error "background_install tried to create directory ${TEMP_DIR}."; abort; }

  # Copy set_environment project into the target temporary folder
  cp -a ../set_environment "${TEMP_DIR}" || { error "background_install failed to copy project to temporary folder '${TEMP_DIR}'"; abort; }

  # Chenge ownership of the temporary folder to the target user
  chown -R "${FF_AGENT_USERNAME}:$(id -gn ${FF_AGENT_USERNAME})" "${TEMP_DIR}"

  # Pass control to the newly created set_environment copy (run by the target user) and exit
  sudo --set-home --user="${USER_TO_RUN_AS}" bash -c "${TEMP_DIR}/set_environment/install.sh"
}

###############################################################################
#
# Function preserve_sources require the only argument: root folder of the project from which installer was started.
# It will analyze if installer was started from expected place (ff_agent/git/[companyname]/set_environment/ folder) and if not
# it will preserve source code into appropriate folder for future reuse (updates etc.).
#
function preserve_sources {
  PROJECT_ROOT_DIR="$1"
  if [ ! -d "${PROJECT_ROOT_DIR}" ]; then
    error "Error: failed to preserve_sources"
    return 1
  fi

  # As a preparation to preserve project source files (used during this installation), let's change directory to the project root directory.
  pushd "${PROJECT_ROOT_DIR}" || { error "Error: failed to change directory into the project root ${PROJECT_ROOT_DIR}" >&2; exit 1; }

  # Make sure ${FF_AGENT_HOME} is set
  [ -z "${FF_AGENT_HOME}" ] && { error "Error: FF_AGENT_HOME is not set." >&2; exit 1; }

  # Extract project owner from github repository URL
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
}

###############################################################################
#
function setup_logging {
	set_script_logging 
}

###############################################################################
# Log this script standard output and standard error to a log file AND system logger
function set_script_logging {

  # Note: we can not yet call "set_state" on that early stages
 	#set_state "${FUNCNAME[0]}" 'started'

  # Let's find a good directory for logs. This assumes zero knowledge.
  # The _best_ place for these logs would be in ${HOME}/ff_agent/logs -- if we can write to it we'll create it
  POTENTIAL_LOG_DIRECTORIES=( "${FF_AGENT_HOME}/logs" /var/log/ff_agent /tmp/ff_agent/logs /tmp/ff_agent.$$/logs )

  LOG_DIRECTORY=""

  # Find a directory we can write to. The first will do.
  for POTENTIAL_LOG_DIRECTORY in "${POTENTIAL_LOG_DIRECTORIES[@]}"
  do
      if mkdir -p "${POTENTIAL_LOG_DIRECTORY}"
      then
          LOG_DIRECTORY=${POTENTIAL_LOG_DIRECTORY}
          break
      fi
  done

  if [ -z "${LOG_DIRECTORY}" ]; then
      error "Unable to find a place to log! Tried: ${POTENTIAL_LOG_DIRECTORIES[@]}"
      export LOG_PATH=$( tty )
  else
      # Get current epoch ms. (note: we can't yet use   # "$( get_epoch_ms )" because ff_bash_functions arent installed/updated yet)
      TIMESTAMP_EPOCH_MS="$( get_epoch_ms )"
      LOG_FILE="set_environment.${TIMESTAMP_EPOCH_MS}.log"
      export LOG_PATH="${LOG_DIRECTORY}/${LOG_FILE}"
      # PREVIOUSLY THIS WAS exec &> >(tee -a "$LOG_PATH")
      exec &> >(tee >(tee -a "${LOG_PATH}" | logger -t set_environment ))
  fi

  # Note: we can not yet call "set_state" on that early stages
 	#set_state "${FUNCNAME[0]}" 'success'
}
