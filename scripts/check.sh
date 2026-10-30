#!/usr/bin/env bash
# Lints every chart, renders it with each of its ci/*-values.yaml files and checks the result
# against the Kubernetes schemas (and the CloudNativePG ones from the CRDs catalog).
#   scripts/check.sh            all charts
#   scripts/check.sh app        one chart
set -euo pipefail
cd "$(dirname "$0")/.."

HELM="${HELM:-helm}"
KUBECONFORM="${KUBECONFORM:-kubeconform}"
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
# Every chart renders with these, as the server sets them
GLOBALS=(--set global.domain=server.example.ts.net --set global.hostIP=100.64.0.1 --set global.timezone=UTC)

if (($#)); then
  charts=("$@")
else
  charts=()
  for dir in charts/*/; do dir="${dir%/}"; charts+=("${dir#charts/}"); done
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

for chart in "${charts[@]}"; do
  dir="charts/$chart"
  [[ -f "$dir/Chart.yaml" ]] || { echo "no chart $chart" >&2; exit 1; }
  if grep -q '^type: library' "$dir/Chart.yaml"; then
    echo "==> $chart (library, checked through the charts that use it)"
    continue
  fi
  echo "==> $chart"
  "$HELM" dependency build "$dir" >/dev/null
  "$HELM" lint --strict "$dir" "${GLOBALS[@]}"
  for values in "$dir"/ci/*-values.yaml; do
    [[ -f "$values" ]] || continue
    rendered="$out/$chart-$(basename "$values" .yaml).yaml"
    "$HELM" lint --strict "$dir" "${GLOBALS[@]}" -f "$values" >/dev/null
    "$HELM" template "$chart" "$dir" --namespace homelab "${GLOBALS[@]}" -f "$values" >"$rendered"
    "$KUBECONFORM" -strict -summary -schema-location default -schema-location "$CRD_SCHEMAS" "$rendered"
  done
done
echo "all charts OK"
