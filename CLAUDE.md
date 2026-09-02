# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Infrastructure provisioning for a home k3s cluster. The controller node is **morgul** (`192.168.1.212`). All services use the `*.home.arpa` wildcard domain, TLS via cert-manager (`home-arpa-ca` secret in `cert-manager` namespace), and are accessed through Traefik ingress.

This repo handles **bootstrap only**: it provisions k3s, creates Kubernetes secrets/DBs for each app, and installs ArgoCD. The actual application manifests live in the separate `github.com/blogdoft/k3s-apps` repo and are deployed by ArgoCD via GitOps. One exception: `redis/RedisToggler.Api` is a standalone .NET app with its own build/deploy script (`deploy.sh`), unrelated to the ArgoCD-managed apps.

## Environment Setup

All credentials are in `.env` (gitignored, `source`d — note it uses `export` statements, not plain `KEY=value`). Copy `.env.template` and fill in before running anything:

```bash
ANSIBLE_MORGUL=<ssh-user>
ANSIBLE_PASSWORD=<ssh-password>
HOST_NAME=morgul
DATABASE_HOST=192.168.1.212
DATABASE_USER=<postgres-superuser>
DATABASE_PASSWORD=<postgres-superuser-password>
K3S_TOKEN=<token>
K3S_DB_USER=<user>
K3S_DB_PASSWORD=<password>
OAUTH2_PROXY_COOKIE_SECRET=...
OAUTH2_PROXY_CLIENT_ID=...
OAUTH2_PROXY_CLIENT_SECRET=...
ARGOCD_KC_CLIENT_SECRET=...
FLAGR_KC_CLIENT_SECRET=...
FORGEJO_DB_NAME=forgejodb
FORGEJO_DB_USER=forgejo
FORGEJO_DB_PASSWORD=...
OWUI_DATABASE=...
OWUI_USER=...
OWUI_DBPASS=...
```

`install.sh` and every component script `source .env` (or `../.env` from a subdirectory) — always run from the repo root, or from the component directory as documented in that script.

## Key Commands

**Full install** — interactive, prompts y/n before each stage:
```bash
./install.sh
```

**Full uninstall:**
```bash
./uninstall.sh
```

**Server preparation (run once on new nodes):**
```bash
ansible-playbook playbooks/prepare-server.yaml -i inventory.yaml
```

**Install k3s controller only:**
```bash
ansible-playbook playbooks/install-controller.yaml -i inventory.yaml
```

**Reset and recreate the shared `flagr`, `k3s`, `kc-cluster` databases:**
```bash
cd databases && ./configure.sh
```
Requires Docker running locally (runs `psql` via `postgres:14-alpine` container) and Postgres at `$DATABASE_HOST` reachable.

**Re-run individual component setup** (each is idempotent — drops/recreates its own DB and secrets):
```bash
cd argocd && ./install.sh       # install ArgoCD + Ingress, register k3s-apps repo, bootstrap root-app
cd keycloak && ./install.sh     # recreate keycloak DB secret + realm configmaps
cd flagr && ./install.sh        # recreate flagr postgres-credentials secret
cd flagr && ./postinstall.sh    # recreate oauth2-proxy secrets (queries Keycloak DB for client secret)
cd forgejo && ./configure.sh    # recreate forgejo DB/user, apply configmap
cd forgejo && ./runner-install.sh   # optionally build+push forgejo-runner image, (re)deploy Forgejo Actions runners
cd open-webui && ./install.sh   # recreate open-webui DB/user, apply secrets
cd openbao && POD_NAME=openbao-0 ./init.sh   # initialize and unseal OpenBao
cd rancher && ./install.sh      # wait for Rancher, pin to morgul node
```

**Trust the self-signed CA on cluster nodes** (Docker + containerd, needed before pushing to the Forgejo registry):
```bash
ansible-playbook playbooks/trust-ca-root.yaml -i inventory.yaml
```

## Architecture

### Install Sequence (`install.sh`)

