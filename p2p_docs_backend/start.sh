#!/usr/bin/env sh
set -e
export ERL_CRASH_DUMP=/dev/null
export ERL_AFLAGS="-noinput"

# Imposta nome nodo
if [ -n "$ERL_NODE_NAME" ]; then
    NODE_NAME="$ERL_NODE_NAME"
else
    NODE_NAME="$(hostname)@$(hostname -i | awk '{print $1}')"
fi

# Range fisso per la distribuzione Erlang
DISTRIBUTION_PORT=9000
ERL_DIST_FLAGS="-kernel inet_dist_listen_min ${DISTRIBUTION_PORT} inet_dist_listen_max ${DISTRIBUTION_PORT}"

echo "Starting distributed IEx node as ${NODE_NAME} on port ${DISTRIBUTION_PORT}"
exec elixir --name "${NODE_NAME}" \
    --cookie "p2pdocs" \
    --erl "${ERL_DIST_FLAGS}" \
    -S mix run --no-halt || {
  echo "Elixir node failed to start"
  exit 1
}
