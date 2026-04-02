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

login() {
  $CLI_PATH login $HARBOR_URL -u $USERNAME -p $PASSWORD
}

create_project() {
  PROJECT=$1

  echo "📦 Checking project: $PROJECT"

  if $CLI_PATH project list -o json | jq -e ".[] | select(.name == \"$PROJECT\")" >/dev/null; then
    echo "♻️ Project $PROJECT exists"
  else
    $CLI_PATH project create "$PROJECT" --public --storage-limit 0
    echo "✅ Created $PROJECT"
  fi
}

docker_login() {
  echo "$PASSWORD" | docker login localhost:8888 -u $USERNAME --password-stdin
}

build_internal() {
  docker build -t ground-control:dev "$GC_PATH"
  docker build -t satellite:dev "$SAT_PATH"
}

push_internal() {
  docker tag ground-control:dev localhost:8888/$SAT_PROJECT/ground-control:dev
  docker tag satellite:dev localhost:8888/$SAT_PROJECT/satellite:dev

  docker push localhost:8888/$SAT_PROJECT/ground-control:dev
  docker push localhost:8888/$SAT_PROJECT/satellite:dev
}

seed_mock() {
  for IMAGE in "${MOCK_IMAGES[@]}"; do
    docker pull $IMAGE

    NAME=$(echo $IMAGE | cut -d':' -f1)
    TAG=$(echo $IMAGE | cut -d':' -f2)

    TARGET="localhost:8888/$MOCK_PROJECT/$NAME:$TAG"

    docker tag $IMAGE $TARGET
    docker push $TARGET
  done
}

create_groups() {
  GC_USERNAME=admin
  GC_PASSWORD=Password@1
  
  echo "🔐 Logging into ground-control..."

  TOKEN=$(curl -s -X POST "$GC_BASE/login" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"$GC_USERNAME\",
      \"password\": \"$GC_PASSWORD\"
    }" | jq -r '.token')

  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "❌ Failed to get token"
    exit 1
  fi

  echo "✅ Got token"

  AUTH_HEADER="Authorization: Bearer $TOKEN"
  GC_URL="$GC_BASE/api/groups/sync"

  echo "📦 Creating groups..."

  # edge-1
  curl -s -X POST "$GC_URL" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{
      "group": "edge-1",
      "registry": "http://host.k3d.internal:8888",
      "artifacts": [
        { "repository": "satellites/ground-control", "tag": ["dev"], "type": "image" },
        { "repository": "satellites/satellite", "tag": ["dev"], "type": "image" },
        { "repository": "library/nginx", "tag": ["alpine"], "type": "image" },
        { "repository": "library/busybox", "tag": ["latest"], "type": "image" }
      ]
    }' >/dev/null

  echo "✅ edge-1 synced"

  # edge-2
  curl -s -X POST "$GC_URL" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{
      "group": "edge-2",
      "registry": "http://host.k3d.internal:8888",
      "artifacts": [
        { "repository": "satellites/satellite", "tag": ["dev"], "type": "image" },
        { "repository": "library/nginx", "tag": ["latest"], "type": "image" },
        { "repository": "library/alpine", "tag": ["latest"], "type": "image" },
        { "repository": "library/redis", "tag": ["7"], "type": "image" }
      ]
    }' >/dev/null

  echo "🎉 Groups created successfully"
}

deploy_gc() {
  kubectl apply -k k8s/ground-control
  kubectl get pods -o wide
}

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
  
  create_groups
}

case $1 in
  seed)
    seed
    ;;
  *)
    echo "Usage: ./seed.sh seed"
    ;;
esac
