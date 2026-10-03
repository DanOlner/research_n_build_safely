#!/bin/bash
# Start, use and stop this project's build container from the host.
#
#   ./container.sh build      build the image (the first build takes several minutes)
#   ./container.sh start      start the container and apply its firewall
#   ./container.sh claude     run Claude in the container, with permission checks skipped
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

# Ports to make reachable from your own machine, on localhost only, e.g. PUBLISH_PORTS="5173".
# Off by default: opening pages the agent wrote in your own browser runs its code on your
# machine, outside the container's firewall. The dev server must listen on 0.0.0.0 inside.
# Changing this needs ./container.sh stop, then start.
PUBLISH_PORTS="${PUBLISH_PORTS:-}"

running() { [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]; }

build() {
  docker build -t "$IMAGE" --build-arg TZ="${TZ:-Europe/London}" "$ROOT/build/.devcontainer"
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
  for d in research/notes build/.git build/.devcontainer build/.vscode; do
    [ -d "$ROOT/$d" ] || { echo "Missing $ROOT/$d" >&2; exit 1; }
  done
  docker image inspect "$IMAGE" >/dev/null 2>&1 || build
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  local ports=() p
  for p in $PUBLISH_PORTS; do ports+=(-p "127.0.0.1:$p:$p"); done
  docker run -d --name "$NAME" --hostname "$NAME" \
    --cap-add=NET_ADMIN --cap-add=NET_RAW \
    --env-file "$TOKEN_FILE" \
    --cpus="$CPUS" --memory="$MEMORY" --pids-limit="$PIDS" --shm-size="$SHM" \
    "${ports[@]}" \
    --mount type=volume,source="$NAME-claude",target=/home/node/.claude \
    -e CLAUDE_CONFIG_DIR=/home/node/.claude \
    --mount type=bind,source="$ROOT/build",target=/workspace \
    --mount type=bind,source="$ROOT/research/notes",target=/notes,readonly \
    --mount type=bind,source="$ROOT/build/.git",target=/workspace/.git,readonly \
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
  claude) running || start; docker exec -it -w /workspace "$NAME" claude --dangerously-skip-permissions "$@" ;;
  shell) running || start; docker exec -it -w /workspace "$NAME" zsh ;;
  firewall) running || { echo "$NAME is not running." >&2; exit 1; }; firewall ;;
  stop) stop ;;
  rebuild) stop; build; start ;;
  status) if running; then echo "$NAME is running."; else echo "$NAME is not running."; fi ;;
  name) echo "$NAME" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
