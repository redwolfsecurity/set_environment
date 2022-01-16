#
# This script is a part of "set_environment" installer and should not be called directry.
# It got sourced from src/architecture/linux/continue_install.sh
#

###############################################################################
#
# Continuation of the "set_environment". Installing baseline components.
# On errror: function aborts (so no need to errorcheck on caller side)
#
function install_set_environment_baseline {
    
    # Discover environment:
    #    - generate AGENT_URI and NAMESPACE (if missing in our "secrets")
    #    - set variables: IS_CONTAINER, IS_PORTAL, IS_LOCAL, IS_TRAFFIC_GENERATOR
    discover_environment || { set_state "${FUNCNAME[0]}" "terminal_error_failed_to_discover_environment"; abort; }

    # Analyzes currently selected user and might call "background_install()" to re-run the installer under a different user
    # Note: it have a dependency: variable BEST_USER_TO_RUN_AS - must be set (by calling choose_ff_agent_home)
    if [ "$( check_if_need_background_install )" == "true" ]; then
      background_install "${BEST_USER_TO_RUN_AS}"
      return 0
      # Note: we can not "exit 0" here since installer might be sourced by "root"
    fi

    # Put logs in best location
    setup_logging || { set_state "${FUNCNAME[0]}" "terminal_error_failed_to_setup_logging"; abort; }

    # Install set of basic packages, bash functions, .bashrc and .profile files
    assert_clean_exit assert_basic_components || { set_state "${FUNCNAME[0]}" "terminal_error_failed_to_assert_basic_components"; abort; }

    # Commented out: for "baseline" we don't use andy credentials
    # # Check that required credentials for npm and docker are set up -- abort otherwise. Note: assert_core_credentials
    # # creates ~/.npmrc, while "ensure_standard_environment" is trying to fix wrong owner "root" on ~/.npmrc.
    # # Chicken-and-the-egg proplem. Solved by fixing ownership locally right befoer trying to write into the ~/.npmrc file.
    # assert_core_credentials || { set_state "${FUNCNAME[0]}" "terminal_error_failed_to_assert_core_credentials"; abort; }

    # Note: this require .npm to be already in-place (with secrets)
    # Note: assert_clean_exit aborts on error
    assert_clean_exit install_ff_agent
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
    assert_clean_exit install_ff_bash_functions   # Install ff_bash_functions -> ff_agent/lib/bash/, or abort.

    # Install docker (not using "apt")
    #assert_clean_exit install_docker

    # Install nodejs suite and all its fixings (not using "apt")
    assert_clean_exit install_nodejs_suite

    # Put back in place some of the npm modules installed earlier
    assert_clean_exit install_required_npm_libraries

    set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Assert core credentials (npmrc, docker, ...)
#
function assert_core_credentials {
    set_state "${FUNCNAME[0]}" 'started'
    create_npmrc_credentials || { set_state "${FUNCNAME[0]}" 'error_creating_npmrc_credentials'; exit 1; }
    assert_npmrc_credentials || { set_state "${FUNCNAME[0]}" 'error_asserting_npmrc_credentials'; exit 1; }
    # Temporarily disabled -- our agents don't have our docker credentials!
    # assert_docker_credentials
    set_state "${FUNCNAME[0]}" 'success'
}

###############################################################################
#
# Create .npmrc credentials
#
function create_npmrc_credentials {
    set_state "${FUNCNAME[0]}" 'started'

    # Check required environment variables are set
    [ "${AGENT_HOME_DIR}" != "" ] || { set_state "${FUNCNAME[0]}" 'error_getting_agent_home_dir'; return 1; }

    # TODO: Get these credentials from secret manager
    # TODO: .npmrc can substitue environment variables -- that's at least a touch more secure if we run npm from our FF framework

    # Try to change ownership of the .npmrc file only if it exists (otherwise this would fail on newly installed portals)
    if [ -f "${AGENT_HOME_DIR}/.npmrc" ]; then
      # Yes, file exists. Change its ownership:
      sudo chown -R "${USER}:$(id -gn ${USER})" ${AGENT_HOME_DIR}/.npmrc || { set_state "${FUNCNAME[0]}" 'error_changing_npmrc_ownership'; return 1; }
    fi

    # Update content of the .npmrc file (or create new file if it didn't exist)
    # TODO: remove hardcoded path to source .npmrc - it should be decided "dynamically" instead (depending on the target environment we're setting up)
    cp secrets/development/.npmrc "${AGENT_HOME_DIR}/.npmrc" || { set_state "${FUNCNAME[0]}" 'error_updating_npmrc'; return 1; }

    set_state "${FUNCNAME[0]}" 'success'
    return 0
}

###############################################################################
#
# Assert .npmrc credentials
#
# Dependency:
#   AGENT_HOME_DIR - must be set
#
function assert_npmrc_credentials {
    set_state "${FUNCNAME[0]}" 'started'

    # Check required environment variables are set
    [ "${AGENT_HOME_DIR}" != "" ] || { set_state "${FUNCNAME[0]}" 'error_getting_agent_home_dir'; return 1; }
    # TODO: Make a more rigorous check -- can we actually use these .npmrc credentials? They might be wrong or out of date!

    NPMRC_FILE="${AGENT_HOME_DIR}/.npmrc"
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
# TODO: Sort this list out - either through them out or move into appropriate section (baseline, development, build, etc.)
#
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy cyrus-dev \                     - Cyrus
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy cyrus-dev \                  - Cyrus SASL - authentication abstraction library
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy gnupg-agent \                   - GNU privacy guard - cryptographic agent (dummy transitional package)
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy libcurl4-openssl-dev \
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy liblz4-dev \
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy musl \
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy musl-dev \                      - "mysl" is a standard C library
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy musl-tools \
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy openjdk-11-jdk  \               - java 11
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy pypy-setuptools \               - PyPy Distutils Enhancements: Extensions to the python-distutils for large or complex distributions
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy snmp \                          - SNMP (Simple Network Management Protocol) applications
#      && DEBIAN_FRONTEND=noninteractive apt-get install -qy zlib1g-dev
#
function apt_install_basic_packages {

    set_state "${FUNCNAME[0]}" 'started'

    # Update apt index and installed components, before installing additional packages.
    assert_clean_exit apt_update
    assert_clean_exit apt_upgrade

    # Let's collect all missing packages in the SELECTED_PACKAGES array
    local SELECTED_PACKAGES=()

    # Define list of all required packages (by category, comment why we need the package for non-obvious ones)
    local REQUIRED_PACKAGES=(
        # Consider removing everything below. They are not probably required for the 'base'
        # System: package management
        apt-utils # apt-utils required to avoid error: debconf: delaying package configuration, since apt-utils is not installed
        apt-transport-https # APT transport for downloading via the HTTP Secure protocol (HTTPS)
        software-properties-common # Part of "apt": manage the repositories that you install software from (common)

        # Consider removing 'sudo' - it should ideally not be required.
        # Also the set_environment concept might never need elevated permissions.
        sudo
        # Bash must exist, for we are running in bash
        #bash

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
        ca-certificates-java # Common CA certificates (JKS keystore)
        ca-certificates-mono # Common CA certificates (Mono keystore)

    # Iterate all required packages and collect only missing ones
    for PACKAGE_NAME in ${REQUIRED_PACKAGES[@]}; do
        add_to_install_if_missing "${PACKAGE_NAME}" SELECTED_PACKAGES
    done

    # If we have any selected packages to install - install them.
    if [[ ${#SELECTED_PACKAGES[@]} > 0 ]]; then
        apt_install "${SELECTED_PACKAGES[@]}" || { set_state "${FUNCNAME[0]}" 'error_failed_apt_install'; return 1; }
    fi

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




###############################################################################
#
# install_ntp disables timesyncd and installs ntp if missing
#
# The systemd-timesyncd is basically a small client-only NTP implementation more or less bundled with newer systemd releases.
# It's more lightweight than a full ntpd but only supports time sync - i.e. it can't act as an NTP server for other machines.
# We should not use both in parallel, as in theory they could pick different timeservers that have a slight delay between them,
# leading to your system clock being periodically "jumpy".
#
# Comparing the ntp and systemd-timesyncd I found out that ntpd is much better solution:
# systemd-timesyncd does no clock discipline: the clock is not trained or compensated, and internal clock drift over time is not reduced.
# It has rudimentary logic to adjust poll interval but without disciplining the host will end up with uneven time forever as
# systemd-timesyncd pushes or pulls at whatever interval it thinks the near-term drift requires. It also can't assess the
# quality of the remote time source. You're unlikely to get accuracy much greater than 100ms. This is sufficient for simple
# end user devices like laptops, but it could definitely cause problems for distributed systems that want greater time precision.
# (source article: https://unix.stackexchange.com/questions/305643/ntpd-vs-systemd-timesyncd-how-to-achieve-reliable-ntp-syncing/464729#464729 )
#
# So install_ntp() disables "systemd-timesyncd" and leaves only "ntpd".
#
# Return value: 0 = success, 1 = failure
#
# Note: f-n also uses set_state()
#
function replace_timesyncd_with_ntpd {

    # Check if timesyncd is active (disable if active)
    IS_TIMESYNCD_ACTIVE=$( systemctl status systemd-timesyncd.service | grep -i active | awk '{print $2}' )  # returns 'active' or 'inactive'

    # Have to commend out the "if" statement below. Here's the reason why:
    #   Noted IBM agents, where "timedatectl status" still reports non-ntpd time syncing is in place: "Network time on: yes"
    #   BUT AT THE SAME TIME the "systemctl status systemd-timesyncd.service" output shows "Active: inactive (dead)"
    #   and only after we run "sudo timedatectl set-ntp no" the output of "timedatectl status" will be finally expected: "Network time on: no"
    #
    # if [ "${IS_TIMESYNCD_ACTIVE}" == "active" ]; then

        # timesyncd is active, need to deactivate it:
        sudo timedatectl set-ntp no

        # make sure timedatectl is not not active
        IS_TIMESYNCD_ACTIVE=$( systemctl status systemd-timesyncd.service | grep -i active | awk '{print $2}' )  # returns 'active' or 'inactive'
        if [ "${IS_TIMESYNCD_ACTIVE}" == "active" ]; then
            # Still active! Error out
            set_state "${FUNCNAME[0]}" 'failed_stop_timesyncd'
            return 1
        fi

    #fi

    # Check if ntpd is insatalled (install if missing)
    IS_NTP_INSTALLED=$( dpkg --get-selections ntp | grep -v deinstall | grep install | awk '{print $2}' )  # returns 'install' if is installed or emptry string if not
    if [ "${IS_NTP_INSTALLED}" != "install" ]; then
        # ntp is not installed, install it
        apt_install ntp

        # Check if ntp is now installed
        IS_NTP_INSTALLED=$( dpkg --get-selections ntp | grep -v deinstall | grep install | awk '{print $2}' )  # returns 'install' if is installed or emptry string if not
        if [ "${IS_NTP_INSTALLED}" != "install" ]; then
            # Still not isntalled! Error out
            set_state "${FUNCNAME[0]}" 'failed_install_ntp'
            return 1
        fi
    fi

    # Enble NTP (this will make it to autostart on reboot)
    sudo systemctl enable ntp
    if [ $? -ne 0 ]; then
        set_state "${FUNCNAME[0]}" 'failed'
    fi

    # Start NTP (note: it is safe to try to start in case it is already running - this might happen if ntp was not installed and was just added 1st time by apt)
    sudo systemctl start ntp
    if [ $? -ne 0 ]; then
        set_state "${FUNCNAME[0]}" 'failed'
    fi

    # Last status check: query local ntpd
    LOCAL_NTP_QUERY_STATUS=$( ntpq -pn )
    LOCAL_NTP_QUERY_STATUS_EXIT_CODE=$?

    if [ ${LOCAL_NTP_QUERY_STATUS_EXIT_CODE} -ne 0 ]; then
        set_state "${FUNCNAME[0]}" 'failed'
        return 1
    fi

    set_state "${FUNCNAME[0]}" 'success'
    return 0
}

###############################################################################
#
# Install ff_bash_functions -> ff_agent/lib/bash/
# On success: return 0
# On error f-n sets state and return nonzero value.
# Depend on:
#   AGENT_HOME variable
#   current directory "./" should be root of "set_environment" project.
#
function install_ff_bash_functions {
    set_state "${FUNCNAME[0]}" 'started'

    # Check ${AGENT_HOME} is set
    if [ -z "${AGENT_HOME}" ]; then
        # Error: required environment variable AGENT_HOME is not set.
        set_state "${FUNCNAME[0]}" 'error_required_variable_not_set_agent_home'
        return 1
    fi

    # Check if target folder exists
    TARGET_DIR="${AGENT_HOME}/lib/bash"
    if [ ! -d "${TARGET_DIR}" ]; then
        # Desitnation folder doesn't exist, try to create
        mkdir -p "${TARGET_DIR}"
        if [ ${?} -ne 0 ]; then
            # Error: failed to create folder
            set_state "${FUNCNAME[0]}" 'error_failed_create_folder'
            return 1
        fi
    fi

    # Copy files to the target folder
    assert_clean_exit sudo cp ./src/ff_bash_functions "${TARGET_DIR}"
    # Disabling this nasty hack: we no longer grep output, instad we use ". install.sh" technique
    # echo "export FF_BASH_FUNCTIONS_PATH=${TARGET_DIR}"

    set_state "${FUNCNAME[0]}" 'success'
    return 0
}

###############################################################################
#
# The purpose of install_ff_agent_bashrc() is to create a new .bashrc file
# which will be 100% our responsibility/ownership and inject 1-liner to source
# that file from the standard linux .bashrc file.
#
# The logic of this function can be described by the following steps:
#    - checks required environment variables are set
#    - creates "custom" .bashrc under ff_agent folder (if missing) 
#    - changes "custom" .bashrc ownership to the BEST_USER_TO_RUN_AS 
#    - injects 1-liner to source "custom" .bashrc from "standard" .bashrc (if missing)
#
function install_ff_agent_bashrc {
  set_state "${FUNCNAME[0]}" 'started'

  # Check required environment variables
  if [ -z "${BEST_USER_TO_RUN_AS}" ]; then
  	set_state "${FUNCNAME[0]}" "error_environment_not_set_best_user_to_run_as"
    return 1
  fi
  if [ -z "${AGENT_HOME_DIR}" ]; then
  	set_state "${FUNCNAME[0]}" "error_environment_not_set_agent_home_dir"
    return 1
  fi
  if [ -z "${AGENT_HOME}" ]; then
  	set_state "${FUNCNAME[0]}" "error_environment_not_set_agent_home"
    return 1
  fi
  
  # Make sure ${AGENT_HOME} folder exist
  if [ ! -d "${AGENT_HOME}" ]; then
      # Create new folder if missing
      mkdir -p "${AGENT_HOME}"
      if [ ${?} -ne 0 ]; then
          # Failed to create ${AGENT_HOME} - report error() and abort()
          error "Did not find AGENT_HOME directory at ${AGENT_HOME}. Tried to create it but failed. Aborting."
          abort
      fi
  fi

  # XXX - TODO - the code in .bashrc and .profile should be the same. This is duplicating code for nothing.
  # ---------------------------------------- .bashrc (begin) --------------------
  # Define location of two .bashrc files
  # XXX TODO - - why are these being exported? They are not deleted after this step and pollute the namespace
  export STD_BASHRC_FILE="${AGENT_HOME_DIR}/.bashrc"    # example: /home/ubuntu/.bashrc
  export FF_AGENT_BASHRC_FILE="${AGENT_HOME}/.bashrc"   # example: /home/ubuntu/ff_agent/.bashrc

  # Create "custom" .bashrc if missing
  if [ ! -f "${FF_AGENT_BASHRC_FILE}" ]; then
    sudo touch "${FF_AGENT_BASHRC_FILE}" || { set_state "${FUNCNAME[0]}" "error_creating_custom_bashrc"; return 1; }
    echo "# Custom ff_agent .bashrc file (created by set_environment -> ff_bash_functions -> ${FUNCNAME[0]} on $(date --utc))" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" > /dev/null
    sudo chown "${BEST_USER_TO_RUN_AS}:$(id -gn ${BEST_USER_TO_RUN_AS})" "${FF_AGENT_BASHRC_FILE}" || { set_state "${FUNCNAME[0]}" "error_chown_custom_bashrc"; return 1; }
  fi

  # Inject 1-liner into standard ~/.bashrc to source custom ff_agent/.bashrc
  grep --quiet "${FF_AGENT_BASHRC_FILE}" "${STD_BASHRC_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing. Inject it
    echo -e "\n# Sourcing custom ff_agent/.bashrc file (injected by set_environment -> ff_bash_functions -> ${FUNCNAME[0]} on $(date --utc))\nsource \"${FF_AGENT_BASHRC_FILE}\"" >> "${STD_BASHRC_FILE}" || {
      set_state "${FUNCNAME[0]}" 'error_inject_to_ff_agent_profile'; return 1; 
    }
  fi
  # ---------------------------------------- .bashrc (end) --------------------

  # ---------------------------------------- .profile (begin) --------------------
  # Define location of two .bashrc files
  export STD_PROFILE_FILE="${AGENT_HOME_DIR}/.profile"    # example: /home/ubuntu/.profile
  export FF_AGENT_PROFILE_FILE="${AGENT_HOME}/.profile"   # example: /home/ubuntu/ff_agent/.profile

  # Create "custom" .profile if missing
  if [ ! -f "${FF_AGENT_PROFILE_FILE}" ]; then
    sudo touch "${FF_AGENT_PROFILE_FILE}" || { set_state "${FUNCNAME[0]}" "error_creating_custom_profile"; return 1; }
    echo "# Custom ff_agent .profile file (created by set_environment -> ff_bash_functions -> ${FUNCNAME[0]} on $(date --utc))" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" > /dev/null
    sudo chown "${BEST_USER_TO_RUN_AS}:$(id -gn ${BEST_USER_TO_RUN_AS})" "${FF_AGENT_PROFILE_FILE}" || { set_state "${FUNCNAME[0]}" "error_chown_custom_profile"; return 1; }
  fi

  # Inject 1-liner into standard ~/.profile to source custom ff_agent/.profile
  grep --quiet "${FF_AGENT_PROFILE_FILE}" "${STD_PROFILE_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing. Inject it
    echo "" >> "${STD_PROFILE_FILE}"
    echo "# Sourcing custom ff_agent/.profile file (injected by set_environment -> ff_bash_functions -> ${FUNCNAME[0]} on $(date --utc))" >> "${STD_PROFILE_FILE}"
    echo "source \"${FF_AGENT_PROFILE_FILE}\"" >> "${STD_PROFILE_FILE}"
  fi

  # Path to the installed ff_bash_functions
  FF_BASH_FUNCTIONS_INSTALLED_PATH="${AGENT_HOME}/lib/bash/ff_bash_functions"

  # Inject 1-liner into custom .profile to source ff_bash_functions (if missing)
  # Search expected 1-liner
  grep --quiet "${FF_BASH_FUNCTIONS_INSTALLED_PATH}" "${FF_AGENT_PROFILE_FILE}"
  if [ ${?} -ne 0 ]; then
    # Line is missing, add it
    echo "" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" >/dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
    echo "# Sourcing bash functions library from ${FF_BASH_FUNCTIONS_INSTALLED_PATH} (added by set_environment -> ff_bash_functions -> ${FUNCNAME[0]} on $(date --utc))" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" >/dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
    echo "source ${FF_BASH_FUNCTIONS_INSTALLED_PATH}" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" >/dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
    
    # Inject functions calls from ff_bash_function to set all the required env variables
    echo "discover_environment" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" > /dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
  fi

  # Also inject same lines into custom bashrc file
  grep --quiet "${FF_BASH_FUNCTIONS_INSTALLED_PATH}" "${FF_AGENT_BASHRC_FILE}"
  if [ ${?} -ne 0 ]; then
    # Line is missing, add it
    echo "" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" >/dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
    echo "# Sourcing bash functions library from ${FF_BASH_FUNCTIONS_INSTALLED_PATH} (added by set_environment -> ff_bash_functions -> ${FUNCNAME[0]} on $(date --utc))" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" >/dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
    echo "source ${FF_BASH_FUNCTIONS_INSTALLED_PATH}" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" >/dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
    
    # Inject functions calls from ff_bash_function to set all the required env variables
    echo "discover_environment" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" > /dev/null || { set_state "${FUNCNAME[0]}" "error_writing_to_custom_profile"; return 1; }
  fi
  # ---------------------------------------- .profile (end) --------------------
    
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

    # Check ${AGENT_HOME} is set
    if [ -z "${AGENT_HOME}" ]; then
      # Error: required environment variable AGENT_HOME is not set.
      set_state "${FUNCNAME[0]}" 'error_required_variable_not_set_agent_home'
      return 1
    fi

    cd "${AGENT_HOME}" || { set_state "${FUNCNAME[0]}" 'terminal_error_changedir_agent_home'; abort; }
    npm init -y        || { set_state "${FUNCNAME[0]}" 'terminal_error_initializing_npm_project'; abort; }
    
    # Define the version of ff_agent npm package to install from CDN
    VERSION='latest'
    
    # Install ff_agent
    npm install "${CONTENT_URL}/ff/npm/ff-ff_agent-${VERSION}.tgz" || { set_state "${FUNCNAME[0]}" 'terminal_error_failed_to_install_ff_agent'; abort; }

    set_state "${FUNCNAME[0]}" 'success'
    return 0
}

###############################################################################
#
# Install standard nodejs latest environment
function install_nodejs_suite {
    set_state "${FUNCNAME[0]}" 'started'

    fix_pre_existing_npm_permissions_ubuntu || { set_state "${FUNCNAME[0]}" 'terminal_error_fixing_npm_permissions'; abort; }
    install_node_ubuntu                     || { set_state "${FUNCNAME[0]}" 'terminal_error_install_node'; abort; }
    install_required_npm_libraries          || { set_state "${FUNCNAME[0]}" 'terminal_error_install_required_npm_libraries'; abort; }

    set_state "${FUNCNAME[0]}" 'success'
    return 0
}

###############################################################################
#
# After install_node_ubuntu() reinstalled npm using "n" we need to put back in place some of the npm modules installed earlierput back in place some of the npm modules installed earlier.
# Old location:
#   /usr/local/lib/node_modules
# New location:
#   /home/ubuntu/ff_agent/.n/lib/node_modules
function install_required_npm_libraries {
  set_state "${FUNCNAME[0]}" 'started'

  # Flush prior knowledge about npm packages (we move whole node/npm suite installation inside ff_agent/.n)
  npm cache clear --force  || { set_state "${FUNCNAME[0]}" "error_npm_cache_clear"; return 1; }

  # Install required packages
  npm install --global commander  || { set_state "${FUNCNAME[0]}" "error_npm_install_commander"; return 1; }
  npm install --global casperjs   || { set_state "${FUNCNAME[0]}" "error_npm_install_casperjs"; return 1; }
  npm install --global jsontool   || { set_state "${FUNCNAME[0]}" "error_npm_install_jsontool"; return 1; }
  npm install --global slimerjs   || { set_state "${FUNCNAME[0]}" "error_npm_install_slimerjs"; return 1; }
  npm install --global typescript || { set_state "${FUNCNAME[0]}" "error_npm_install_typescript"; return 1; }

  # Chage state and return success
  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
# Dependencies: 
#   AGENT_HOME_DIR
#   BEST_USER_TO_RUN_AS
function fix_pre_existing_npm_permissions_ubuntu {
    set_state "${FUNCNAME[0]}" 'started'

    # Check dependency environment is set
    [ -z "${AGENT_HOME_DIR}" ] && { set_state "${FUNCNAME[0]}" "error_environment_not_set_agent_home_dir"; return 1; }
    [ -z "${BEST_USER_TO_RUN_AS}" ] && { set_state "${FUNCNAME[0]}" "error_environment_not_set_best_user_to_run_as"; return 1; }
        
    # This is a fix for previous sins we comitted with permissions. It tries to align permissions properly going forward
    # Note: on agents we can't install npm's as ubuntu unless this is fixed
    local FIX_OWNERSHIP_PATHS=(
        ${AGENT_HOME_DIR}/.npm
        ${AGENT_HOME_DIR}/.npmrc
        ${AGENT_HOME_DIR}/.config
        ${AGENT_HOME_DIR}/.cache
    )

    for FIX_OWNERSHIP_PATH in ${FIX_OWNERSHIP_PATHS[@]}; do 
        # Note: the '-e' test will check if file OR directory exists
        [ -e "${FIX_OWNERSHIP_PATH}" ] && sudo chown -R "${BEST_USER_TO_RUN_AS}:$(id -gn ${BEST_USER_TO_RUN_AS})" "${FIX_OWNERSHIP_PATH}"
    done

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
            export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${AGENT_HOME_DIR}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
            [ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"
            nvm install lts/*
        ;;
        n)
            # # We need to stop pm2 before replacing location of nodejs, otherwise any pm2 command would faild
            # stop_pm2
            #uninstall_n_outside_agent_home  || { set_state "${FUNCNAME[0]}" 'terminal_error_uninstall_n_outside_agent_home'; abort; }
            install_n || { set_state "${FUNCNAME[0]}" 'terminal_error_install_n'; abort; }
            n install "${VERSION}" || { set_state "${FUNCNAME[0]}" 'terminal_error_switching_node_version'; abort; }
        ;;
    esac

    set_state "${FUNCNAME[0]}" 'success'
    return 0
}

# Commented out - we only add local n/npm/node installation without removing anything existing.
# ###############################################################################
# #
# # This function uninstalls any 'n' and/or 'npm' installled outside ff_agent home directory.
# #
# # Most of the ways to uninstall 'n' implemented here were picked from 
# # official 'n' github bug tracker: "How to uninstall n? #169"
# # https://github.com/tj/n/issues/169
# #
# function uninstall_n_outside_agent_home {
#   set_state "${FUNCNAME[0]}" "uninstalling"

#   # Call 'uninstall' on 'n' itself. n uninstall has been added in v4.1.0.
#   if [ "$(which n | grep -v "${AGENT_HOME}")" != "" ]; then
#     echo "y" | sudo n uninstall
#   fi

#   # Example output:
#   #    Uninstalling node and npm
#   #    /usr/local/bin/node
#   #    /usr/local/bin/npm
#   #    /usr/local/bin/npx
#   #    /usr/local/include/node
#   #    /usr/local/lib/node_modules/npm
#   #    /usr/local/share/doc/node
#   #    /usr/local/share/man/man1/node.1
#   #    /usr/local/share/systemtap/tapset/node.stp

#   # Uninstall 'n' if it was installed under "/usr" using "npm install --global n"
#   WHICH_NPM="$(which npm)"
#   if [ "${WHICH_NPM}" != "" ]; then
#     # Only uninstall if npm installed under /user
#     if [[ "${WHICH_NPM}" =~ ^/usr/ ]]; then
#       npm r -g n
#     fi
#   fi

#   # Remove n node_modules
#   if [ -d /usr/local/lib/node_modules/n ]; then
#     echo "removing /usr/local/lib/node_modules/n"
#     sudo rm -fr /usr/local/lib/node_modules/n
#   fi

#   # Remove n cache
#   if [ -d /usr/local/n ]; then
#     sudo rm -rf /usr/local/n
#   fi

#   # Remove n (if file exists)
#   if [ -f /usr/local/bin/n ]; then
#     sudo rm -fr /usr/local/bin/n
#   fi

#   # Remove n (if symlink exists)
#   if [ -L /usr/local/bin/n ]; then
#     sudo rm -fr /usr/local/bin/n
#   fi

#   # Remove n (if file exists) from other possible location
#   if [ -f /usr/bin/n ]; then
#     sudo rm -fr /usr/bin/n
#   fi

#   # Remove standard "global" npm libraries folder
#   if [ -d /usr/lib/node_modules ]; then
#     sudo rm -fr /usr/lib/node_modules
#   fi

#   # Also on agent nodejs was installed via apt:
#   # sudo apt remove -y nodejs
#   DPGK_NODEJS_CHECK="$(dpkg --get-selections | grep nodejs | grep '[[:space:]]install$')"
#   if [ ! -z "${DPGK_NODEJS_CHECK}" ]; then
#     sudo DEBIAN_FRONTEND=noninteractive apt-get -oDpkg::Options::="--force-confold" -yq -o Acquire::ForceIPv4=true remove nodejs
#   fi

#   # Chage state and return success
#   set_state "${FUNCNAME[0]}" 'success'
#   return 0
# }

###############################################################################
#
# Installations of "n" based on the tutorial:
#  "Getting started with n (node version management)"
#   https://zacharytodd.com/posts/n-version-manager/
# 
# Official n github page:
#   https://github.com/tj/n
#   https://github.com/tj/n#installation
#
function install_n {
  set_state "${FUNCNAME[0]}" "installing"

  # Check the required environment variables are set
  if [ -z "${FF_AGENT_BASHRC_FILE}" ]; then
  	set_state "${FUNCNAME[0]}" "error_environment_not_set_ff_agent_bashrc_file"
    return 1
  fi

  if [ -z "${FF_AGENT_PROFILE_FILE}" ]; then
  	set_state "${FUNCNAME[0]}" "error_environment_not_set_ff_agent_profile_file"
    return 1
  fi

  if [ -z "${AGENT_HOME}" ]; then
  	set_state "${FUNCNAME[0]}" "error_environment_not_set_agent_home"
    return 1
  fi

  # Check custom .bashrc file exists
  if [ ! -f "${FF_AGENT_BASHRC_FILE}" ]; then
    # Let's not try to re-create it if missing.
    # It should have been created by existing f-n install_ff_agent_bashrc() (defined in project: "set_environment", see file: src/ff_bash_functions)
  	set_state "${FUNCNAME[0]}" "error_custom_ff_agent_bashrc_does_not_exist"
    return 1
  fi

  # Check custom .profile file exists
  if [ ! -f "${FF_AGENT_PROFILE_FILE}" ]; then
    # Let's not try to re-create it if missing.
    # It should have been created by existing f-n install_ff_agent_bashrc() (defined in project: "set_environment", see file: src/ff_bash_functions)
  	set_state "${FUNCNAME[0]}" "error_custom_ff_agent_profile_does_not_exist"
    return 1
  fi

  # Create tmp folder and change directory into it
  TMPDIR="$( mktemp -d )"
  PREVIOUS_DIR="$( pwd )"
  cd "${TMPDIR}" || { set_state "${FUNCNAME[0]}" 'error_chdir_to_tmp_directory'; return 1; }

  # Attempt 1: download 'n' from CONTENT_URL server
  # We do "CONTENT_URL server first" because it gives more control over what version of 'n' will be executed.
  # The magour update on the github might introduce some breaking change, let's leave it for 2nd attept only.
  SAVE_AS='n'
  URL="${CONTENT_URL}/ff/ff_agent/hotpatch/hotpatch_files/${SAVE_AS}"
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
        # 2nd attempt failed too, giving up
        set_state "${FUNCNAME[0]}" 'warning_failed_to_download_n_from_github'
        # Clean up tmp folder
        cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
        return 1
      fi      
  fi

  # Export 2 env variables we need for "n" to operate properly: N_PREFIX and NODE_PATH
  export N_PREFIX="${AGENT_HOME}/.n"  # example: /home/ubuntu/ff_agent/.n
  # We set NODE_PATH, so npm can load modules from "non-standard place". Details: https://stackoverflow.com/questions/12594541/npm-global-install-cannot-find-module
  export NODE_PATH="${AGENT_HOME}/.n/lib/node_modules"

  # Update PATH variable (if it not yet contains ff_agent/.n path)
  echo "${PATH}" | grep --quiet 'ff_agent/.n'
  if [ ${?} -ne 0 ]; then
    export PATH="${N_PREFIX}/bin:$PATH"
  fi

  # Add '# Export N_PREFIX' into custom .profile file if in was not injected earlier.
  # TODO: add into ff_bash_funcitons a function to add/edit/remove our custom profile file.
  EXPECTED_LINE="export N_PREFIX=\"${AGENT_HOME}/.n\""
  grep --quiet "${EXPECTED_LINE}" "${FF_AGENT_PROFILE_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing, inject it
    echo -e "# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)\n${EXPECTED_LINE}" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" > /dev/null || {
        # Clean up tmp folder
        cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
        set_state "${FUNCNAME[0]}" 'error_inject_to_ff_agent_profile'; return 1; 
    }
  fi

  # Also: Inject same lines into custom .bashrc
  grep --quiet "${EXPECTED_LINE}" "${FF_AGENT_BASHRC_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing, inject it
    echo -e "# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)\n${EXPECTED_LINE}" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" > /dev/null || {
        # Clean up tmp folder
        cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
        set_state "${FUNCNAME[0]}" 'error_inject_to_ff_agent_profile'; return 1; 
    }
  fi
  
  # Add '# Export NODE_PATH' into custom .profile file if in was not injected earlier.
  # TODO: add into ff_bash_funcitons a function to add/edit/remove our custom profile file.
  EXPECTED_LINE="export NODE_PATH=\"${AGENT_HOME}/.n/lib/node_modules\""
  grep --quiet "${EXPECTED_LINE}" "${FF_AGENT_PROFILE_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing, inject it
    echo -e "# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)\n${EXPECTED_LINE}" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" > /dev/null || {
        # Clean up tmp folder
        cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
        set_state "${FUNCNAME[0]}" 'error_inject_to_ff_agent_profile'; return 1; 
    }
  fi

  # Also: Inject same lines into custom .bashrc
  EXPECTED_LINE="export NODE_PATH=\"${AGENT_HOME}/.n/lib/node_modules\""
  grep --quiet "${EXPECTED_LINE}" "${FF_AGENT_BASHRC_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing, inject it
    echo -e "# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)\n${EXPECTED_LINE}" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" > /dev/null || {
        # Clean up tmp folder
        cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
        set_state "${FUNCNAME[0]}" 'error_inject_to_ff_agent_profile'; return 1; 
    }
  fi

  # Inject PATH to "ff_agent/.n/bin"
  # Note: we escape "\$" infront of the PATH, so it does not get expanded
  EXPECTED_LINE="export PATH=${N_PREFIX}/bin:\$PATH"
  grep --quiet "${EXPECTED_LINE}" "${FF_AGENT_PROFILE_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing, inject it
    echo -e "# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)\n${EXPECTED_LINE}" | sudo tee -a "${FF_AGENT_PROFILE_FILE}" > /dev/null || { 
      # Clean up tmp folder
      cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
      set_state "${FUNCNAME[0]}" 'error_inject_to_ff_agent_profile'; return 1; 
    }
  fi

  # Also: Inject same lines into custom .bashrc
  EXPECTED_LINE="export PATH=${N_PREFIX}/bin:\$PATH"
  grep --quiet "${EXPECTED_LINE}" "${FF_AGENT_BASHRC_FILE}"
  if [ ${?} -ne 0 ]; then
    # Expected line is missing, inject it
    echo -e "# Injected by set_environment ${FUNCNAME[0]} on $(date --utc)\n${EXPECTED_LINE}" | sudo tee -a "${FF_AGENT_BASHRC_FILE}" > /dev/null || { 
      # Clean up tmp folder
      cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
      set_state "${FUNCNAME[0]}" 'error_inject_to_ff_agent_profile'; return 1; 
    }
  fi

  # Install 'npm' using dowloaded into TMPDIR 'n' ('npm' will be installed into ff_agent/.n)
  bash n lts || { 
    # Clean up tmp folder
    cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
    set_state "${FUNCNAME[0]}" 'error_installing_npm'; return 1; 
  }

  # Install 'n' into ff_agent/.n  (yes, we have downloaded 'n' into TMPDIR,
  # then used it to install 'npm', and now we use 'npm' to install "globally" n.
  # The proper installed 'n' will reisde under ff_agent/.n/ folder)
  npm install --global n || { 
    # Clean up tmp folder
    cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"
    set_state "${FUNCNAME[0]}" 'error_installing_n'; return 1; 
  }

  # Clean up tmp folder
  cd "${PREVIOUS_DIR}" ; rm -fr "${TMPDIR}"

  # Chage state and return success
  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
# After install_node_ubuntu() reinstalled npm using "n" we need to put back in place some of the npm modules installed earlier.
# Old location:
#   /usr/local/lib/node_modules
# New location:
#   /home/ubuntu/ff_agent/.n/lib/node_modules
function install_required_npm_libraries {
  set_state "${FUNCNAME[0]}" 'started'

  # Flush prior knowledge about npm packages (we move whole node/npm suite installation inside ff_agent/.n)
  npm cache clear --force  || { set_state "${FUNCNAME[0]}" "error_npm_cache_clear"; return 1; }

  # Install required packages
  # XXX - TODO - None of these are needed I think. They are not in the spec. If a project needs them, it can put
  # them in, else, they can be part of other projects, like buildtools.
  # We also need to not isntall typescript here as baseline, it is only for the development environment
  npm install --global commander  || { set_state "${FUNCNAME[0]}" "error_npm_install_commander"; return 1; }
  npm install --global casperjs   || { set_state "${FUNCNAME[0]}" "error_npm_install_casperjs"; return 1; }
  npm install --global jsontool   || { set_state "${FUNCNAME[0]}" "error_npm_install_jsontool"; return 1; }
  npm install --global slimerjs   || { set_state "${FUNCNAME[0]}" "error_npm_install_slimerjs"; return 1; }
  npm install --global typescript || { set_state "${FUNCNAME[0]}" "error_npm_install_typescript"; return 1; }

  # Chage state and return success
  set_state "${FUNCNAME[0]}" 'success'
  return 0
}

###############################################################################
#
# Function installs docker. It takes 1 argement "minimum version", if not provided,
# then by default version 19 will be used.
#
# Supports Ubuntu 16.04, 18.04, 20.04
function install_docker {

    set_state "${FUNCNAME[0]}" 'started'

    # Check required environment variables are set
    # Check required environment variables
    if [ -z "${BEST_USER_TO_RUN_AS}" ]; then
        set_state "${FUNCNAME[0]}" "error_environment_not_set_best_user_to_run_as"
        return 1
    fi

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
    ID=$( get_lsb_id ) || { set_state "${FUNCNAME[0]}" "failed_to_get_lsb_id"; return 1; } # Ubuntu
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
    # XXX - todo, the docker group might not actually exist and should be checked.
    # We might not have sudo, so we should request command to be run.
    GROUP="docker"
    # Check if user is in this group. If not, add them
    if [ ! is_user_in_group "${BEST_USER_TO_RUN_AS}" "${GROUP}" ]; then
      # Not in group
      sudo usermod -aG "${GROUP}" "${BEST_USER_TO_RUN_AS}"
      if [ "${?}" != "0" ]; then set_state "${FUNCNAME[0]}" "failed_to_modify_docker_user_group"; return 1; fi
      # Now check that we actually are in the group. This will work in current shell because it reads the groups file directly
      [ ! is_user_in_group "${BEST_USER_TO_RUN_AS}" "${GROUP}" ] || { set_state "${FUNCNAME[0]}" "failed_postcondition_user_in_group"; return 1; }
    fi
    

    # Postcondition checks
    # Verify docker is properly set up
    # Note we are running via sudo, and if we added user to the ${GROUP} then it won't be applied in this shell.
    set_secret docker_release "$( sudo --user=${BEST_USER_TO_RUN_AS} docker --version )" || { set_state "${FUNCNAME[0]}" "failed_to_run_docker_to_get_release"; return 1; }
    set_secret docker_compose_release "$( sudo --user=${BEST_USER_TO_RUN_AS} docker-compose --version )" || { set_state "${FUNCNAME[0]}" "failed_to_run_docker_compose_to_get_release"; return 1; }

    # Check if installed docker version is less than minimally required
    if [ "$( get_installed_docker_version )" -lt "${MINIMUM_VERSION}" ]; then
    	set_state "${FUNCNAME[0]}" "failed_to_install_did_not_pass_version_check"
	    return 1
    fi

    set_state "${FUNCNAME[0]}" 'success'
}

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
#    - function prints "true" to stdout only if we need to background_install as "${BEST_USER_TO_RUN_AS}"
#    - function returns/prints nothing if no need to background install
#    - on error function aborts (no need to errorcheck by the caller)
#
#
# Dependency:
#   BEST_USER_TO_RUN_AS - must be set
#
function check_if_need_background_install () {

    # Check required environment variables are set
    [ "${BEST_USER_TO_RUN_AS}" != "" ] || { set_state "${FUNCNAME[0]}" 'terminal_error_getting_best_user_to_run_as'; abort; }

    # It might already exist, but not be writable due to chmod changes
    if [ ! -w "${AGENT_HOME}" ]; then
        # TODO: The ${USER} environment is NOT set when running as 'root' in docker. Improve this.
        error "AGENT_HOME at ${AGENT_HOME} is not writable by user ${USER}. Aborting."
        ls -l $AGENT_HOME/..
        abort
    fi

    DO_BACKGROUND_INSTALL=false

    # Suppose I'm not the best user, but I can sudo to become the best! e.g. If I am root - I'm not the best user.
    if [ "${USER}" != "${BEST_USER_TO_RUN_AS}" ]; then
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
      ## background_install "${BEST_USER_TO_RUN_AS}"
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
function background_install () {

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
    chown -R "${BEST_USER_TO_RUN_AS}:$(id -gn ${BEST_USER_TO_RUN_AS})" "${TEMP_DIR}"

    # Pass control to the newly created set_environment copy (run by the target user) and exit
    sudo --set-home --user="${USER_TO_RUN_AS}" bash -c "${TEMP_DIR}/set_environment/install.sh"
}

###############################################################################
#
function setup_logging () {
	set_script_logging 
}

###############################################################################
# Log this script stdout and err to a log file AND system logger
function set_script_logging () {

  # Note: we can not yet call "set_state" on that early stages
 	#set_state "${FUNCNAME[0]}" 'started'

  # Let's find a good directory for logs. This assumes zero knowledge.
  # The _best_ place for these logs would be in ${HOME}/ff_agent/logs -- if we can write to it we'll create it
  POTENTIAL_LOG_DIRECTORIES=( "${AGENT_HOME}/logs" /var/log/ff_agent /tmp/ff_agent/logs /tmp/ff_agent.$$/logs )

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
