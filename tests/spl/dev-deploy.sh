#!/usr/bin/env bash
# Dev deploy: copy splunk/apps/hl_data_health into the local wd2l-splunk container and reload it.
# Swaps default/, metadata/default.meta and the shipped lookups; keeps local/, local.meta, other
# lookup files and the KV data. Reloads through the _reload endpoints; it never restarts splunkd
# (the role does a real install in task 3). Usage: tests/spl/dev-deploy.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/spl/lib.sh
. "$here/lib.sh"
repo=$(cd "$here/../.." && pwd)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
tar -C "$repo/splunk/apps" --exclude="$DH_APP/local" -cf - "$DH_APP" | tar -C "$stage" -xf -

dh_docker exec -u root "$DH_CONTAINER" rm -rf /tmp/hl_dh_stage
dh_docker cp "$(dh_hostpath "$stage/$DH_APP")" "$DH_CONTAINER:/tmp/hl_dh_stage"
# shellcheck disable=SC2016  # expanded inside the container
dh_docker exec -u root "$DH_CONTAINER" sh -ec '
  app=$1; st=/tmp/hl_dh_stage
  mkdir -p "$app/lookups" "$app/metadata"
  chmod -R u=rwX,go=rX "$st"
  for d in "$st"/*; do
    name=${d##*/}
    case $name in
      local) ;;
      lookups) cp -f "$d"/* "$app/lookups/" ;;
      metadata) cp -f "$d/default.meta" "$app/metadata/default.meta" ;;
      *) rm -rf "${app:?}/$name"; cp -a "$d" "$app/$name" ;;
    esac
  done
  chown -R splunk:splunk "$app"
  rm -rf "$st"
' sh "$DH_APP_DIR"

# Reload what this app ships. Each prints its HTTP code; anything but 200 is reported.
fail=0
# apps/local first: it registers a new app (and its KV collections) without a restart.
for ep in apps/local admin/conf-collections admin/macros admin/conf-macros saved/searches \
  admin/conf-savedsearches data/transforms/lookups admin/conf-transforms; do
  code=$(dh_curl -o "$stage/reload.out" -w '%{http_code}' -X POST "$DH_MGMT/services/$ep/_reload") || true
  echo "reload $ep: $code"
  case $code in 200 | 201) ;; *) fail=1 ;; esac
done
if [ "$fail" -ne 0 ]; then
  echo "dev-deploy: some reloads failed (see above); splunkd may be running stale config" >&2
  exit 1
fi
echo "deployed $DH_APP to $DH_CONTAINER"
