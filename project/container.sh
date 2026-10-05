#!/bin/bash
# Start, use and stop this project's build container from the host.
#
#   ./container.sh build      build the image (the first build takes several minutes), then run
#                             the container checks if its Claude Code version hasn't passed them
#   ./container.sh start      start the container and apply its firewall
#   ./container.sh claude     run Claude in the container, with permission checks skipped; first
#                             runs the container checks if they haven't passed on this version
#   ./container.sh shell      open a shell in the container
#   ./container.sh firewall   re-apply the firewall, refreshing the allowed sites' addresses
#   ./container.sh stop       stop and remove the container (the image and Claude's history are kept)
#   ./container.sh rebuild    stop, rebuild the image and start again
#   ./container.sh status     say whether the container is running
#   ./container.sh name       print the container name
#
# This script lives outside build/ on purpose: the agent can change anything in build/, so
# nothing the host runs should live there.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SLUG="$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_.-' '-' | sed 's/-*$//')"
NAME="${CONTAINER_NAME:-dual-$SLUG}"
IMAGE="dual-$SLUG:latest"
TOKEN_FILE="$HOME/.config/claude-container/token.env"

# Resource limits for the container. Shared memory is raised from Docker's 64 MB because
# Chromium crashes without more.
CPUS=4
MEMORY=8g
PIDS=1024
SHM=1g

# Ports to make reachable from your own machine, on localhost only: put them after the "-",
# e.g. PUBLISH_PORTS="${PUBLISH_PORTS-8000 8001}". Off by default: opening pages the agent wrote
# in your own browser runs its code on your machine, outside the container's firewall. The
# agent sees the list as $PUBLISH_PORTS, and its server must listen on 0.0.0.0 inside.
# Changing this needs ./container.sh stop, then start. check.py runs its own container with
# PUBLISH_PORTS set empty, so the two don't compete for the same ports.
PUBLISH_PORTS="${PUBLISH_PORTS-}"

running() { [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]; }

build() {
  # Install the same Claude Code version as on this machine. A new version also makes Docker redo
  # that step, rather than reusing a cached install of "latest".
  local version
  version="$(claude --version 2>/dev/null | cut -d' ' -f1)"
  docker build -t "$IMAGE" --build-arg TZ="${TZ:-Europe/London}" \
    --build-arg CLAUDE_CODE_VERSION="${version:-latest}" \
    --label claude_code_version="${version:-latest}" "$ROOT/build/.devcontainer"
  ensure_checked
}

# The Claude Code version in the image: from the label build() adds, or by asking the image.
image_version() {
  local version
  version="$(docker image inspect -f '{{index .Config.Labels "claude_code_version"}}' "$IMAGE" 2>/dev/null || true)"
  case "$version" in
    [0-9]*) echo "$version" ;;
    *) docker run --rm --entrypoint claude "$IMAGE" --version 2>/dev/null | cut -d' ' -f1 ;;
  esac
}

# Run the container checks once for each Claude Code version the image gets, and refuse to run
# Claude on a version that hasn't passed them.
ensure_checked() {
  local version tested
  version="$(image_version)"
  tested="$(sed -n 's/^tested_container=//p' "$ROOT/VERSION")"
  tested="${tested:-$(sed -n 's/^tested_claude_code=//p' "$ROOT/VERSION")}"
  if [ -n "$version" ] && [ "$version" = "$tested" ]; then return 0; fi
  echo "The image has Claude Code ${version:-of an unknown version}, which the container checks haven't passed yet (they last passed on ${tested:-no version}), so they're running once now: it takes about 20 seconds and a little of your usage, and makes sure the new version keeps the container's restrictions in place."
  if "$ROOT/check.py" --container-only --auto; then return 0; fi
  echo "The container checks didn't all pass, so Claude won't be started in this container. Fix the cause, then run ./check.py --container-only --accept." >&2
  return 1
}

# Say so when the running container is older than the current image.
note_old_image() {
  [ "$(docker inspect -f '{{.Image}}' "$NAME")" = "$(docker image inspect -f '{{.Id}}' "$IMAGE")" ] ||
    echo "This container started before the image was last rebuilt. To use the new image, exit Claude, then run ./container.sh stop and ./container.sh claude."
}

firewall() {
  local out
  if ! out=$(docker exec "$NAME" sudo /usr/local/bin/init-firewall.sh 2>&1); then
    echo "$out" | tail -5 >&2
    echo "Firewall setup failed, so the container has been removed." >&2
    docker rm -f "$NAME" >/dev/null
    exit 1
  fi
  echo "$out" | grep 'verification passed' || true
}

start() {
  if running; then echo "$NAME is already running."; return; fi
  [ -f "$TOKEN_FILE" ] || { echo "Missing $TOKEN_FILE. See 'Container login' in README.md." >&2; exit 1; }
  for d in research/notes build/.devcontainer build/.vscode; do
    [ -d "$ROOT/$d" ] || { echo "Missing $ROOT/$d" >&2; exit 1; }
  done
  docker image inspect "$IMAGE" >/dev/null 2>&1 || build
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  local ports=() p
  for p in $PUBLISH_PORTS; do ports+=(-p "127.0.0.1:$p:$p"); done
  # The git repository is the whole project folder, which the container never sees.
  # /workspace/.git and /workspace/.claude are empty read-only placeholders, so the agent can't
  # create a repository in build/ that git on the host would then use, or Claude Code settings
  # (which can define hooks) that a session on the host would load. The trust you give the
  # project covers build/ too. Docker leaves empty root-owned build/.git and build/.claude
  # folders on the host as the mount points; git ignores them.
  docker run -d --name "$NAME" --hostname "$NAME" \
    --cap-add=NET_ADMIN --cap-add=NET_RAW \
    --env-file "$TOKEN_FILE" \
    -e PUBLISH_PORTS="$PUBLISH_PORTS" \
    --cpus="$CPUS" --memory="$MEMORY" --pids-limit="$PIDS" --shm-size="$SHM" \
    "${ports[@]}" \
    --mount type=volume,source="$NAME-claude",target=/home/node/.claude \
    -e CLAUDE_CONFIG_DIR=/home/node/.claude \
    --mount type=bind,source="$ROOT/build",target=/workspace \
    --mount type=bind,source="$ROOT/research/notes",target=/notes,readonly \
    --mount type=tmpfs,target=/workspace/.git,readonly \
    --mount type=tmpfs,target=/workspace/.claude,readonly \
    --mount type=bind,source="$ROOT/build/.devcontainer",target=/workspace/.devcontainer,readonly \
    --mount type=bind,source="$ROOT/build/.vscode",target=/workspace/.vscode,readonly \
    -w /workspace -u node "$IMAGE" sleep infinity >/dev/null
  firewall
  echo "$NAME is running."
}

stop() {
  if docker rm -f "$NAME" >/dev/null 2>&1; then echo "$NAME stopped."; else echo "$NAME was not running."; fi
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift
case "$cmd" in
  build) build ;;
  start) start ;;
  claude)
    running || start
    ensure_checked || exit 1
    note_old_image
    docker exec -it -w /workspace "$NAME" claude --dangerously-skip-permissions "$@" ;;
  shell) running || start; docker exec -it -w /workspace "$NAME" zsh ;;
  firewall) running || { echo "$NAME is not running." >&2; exit 1; }; firewall ;;
  stop) stop ;;
  rebuild) stop; build; start ;;
  status) if running; then echo "$NAME is running."; else echo "$NAME is not running."; fi ;;
  name) echo "$NAME" ;;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
