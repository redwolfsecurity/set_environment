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

  state_set "${FUNCNAME[0]}" 'started'

  # Initialize terminal
  terminal_initialize || { state_set "${FUNCNAME[0]}" "terminal_error_initialize_terminal"; abort 'terminal_error_initialize_terminal'; }

  # Enable bash call trace
  bash_call_trace_enable

  # Source OS-specific install functions to continue installation
  # Get this script directory
  SET_ENVIRONMENT_CONTINUE_INSTALL_SCRIPT_DIRECTORY="$( script_directory_get )"
  export SET_ENVIRONMENT_CONTINUE_INSTALL_SCRIPT_DIRECTORY
  # shellcheck disable=SC1091
  source "${SET_ENVIRONMENT_CONTINUE_INSTALL_SCRIPT_DIRECTORY}/continue_install.functions.sh" || { state_set "${FUNCNAME[0]}" "terminal_error_cant_source_os_specific_install_functions"; abort 'terminal_error_cant_source_os_specific_install_functions'; }

  # Set up logs for this script - part of continue install functions
  # Move to top part of installer maybe?
  # logging_script_set_deprecated || { state_set "${FUNCNAME[0]}" "terminal_error_failed_to_setup_logging"; abort 'terminal_error_failed_to_setup_logging'; }

  # discover the rest of environment
  discover_environment || { state_set "${FUNCNAME[0]}" "terminal_error_cant_discover_environment"; abort 'terminal_error_cant_discover_environment'; }

  # Project installer preserves the project source code: instead of erasing the source folder,
  # the code must be preserved under ff_agent/git/[project-owner]/set_environment/ folder.
  set_environment_preserve_source_code || { state_set "${FUNCNAME[0]}" "terminal_error_failed_to_set_environment_preserve_source_code"; abort 'terminal_error_failed_to_set_environment_preserve_source_code'; }

  # Install basic packages before installing anything else. This will install "curl", thus "state_set" will be able to POST JSON.
  assert_clean_exit apt_install_basic_packages

  # Ensure file "ff_agent/.profile" created and sourced from ~/.bashrc (Note: this must be done before install node)
  assert_clean_exit ff_agent_install_bashrc

  # Install nodejs suite and all its fixings (not using "apt") (Note: this will modify ff_agent/.profile)
  assert_clean_exit install_nodejs_suite

  # Install npm package "@ff/ff_agent"
  assert_clean_exit ff_agent_install

  # Install pm2, our process manager, npm globally
  assert_clean_exit pm2_install

  # Based on environment (host or container), start pm2 with ff_agent
  if [ -d /run/systemd/system ] && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    log "💻 Host system detected (systemd available) - Starting pm2 via systemd"
    assert_clean_exit pm2_configure_host
    assert_clean_exit pm2_update
    assert_clean_exit pm2_start
    assert_clean_exit ff_agent_run_pm2
    assert_clean_exit ff_agent_register_pm2_systemd
    pm2 save
  else
    log "📦 Container or non-systemd environment detected"
    assert_clean_exit pm2_configure_container
  fi

  # Install ecosystem.config.js for pm2 - dynamic loader to start ff_agent only
  # in dockerfile, pm2-runtime will start pm2 with this config file.
  # on host, we gotta do somethin different ;) - TBD (I still, even on host, want to use pm2 to use the ecosystem file)
  # But - we have to deal with the fact that host vs. docker are a bit of different processes below.

  # Install a script to update ff_agent and restart it by pm2
  assert_clean_exit ff_agent_update_install

  # Preserved "set environment" sources provide the installer linked by set_environment_install script, which must be in the PATH.
  set_environment_ensure_install_exists || { state_set "${FUNCNAME[0]}" "terminal_error_failed_to_set_environment_ensure_install_exists"; abort 'terminal_error_failed_to_set_environment_ensure_install_exists'; }

  # Last step: run a selfcheck
  set_environment_is_working || { state_set "${FUNCNAME[0]}" "terminal_error_selfcheck_failed"; abort 'terminal_error_selfcheck_failed'; }

  state_set "${FUNCNAME[0]}" 'success'
}

continue_install
