# Harbor Satellite Simulation (WIP 🚧) (Mostly Vibed)

A local, reproducible Kubernetes-based simulation of a **control-plane ↔ satellite system**, backed by a private container registry.

This project aims to model how distributed systems coordinate workloads, manage artifacts, and handle identity — all within a lightweight, ephemeral dev environment.

> ⚠️ **Status: Work in Progress**
> This project is actively being developed. Expect breaking changes, incomplete features, and evolving architecture.

---

## 🧠 Overview

This environment simulates a simplified distributed system:

* **Ground Control** → central coordinator (control plane)
* **Satellites** → worker nodes/agents
* **Harbor** → private container registry
* **Kubernetes (k3d)** → orchestration layer

Everything is bootstrapped via a single script and runs locally.

---

## ⚙️ Architecture

```
k3d cluster
├── harbor (container registry)
├── ground-control (control plane)
├── satellites (workers, replicated)
└── seed jobs (bootstrap data + images)
```

---

## 🚀 Getting Started

### Prerequisites

* Docker
* k3d
* kubectl
* Helm

---

### Start the environment

```bash
./dev.sh up
```

This will:

1. Create a local Kubernetes cluster (k3d)
2. Install Harbor via Helm
3. Wait for Harbor to become ready
4. Seed Harbor with:

   * a project (`satellites`)
   * a few images (`nginx`, `alpine`, `busybox`)
5. Deploy:

   * ground-control
   * satellite replicas

---

### Stop everything

```bash
./dev.sh down
```

This completely deletes the cluster and all state.

---

### Check status

```bash
./dev.sh status
```

---

### View logs

```bash
./dev.sh logs
```

---

## 📦 Harbor Setup

Harbor is deployed inside the cluster and seeded automatically.

### Seeded Project

```
satellites
```

### Seeded Images

* nginx:latest
* alpine:latest
* busybox:latest

Images are copied from public registries into Harbor using an internal Kubernetes Job (no local Docker configuration required).

---

## 🔍 Access Harbor UI

```bash
kubectl port-forward svc/harbor 8080:80 -n harbor
```

Open:

```
http://localhost:8080
```

Credentials:

```
username: admin
password: admin
```

---

## 🧪 What This Simulates

* Multi-node orchestration (via Kubernetes)
* Internal service discovery
* Private registry usage (Harbor)
* Artifact seeding and distribution
* Control-plane ↔ worker interaction (basic, expanding)

---

## 📁 Project Structure

```
.
├── dev.sh
├── k8s/
│   ├── ground-control/
│   ├── satellites/
│   └── harbor/
│       ├── seed-job.yaml
│       └── seed-images-job.yaml
└── scripts/
```

---

## 🧠 Design Philosophy

* **Ephemeral by default** — no long-running infra
* **Reproducible** — one command = full system
* **Layered complexity** — build up gradually:

  1. Basic deployments
  2. Registry integration
  3. Workload coordination
  4. Identity (planned)

---

## 🚧 Roadmap

Planned features:

* [ ] Replace mock containers with real services (Go)
* [ ] Satellite → Ground Control communication (heartbeat + tasks)
* [ ] Dynamic workload assignment
* [ ] Integration with SPIFFE/SPIRE for identity
* [ ] Failure simulation (node/pod crashes)
* [ ] Observability (logs, metrics)

---

## ⚠️ Known Limitations

* Harbor startup is slow (~2–5 minutes)
* No authentication/identity layer yet
* Ground Control is currently a placeholder
* No persistent storage (by design)

---

## 💡 Why This Exists

This project is part of a broader exploration into:

> **Integration trade-offs in container-based distributed systems**

It serves as a sandbox to experiment with:

* orchestration
* registry interactions
* control-plane design
* system coordination patterns

---

## 🤝 Contributing / Notes

This is currently a personal exploration project, but structure and clarity are prioritized so it can evolve into something more formal (e.g., research or demonstration).

---

## 📌 TL;DR

```bash
./dev.sh up     # start everything
./dev.sh down   # destroy everything
```

---

## 🚧 Reminder

This is **not production-ready**.
It’s a **learning + experimentation environment**.

Expect things to break — and that’s kind of the point.