Each stage is gated by a y/n prompt, in this order — later stages assume earlier ones ran:

1. `playbooks/prepare-server.yaml` — OS prep on `morgul` (one-time)
2. `databases/configure.sh` then `playbooks/install-controller.yaml` — drops/recreates the `flagr`/`k3s`/`kc-cluster` DBs, installs k3s, copies kubeconfig (`scp sauron@morgul:/etc/rancher/k3s/k3s.yaml ~/.kube/config`)
3. Secrets stage: `flagr/install.sh`, `kubectl apply -f dns/` (CoreDNS forward for `home.arpa`), `keycloak/install.sh`, `forgejo/configure.sh`, `open-webui/install.sh`
4. `argocd/install.sh` — installs ArgoCD + ingress, registers the `k3s-apps` repo, bootstraps the root app; prints the initial admin password
5. Manual pause: tag the Longhorn disk/node `ssd` at `https://longhorn.home.arpa`
6. Manual pause or `openbao/init.sh` — unseal OpenBao at `https://openbao.home.arpa`
7. Manual pause: verify the Keycloak realm import and that ArgoCD apps are synced
8. `rancher/install.sh` — pins Rancher to `morgul`
9. Exports the CA (`kubectl -n cert-manager get secret home-arpa-ca`) to `./home-arpa-ca.crt` and installs it into the local machine's trust store (`update-ca-certificates`)
10. Optional: `playbooks/trust-ca-root.yaml` — distributes the CA to cluster nodes so Docker/containerd trust the Forgejo registry
11. Optional: `forgejo/runner-install.sh` — build+push the `forgejo-runner-custom` image and deploy Forgejo Actions runners (needs step 10 done first)
12. `flagr/postinstall.sh` — queries the Keycloak DB for the `flagr` client secret and creates `oauth2-proxy-secrets`

### K3s Datastore

k3s uses **PostgreSQL** (not embedded etcd) as its datastore. Postgres runs on `morgul` itself (`192.168.1.212:5432`), external to the cluster, and also hosts the `kc-cluster` (Keycloak), `flagr`, `forgejodb`, and Open-WebUI databases. Connection details for the k3s datastore come from `inventory.yaml`, sourced from `.env`.

### GitOps Split

- **This repo**: k3s installation, per-app secret/DB bootstrapping, ArgoCD installation, Forgejo Actions runner provisioning.
- **`github.com/blogdoft/k3s-apps`**: all application Kubernetes manifests (Longhorn, OpenBao, Keycloak, Rancher, Flagr, Forgejo, Open-WebUI, etc.), managed by ArgoCD. Changes to running workloads go there, not here.

### Component-script pattern

Most `<component>/install.sh` or `configure.sh` scripts follow the same shape: `source ../.env` → optionally drop/recreate a Postgres DB and role via a throwaway `postgres:14-alpine` Docker container → `envsubst` a template YAML (secrets/configmap) → `kubectl apply` it into the component's namespace (created if missing) → clean up the substituted temp file. When adding a new component, follow this pattern rather than inventing a new one.

### TLS / Registry Trust

- TLS for `*.home.arpa` is issued by cert-manager and stored as the `home-arpa-ca` secret in `cert-manager` namespace (managed in `k3s-apps`, not here).
- `install.sh` exports that CA to `./home-arpa-ca.crt` (gitignored) for local machine/browser trust.
- `playbooks/trust-ca-root.yaml` distributes the same CA to Docker and k3s/containerd on cluster nodes, specifically so images can be pushed to/pulled from the self-hosted Forgejo container registry (`forgejo.home.arpa`).

### Sensitive Files (all gitignored)

- `.env` — all credentials
- `*.crt`, `*.key`, `*.pem` (repo-wide) — TLS material, including `home-arpa-ca.crt`
- `argocd/repo-secret.generated.yaml`
- `openbao/openbao-init.json`, `openbao-root-token.txt`, `openbao-unseal-keys.txt` — vault init output
- `forgejo/*-temp.yaml` — envsubst'd runner manifests
