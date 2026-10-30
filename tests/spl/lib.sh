#!/usr/bin/env bash
# Shared helpers for the tests/spl scripts (sourced, not run). Dev only: they talk to the local
# wd2l-splunk container's REST API at 127.0.0.1:8089 and never print the admin password.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

# docker with Git Bash path conversion off, so container paths like /opt/splunk stay as they are.
dh_docker() { MSYS_NO_PATHCONV=1 docker "$@"; }
DH_CONTAINER=${DH_CONTAINER:-wd2l-splunk}
DH_APP=hl_data_health
DH_APP_DIR=/opt/splunk/etc/apps/$DH_APP
DH_MGMT=${DH_MGMT:-https://127.0.0.1:8089}
DH_PASS_FILE=${DH_PASS_FILE:-/c/Users/taylo/wd2l-splunk/secrets/splunk-admin-password}

# curl with admin credentials passed on stdin as a curl config, so they are not in argv or output.
dh_curl() {
  local p
  p=$(<"$DH_PASS_FILE")
  p=${p//\\/\\\\}
  p=${p//\"/\\\"}
  printf 'user = "admin:%s"\n' "$p" | curl -sk --config - "$@"
}

# dh_search '<SPL>' [output_mode]: run a search in the app's namespace, stream the results.
dh_search() {
  dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs/export" \
    -d "output_mode=${2:-csv}" --data-urlencode "search=$1"
}

# dh_hec_health: wd2l's HEC must stay healthy after anything that touches splunkd.
dh_hec_health() {
  curl -sk https://127.0.0.1:8088/services/collector/health
  echo
}

# Host path for docker cp (Git Bash hands docker.exe a Windows path).
dh_hostpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}
