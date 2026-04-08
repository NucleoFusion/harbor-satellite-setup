#!/usr/bin/env bash
set -e

HARBOR_URL=http://localhost:8888
USERNAME=admin
PASSWORD=Harbor12345

CLI_PATH=/home/nucleofusion/harbor-fix

SAT_PROJECT=satellites
MOCK_PROJECT=mock

GC_PATH=/home/nucleofusion/Programming/projects/satellite/ground-control
SAT_PATH=/home/nucleofusion/Programming/projects/satellite

GC_BASE=http://localhost:8000

MOCK_IMAGES=(
  nginx:latest
  alpine:latest
  redis:latest
  busybox:latest
)

# -------------------------------
# Harbor
# -------------------------------
login() {
  $CLI_PATH login $HARBOR_URL -u $USERNAME -p $PASSWORD
}

create_project() {
  PROJECT=$1

  echo "📦 Checking project: $PROJECT"

  if $CLI_PATH project list -o json | jq -e --arg name "$PROJECT" '.[] | select(.name == $name)' >/dev/null; then
    echo "♻️ Project $PROJECT exists"
  else
    $CLI_PATH project create "$PROJECT" --public --storage-limit 0
    echo "✅ Created $PROJECT"
  fi
}

docker_login() {
  echo "$PASSWORD" | docker login localhost:8888 -u $USERNAME --password-stdin
}

# -------------------------------
# Build + Push
# -------------------------------
build_internal() {
  echo "🔨 Building images..."
  docker build -t ground-control:dev "$GC_PATH"
  docker build -t satellite:dev "$SAT_PATH"
}

push_internal() {
  echo "🚀 Pushing internal images..."

  docker tag ground-control:dev localhost:8888/$SAT_PROJECT/ground-control:dev
  docker tag satellite:dev localhost:8888/$SAT_PROJECT/satellite:dev

  docker push localhost:8888/$SAT_PROJECT/ground-control:dev
  docker push localhost:8888/$SAT_PROJECT/satellite:dev
}

seed_mock() {
  echo "📦 Seeding mock images..."

  for IMAGE in "${MOCK_IMAGES[@]}"; do
    docker pull $IMAGE

    NAME=$(echo $IMAGE | cut -d':' -f1)
    TAG=$(echo $IMAGE | cut -d':' -f2)

    TARGET="localhost:8888/$MOCK_PROJECT/$NAME:$TAG"

    docker tag $IMAGE $TARGET
    docker push $TARGET
  done
}

# -------------------------------
# Ground Control
# -------------------------------
deploy_gc() {
  echo "📡 Deploying ground-control..."
  kubectl apply -k k8s/ground-control
}

wait_for_gc() {
  echo "⏳ Waiting for ground-control..." >&2
  until curl -sf -X POST "$GC_BASE/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"Password@1"}' >/dev/null 2>&1; do
    sleep 2
  done
  echo "✅ GC ready" >&2
}

gc_login() {
  echo "🔐 Logging into GC..." >&2

  RESP=$(curl -X POST "$GC_BASE/login" \
    -H "Content-Type: application/json" \
    -d '{
      "username": "admin",
      "password": "Password@1"
    }')

  echo "$RESP" | jq . >&2

  TOKEN=$(echo "$RESP" | jq -r '.token // empty')

  if [ -z "$TOKEN" ]; then
    echo "❌ Failed to login to GC" >&2
    exit 1
  fi

  echo "$TOKEN"
}

# -------------------------------
# Groups
# -------------------------------

create_groups() {
  local TOKEN=$1

  echo "📦 Creating groups..." >&2

  sync_group "$TOKEN" "edge-1" '{
    "group": "edge-1",
    "registry": "http://host.k3d.internal:8888",
    "artifacts": [
      { "repository": "mock/nginx", "tag": ["latest"], "type": "image" },
      { "repository": "mock/busybox", "tag": ["latest"], "type": "image" }
    ]
  }'

  sync_group "$TOKEN" "edge-2" '{
    "group": "edge-2",
    "registry": "http://host.k3d.internal:8888",
    "artifacts": [
      { "repository": "satellites/satellite", "tag": ["dev"], "type": "image" },
      { "repository": "mock/nginx", "tag": ["latest"], "type": "image" },
      { "repository": "mock/alpine", "tag": ["latest"], "type": "image" },
      { "repository": "mock/redis", "tag": ["latest"], "type": "image" }
    ]
  }'

  echo "🎉 Groups created" >&2
}

sync_group() {
  local TOKEN=$1
  local GROUP_NAME=$2
  local PAYLOAD=$3

  RESP=$(curl -s --max-time 10 -X POST "$GC_BASE/api/groups/sync" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD") || true

  echo "DEBUG $GROUP_NAME: $RESP" >&2
}

# -------------------------------
# Satellites
# -------------------------------
register_satellites() {
  local GC_TOKEN=$1
  echo "📡 Registering satellites..." >&2
  for i in 0 1 2; do
    local NAME="satellite-$i"
    local RESP TOKEN
    RESP=$(curl -s -X POST "$GC_BASE/api/satellites" \
      -H "Authorization: Bearer $GC_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$NAME\", \"groups\": [\"edge-1\"], \"config_name\": \"default\"}")
    echo "DEBUG $NAME: $RESP" >&2
    TOKEN=$(echo "$RESP" | jq -r '.token // empty')
    if [ -z "$TOKEN" ]; then
      echo "⚠️ $NAME may already exist, skipping..." >&2
      continue
    fi
    echo "✅ $NAME registered" >&2
    echo "$NAME=$TOKEN"
  done
}

create_default_config() {
  local TOKEN=$1

  echo "⚙️ Creating default config..." >&2

  RESP=$(curl -s --max-time 10 -X POST "$GC_BASE/api/configs" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"config_name": "default"}') || true

  echo "DEBUG config: $RESP" >&2
}

create_satellite_secret() {
  kubectl delete secret satellite-tokens --ignore-not-found
  local args=()
  for pair in "$@"; do
    args+=("--from-literal=$pair")
  done
  kubectl create secret generic satellite-tokens "${args[@]}"
}

deploy_satellites() {
  echo "🛰️ Deploying satellites..." >&2
  kubectl apply -f k8s/satellites/
  echo "✅ Satellites deployed" >&2
}

# -------------------------------
# Main
# -------------------------------
seed() {
  login

  create_project $SAT_PROJECT
  create_project "satellite"
  create_project $MOCK_PROJECT

  docker_login

  build_internal
  push_internal
  seed_mock

  deploy_gc
  wait_for_gc

  GC_TOKEN=$(gc_login)
  create_groups "$GC_TOKEN"
  create_default_config "$GC_TOKEN"
  mapfile -t TOKEN_ARRAY < <(register_satellites "$GC_TOKEN")

  if [ ${#TOKEN_ARRAY[@]} -eq 0 ]; then
    echo "⚠️ No new satellite tokens — skipping secret update" >&2
  else
    create_satellite_secret "${TOKEN_ARRAY[@]}"
  fi

  deploy_satellites

  echo "🎉 Seed complete"
}

case $1 in
  seed)
    seed
    ;;
  *)
    echo "Usage: ./seed.sh seed"
    ;;
esac
