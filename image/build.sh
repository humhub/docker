#!/usr/bin/env bash
# Build the HumHub image locally.
#
# Usage: ./build.sh [HUMHUB_REF] [IMAGE_TAG]
#
#   HUMHUB_REF  Branch or tag of humhub/humhub to build. Defaults to the ref
#               implied by the current docker branch, using the same mapping
#               as the nightly workflow:
#                 main      -> master
#                 develop   -> develop
#                 v<x>.<y>  -> v<x>.<y>   (maintenance branches)
#                 <other>   -> develop    (feature branches, detached HEAD)
#   IMAGE_TAG   Image tag to apply. Defaults to humhub:local, which is what
#               compose.yml runs.
#
# Environment:
#   PLATFORM    Target platform, e.g. linux/arm64. Defaults to the host platform.
#               One platform only; the result is loaded into the local image store.
#
# Examples:
#   ./build.sh                    # follow the current docker branch
#   ./build.sh v1.19.0            # build a release tag
#   ./build.sh master humhub:local-master
#   PLATFORM=linux/arm64 ./build.sh v1.19.0 humhub:local-arm64
#
# Prerequisites:
#   - Docker with BuildKit (default since Docker 23).
#   - Network access to github.com (HumHub clone, composer, npm).
#   - For a PLATFORM other than the host: QEMU user-mode emulation registered via
#     binfmt. Docker Desktop ships it; on Linux run once:
#       docker run --privileged --rm tonistiigi/binfmt --install arm64
#     Only the runtime stage is emulated (the builder stage is pinned to the host
#     platform), expect roughly 10x the native build time for that stage.
set -euo pipefail

cd "$(dirname "$0")"

DOCKER_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
case "$DOCKER_BRANCH" in
  main)         DEFAULT_REF="master" ;;
  develop)      DEFAULT_REF="develop" ;;
  v[0-9]*.[0-9]*) DEFAULT_REF="$DOCKER_BRANCH" ;;
  *)            DEFAULT_REF="develop" ;;
esac

HUMHUB_REF="${1:-$DEFAULT_REF}"
IMAGE_TAG="${2:-humhub:local}"
PLATFORM="${PLATFORM:-}"
HUMHUB_GIT_REVISION="$(git ls-remote https://github.com/humhub/humhub.git "refs/heads/$HUMHUB_REF" "refs/tags/$HUMHUB_REF" 2>/dev/null | head -n1 | cut -f1 || true)"

echo "docker branch: ${DOCKER_BRANCH:-<unknown>}"
echo "humhub ref:    $HUMHUB_REF ${HUMHUB_GIT_REVISION:+($HUMHUB_GIT_REVISION)}"
echo "image tag:     $IMAGE_TAG"
echo "platform:      ${PLATFORM:-<host>}"

docker build . \
  ${PLATFORM:+--platform "$PLATFORM"} \
  --build-arg HUMHUB_GIT_BRANCH="$HUMHUB_REF" \
  --build-arg HUMHUB_GIT_REVISION="$HUMHUB_GIT_REVISION" \
  --build-arg IMAGE_REVISION="$(git rev-parse HEAD 2>/dev/null || true)" \
  --build-arg IMAGE_CREATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg IMAGE_TAG="${IMAGE_TAG##*:}" \
  --tag "$IMAGE_TAG"
