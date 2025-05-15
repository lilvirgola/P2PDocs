#!/usr/bin/env sh
set -e
export ERL_CRASH_DUMP=/dev/null
export ERL_AFLAGS="-noinput"
if [ -n "$ERL_NODE_NAME" ]; then
    NODE_NAME="$ERL_NODE_NAME"
else
    NODE_NAME="$(hostname)@$(hostname -i | awk '{print $1}')"
fi
echo "Starting distributed IEx node as ${NODE_NAME}"
exec elixir --name "${NODE_NAME}" --erl "-noshell -noinput" -S mix run --no-halt || {
  echo "Elixir node failed to start"
  exit 1
}