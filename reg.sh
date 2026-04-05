#!/usr/bin/env bash
set -e

GC_BASE=http://localhost:8000
USERNAME=admin
PASSWORD=Password@1

NAME=$1
CONFIG=${2:-default}
GROUPS=${3:-edge-1}

if [ -z "$NAME" ]; then
  echo "Usage: ./reg.sh <name> [config] [groups]" >&2
  exit 1
fi

LOGIN_PAYLOAD=$(jq -n \
  --arg u "$USERNAME" \
  --arg p "$PASSWORD" \
  '{"username": $u, "password": $p}')

LOGIN_RESP=$(curl -sf -X POST "$GC_BASE/login" \
  -H "Content-Type: application/json" \
  -d "$LOGIN_PAYLOAD")

TOKEN=$(echo "$LOGIN_RESP" | jq -r '.token // empty')

if [ -z "$TOKEN" ]; then
  echo "$LOGIN_RESP" >&2
  exit 1
fi

GROUPS_JSON=$(echo "$GROUPS" | jq -Rc 'split(",")')

SAT_PAYLOAD=$(jq -n \
  --arg name "$NAME" \
  --arg config "$CONFIG" \
  --argjson groups "$GROUPS_JSON" \
  '{"name": $name, "groups": $groups, "config_name": $config}')

RESP=$(curl -sf -X POST "$GC_BASE/api/satellites" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$SAT_PAYLOAD")

SAT_TOKEN=$(echo "$RESP" | jq -r '.token.token // .token // empty')

if [ -z "$SAT_TOKEN" ]; then
  echo "$RESP" >&2
  exit 1
fi

echo "$SAT_TOKEN"
