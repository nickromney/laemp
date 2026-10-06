#!/usr/bin/env bash
# Suggest the Trivy image to pin in the Makefile's TRIVY_IMAGE.
#
# Picks the newest stable Trivy release that has been public for at least
# TRIVY_COOLDOWN_DAYS (default 7), skips the versions published by the March
# 2026 supply-chain compromise (GHSA-69fq-xp46-6x23), and prints its digest on
# Docker Hub and GHCR plus the cosign command that proves it was built by
# Trivy's own release workflow. It only prints; updating the pin is manual.
#
# Requires: gh, docker (buildx), and date (BSD or GNU).

set -euo pipefail

COOLDOWN_DAYS="${TRIVY_COOLDOWN_DAYS:-7}"
# Published by the attacker on 2026-03-19 and 2026-03-22; never pin these.
COMPROMISED_VERSIONS=(v0.69.4 v0.69.5 v0.69.6)

function epoch() {
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s
}

now="$(date -u +%s)"
cutoff=$((now - COOLDOWN_DAYS * 86400))
candidate=""

while IFS=$'\t' read -r tag published; do
  for bad in "${COMPROMISED_VERSIONS[@]}"; do
    [[ "${tag}" == "${bad}" ]] && continue 2
  done
  if (($(epoch "${published}") <= cutoff)); then
    candidate="${tag}"
    candidate_published="${published}"
    break
  fi
  echo "Skipping ${tag} (published ${published}, inside the ${COOLDOWN_DAYS}-day cooldown)" >&2
done < <(gh api 'repos/aquasecurity/trivy/releases?per_page=30' \
  --jq '.[] | select(.draft == false and .prerelease == false) | [.tag_name, .published_at] | @tsv' |
  sort -t$'\t' -k2 -r)

if [[ -z "${candidate}" ]]; then
  echo "Error: no Trivy release is past the ${COOLDOWN_DAYS}-day cooldown." >&2
  exit 1
fi

version="${candidate#v}"
hub_digest="$(docker buildx imagetools inspect "docker.io/aquasec/trivy:${version}" --format '{{.Manifest.Digest}}')"
ghcr_digest="$(docker buildx imagetools inspect "ghcr.io/aquasecurity/trivy:${version}" --format '{{.Manifest.Digest}}')"

if [[ "${hub_digest}" != "${ghcr_digest}" ]]; then
  echo "Error: Docker Hub (${hub_digest}) and GHCR (${ghcr_digest}) disagree for ${candidate}; do not pin." >&2
  exit 1
fi

cat <<EOF
Candidate: ${candidate} (published ${candidate_published}, cooldown ${COOLDOWN_DAYS} days)
Digest (Docker Hub and GHCR agree): ${hub_digest}

TRIVY_IMAGE ?= aquasec/trivy:${version}@${hub_digest}

Verify before pinning:
  cosign verify aquasec/trivy:${version}@${hub_digest} \\
    --certificate-identity-regexp '^https://github.com/aquasecurity/trivy/\\.github/workflows/.+@refs/tags/${candidate//./\\.}\$' \\
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
EOF
