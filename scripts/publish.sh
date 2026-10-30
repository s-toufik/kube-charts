#!/usr/bin/env bash
# Pushes every application chart whose Chart.yaml version is not in the registry yet.
# A published version is never overwritten: bump `version` in Chart.yaml to publish a change.
#   REGISTRY=oci://ghcr.io/<owner>/charts scripts/publish.sh
set -euo pipefail
cd "$(dirname "$0")/.."

HELM="${HELM:-helm}"
: "${REGISTRY:?set REGISTRY, e.g. oci://ghcr.io/s-toufik/charts}"

mkdir -p dist
for dir in charts/*/; do
  dir="${dir%/}"
  grep -q '^type: library' "$dir/Chart.yaml" && continue
  name="$(awk '/^name:/ {print $2}' "$dir/Chart.yaml")"
  version="$(awk '/^version:/ {print $2}' "$dir/Chart.yaml")"
  if "$HELM" show chart "$REGISTRY/$name" --version "$version" >/dev/null 2>&1; then
    echo "$name $version is already published"
    continue
  fi
  "$HELM" dependency build "$dir" >/dev/null
  "$HELM" package "$dir" --destination dist
  "$HELM" push "dist/$name-$version.tgz" "$REGISTRY"
  echo "published $REGISTRY/$name:$version"
done
