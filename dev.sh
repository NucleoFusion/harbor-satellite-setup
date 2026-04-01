#!/usr/bin/env bash
set -e

CLUSTER=sat-sim
HARBOR_CLUSTER=harbor-registry

HARBOR_PORT=8888
HARBOR_HOST=localhost:$HARBOR_PORT
HARBOR_PROJECT=satellites

create_harbor_cluster() {
  if ! k3d cluster list | grep -q "$HARBOR_CLUSTER"; then
    echo "📦 Creating Harbor cluster..."
    k3d cluster create $HARBOR_CLUSTER \
      --port "$HARBOR_PORT:30002@server:0" \
      --k3s-arg "--disable=traefik@server:0"
  else
    echo "♻️ Harbor cluster exists"
  fi
}

install_harbor() {
  helm repo add harbor https://helm.goharbor.io >/dev/null 2>&1 || true
  helm repo update >/dev/null

  if helm status harbor -n harbor >/dev/null 2>&1; then
    echo "♻️ Harbor already installed"
  else
    helm install harbor harbor/harbor \
      --namespace harbor \
      --create-namespace \
      --set expose.type=nodePort \
      --set expose.nodePort.ports.http.nodePort=30002 \
      --set externalURL=http://$HARBOR_HOST \
      --set harborAdminPassword=admin \
      --set expose.tls.enabled=false
  fi
}

wait_for_harbor() {
  echo "⏳ Waiting for Harbor pods..."

  kubectl wait --namespace harbor \
    --for=condition=available deployment \
    --all --timeout=600s

  echo "⏳ Waiting for Harbor API..."

  until curl -sf http://$HARBOR_HOST/api/v2.0/ping >/dev/null; do
    sleep 3
  done

  # echo "⏳ Waiting for Registry..."

  # until curl -sf http://$HARBOR_HOST/v2/_catalog >/dev/null; do
  #   sleep 3
  # done

  echo "✅ Harbor fully ready"
}

create_main_cluster() {
  if ! k3d cluster list | grep -q "$CLUSTER"; then
    echo "📦 Creating main cluster..."
    k3d cluster create $CLUSTER \
      --port "8000:30000@server:0" \
      --k3s-arg "--disable=traefik@server:0" \
      --registry-config ./k8s/k3d-registry.yaml
  else
    echo "♻️ Main cluster exists"
  fi
}

create_harbor_secret() {
  kubectl delete secret harbor-regcred --ignore-not-found

  kubectl create secret docker-registry harbor-regcred \
    --docker-server=$HARBOR_HOST \
    --docker-username=admin \
    --docker-password=admin
}

build_and_push_gc() {
  docker build -t ground-control:dev /home/nucleofusion/Programming/projects/satellite/ground-control

  echo "admin" | docker login $HARBOR_HOST -u admin --password-stdin

  docker tag ground-control:dev $HARBOR_HOST/$HARBOR_PROJECT/ground-control:dev
  docker push $HARBOR_HOST/$HARBOR_PROJECT/ground-control:dev
}

deploy_system() {
  kubectl apply -k k8s/ground-control
  kubectl apply -f k8s/satellites/
  kubectl get pods -o wide
}

stop_workloads() {
  kubectl delete -k k8s/ground-control --ignore-not-found
  kubectl delete -f k8s/satellites/ --ignore-not-found
}

reload() {
  build_and_push_gc
  kubectl rollout restart deployment ground-control
}

case $1 in
  up)
    create_harbor_cluster
    install_harbor

    create_main_cluster
    create_harbor_secret

    wait_for_harbor

    docker login $HARBOR_HOST || true

    build_and_push_gc
    deploy_system

    echo "🎉 System is up"
    ;;

  down)
    stop_workloads
    ;;

  reload)
    reload
    ;;

  nuke)
    k3d cluster delete "$CLUSTER"
    k3d cluster delete "$HARBOR_CLUSTER"
    ;;

  *)
    echo "Usage: ./dev.sh {up|down|reload|nuke}"
    ;;
esac
