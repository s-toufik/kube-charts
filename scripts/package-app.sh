#!/usr/bin/env bash
# Builds an app's own chart: the generic `app` chart, renamed after the app, at the app's
# version, with the app's devops/helm/values.yml merged over its defaults. Prints the .tgz path.
#   scripts/package-app.sh <name> <version> <image repository> <values file> [out dir]
# APP_CHART / APP_CHART_VERSION pick the generic chart (default: the latest in the registry).
# Needs helm and yq (mikefarah, v4).
set -euo pipefail

name="${1:?name}" version="${2:?version}" image="${3:?image repository}" values="${4:?values file}"
out="${5:-dist}"
HELM="${HELM:-helm}"
APP_CHART="${APP_CHART:-oci://ghcr.io/s-toufik/charts/app}"
APP_CHART_VERSION="${APP_CHART_VERSION:-}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be X.Y.Z, got '$version'" >&2; exit 1; }
[[ -f "$values" ]] || { echo "no values file $values" >&2; exit 1; }
yq --version | grep -q 'version v4' || { echo "yq v4 (mikefarah) is required" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pull=("$HELM" pull "$APP_CHART" --untar --untardir "$work")
[[ -n "$APP_CHART_VERSION" ]] && pull+=(--version "$APP_CHART_VERSION")
"${pull[@]}" >/dev/null
chart="$work/$name"
mv "$work/app" "$chart"

base="$(yq '.version' "$chart/Chart.yaml")"
NAME="$name" VERSION="$version" BASE="$base" yq -i '
  .name = strenv(NAME) |
  .version = strenv(VERSION) |
  .appVersion = strenv(VERSION) |
  .description = strenv(NAME) + " on the homelab (built on the app chart " + strenv(BASE) + ")"
' "$chart/Chart.yaml"

# The app's values over the chart's defaults (maps merge, lists are replaced), then its image
yq eval-all '. as $item ireduce ({}; . * $item)' "$chart/values.yaml" "$values" >"$work/values.yaml"
IMAGE="$image" yq -i '.image.repository = strenv(IMAGE) | .image.tag = ""' "$work/values.yaml"
mv "$work/values.yaml" "$chart/values.yaml"

# The server provides these; any value is fine to check that the chart renders
"$HELM" lint --strict "$chart" --set global.domain=server.example.ts.net --set global.hostIP=100.64.0.1 >&2
"$HELM" template "$name" "$chart" --set global.domain=server.example.ts.net --set global.hostIP=100.64.0.1 >/dev/null

mkdir -p "$out"
"$HELM" package "$chart" --destination "$out" >&2
echo "$out/$name-$version.tgz"
