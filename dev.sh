#!/usr/bin/env bash
set -e

CLUSTER=sat-sim

create_cluster() {
  echo "🚀 Creating k3d cluster..."
  k3d cluster create $CLUSTER --agents 2
}

install_harbor() {
  echo "📦 Installing Harbor..."

  helm repo add harbor https://helm.goharbor.io >/dev/null 2>&1 || true
  helm repo update >/dev/null

  helm install harbor harbor/harbor \
    --namespace harbor \
    --create-namespace \
    --set expose.type=nodePort \
    --set expose.nodePort.ports.http.nodePort=30002 \
    --set externalURL=http://localhost:5000 \
    --set harborAdminPassword=admin \
    --set expose.tls.enabled=false
}

wait_for_harbor() {
  echo "⏳ Waiting for Harbor to be ready (this takes time)..."

  kubectl wait --namespace harbor \
    --for=condition=available deployment \
    --all --timeout=600s

  echo "✅ Harbor is ready"
}

seed_harbor() {
  echo "📦 Seeding Harbor with images..."
  kubectl apply -f k8s/harbor/seed-job.yaml
  kubectl apply -f k8s/harbor/seed-images-job.yaml

  kubectl wait --for=condition=complete job/harbor-seed-images -n harbor --timeout=300s

  echo "⏳ Waiting for seed job..."
  kubectl wait --for=condition=complete job/harbor-seed -n harbor --timeout=120s

  echo "✅ Harbor seeded"
}

deploy_system() {
  echo "📡 Deploying ground-control + satellites..."

  kubectl apply -f k8s/ground-control/ --recursive
  kubectl apply -f k8s/satellites/ --recursive

  kubectl wait --for=condition=available deployment --all --timeout=120s

  echo "📊 Pods:"
  kubectl get pods -o wide
}

delete_cluster() {
  echo "💣 Deleting cluster..."
  k3d cluster delete $CLUSTER
}

logs() {
  kubectl logs -l app=satellite -f
}

status() {
  kubectl get nodes
  kubectl get pods -A
}

case $1 in
  up)
    create_cluster
    install_harbor
    wait_for_harbor
    seed_harbor
    deploy_system
    echo "🎉 Full system is up"
    ;;

  down)
    delete_cluster
    ;;

  logs)
    logs
    ;;

  status)
    status
    ;;

  reset)
    delete_cluster
    create_cluster
    install_harbor
    wait_for_harbor
    seed_harbor
    deploy_system
    ;;

  *)
    echo "Usage: ./dev.sh {up|down|logs|status|reset}"
    ;;
esac
