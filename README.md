# k3s-experiment 🚀

Infraestrutura k3s para ambiente de experimentação com storage distribuído, monitoramento e aplicações containerizadas.

## 📋 Índice

- [Serviços Disponíveis](#serviços-disponíveis)
- [Arquitetura](#arquitetura)
- [Estrutura do Repositório](#estrutura-do-repositório)
- [Pré-requisitos](#pré-requisitos)
- [Instalação](#instalação)
- [Componentes](#componentes)
- [Troubleshooting](#troubleshooting)

---

## 🌐 Serviços Disponíveis

Todos os serviços são acessíveis através do nó controller **morgul** (`192.168.1.212`) no domínio `.home.arpa`:

| Serviço | URL | Descrição |
|---------|-----|-----------|
| 🗃️ **Docker Registry** | `https://registry.home.arpa` | Registry privado com TLS para imagens Docker |
| 💾 **Longhorn UI** | `https://longhorn.home.arpa` | Interface web do storage distribuído |
|  **RedisToggler API** | `https://redis-toggler.home.arpa` | API de exemplo para gerenciamento Redis |

> **⚠️ Nota:** Todos os serviços utilizam certificados TLS auto-assinados via secret `wildcard-home-arpa`. Configure seu sistema para confiar na CA ou aceite os avisos do navegador.

---

## 🏗️ Arquitetura

### Topologia do Cluster

```
┌─────────────────────────────────────────────────┐
│  morgul (Controller Node) - 192.168.1.212       │
│  ┌──────────────────────────────────────────┐   │
│  │  k3s Server + Traefik Ingress            │   │
│  │  Entry Point: websecure (443), web (80)  │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │ Worker1 │   │ Worker2 │   │ Worker3 │
   │  Agent  │   │  Agent  │   │  Agent  │
   └─────────┘   └─────────┘   └─────────┘
```

### Stack Tecnológico

- **Orquestração:** k3s (Kubernetes lightweight)
- **Storage:** Longhorn (distributed block storage)
- **Ingress Controller:** Traefik (integrado ao k3s)
- **Registry:** Docker Registry privado com TLS
- **Banco de Dados:** PostgreSQL, Redis
- **TLS:** Certificados auto-assinados wildcard `*.home.arpa`

---

## 📁 Estrutura do Repositório

```
k3s-experiment/
├── 01 - preparar-ambiente/     # 🛠️ Ansible playbooks para setup do cluster
│   ├── inventory/              # Inventário dos nós
│   ├── 01-update-server.yaml   # Atualização do sistema
│   ├── 02-install-controller.yaml  # Instalação k3s controller
│   ├── 03-install-agent.yaml   # Instalação k3s agents
│   └── 04-disk-prepare.yaml    # Preparação de discos para Longhorn
│
├── registry/                   # 🗃️ Docker Registry privado
│   ├── registry-tls.yaml       # Deployment com TLS
│   ├── ansible/                # Configuração de nodes para registry
│   └── README.md
│
├── longhorn/                   # 💾 Storage distribuído
│   ├── longhorn.yaml           # Instalação do Longhorn
│   ├── longhorn-postinstall.yaml  # StorageClasses e Ingress
│   └── ssd.yaml                # Configuração de disks SSD
│
├── redis/                      # 🔴 Redis Server
│   ├── deployment.yaml
│   ├── pvc.yaml
│   ├── service.yaml
│   └── RedisToggler.Api/       # API .NET de exemplo
│
├── deployPostgres/             # 🐘 PostgreSQL
│   ├── 01-pvc.yaml
│   ├── 04-service.yaml
│   └── deploy.sh
│
├── dashboard/                  # 📱 Kubernetes Dashboard
│   ├── recommended.yaml
│   └── serviceAccount.yaml
│
├── kafka/                      # 📨 Apache Kafka (experimental)
│   ├── deployment.yaml
│   └── client.yaml
│
└── rancher/                    # 🐄 Rancher UI (experimental)
    └── apply/
```

---

## 🚀 Instalação

### 1. Preparação do Cluster

Configure o inventário Ansible em `01 - preparar-ambiente/inventory/01-inventory.yaml`:

```yaml
all:
  children:
    k3s_cluster:
      children:
        controller:
          hosts:
            morgul:
              ansible_host: 192.168.1.212
        workers:
          hosts:
            worker1:
              ansible_host: 192.168.1.xxx
            worker2:
              ansible_host: 192.168.1.xxx
```

Execute os playbooks na ordem:

```bash
cd "01 - preparar-ambiente"

# 1. Atualizar todos os nós
ansible-playbook -i inventory/01-inventory.yaml 01-update-server.yaml

# 2. Instalar k3s controller (morgul)
ansible-playbook -i inventory/01-inventory.yaml 02-install-controller.yaml

# 3. Instalar k3s agents (workers)
ansible-playbook -i inventory/01-inventory.yaml 03-install-agent.yaml

# 4. Preparar discos para Longhorn (opcional, se usar discos dedicados)
ansible-playbook -i inventory/01-inventory.yaml 04-disk-prepare.yaml
```

### 2. Configurar Storage (Longhorn)

```bash
cd ../longhorn

# Instalar Longhorn no cluster
kubectl apply -f longhorn.yaml

# Aguardar pods do Longhorn subirem
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# Aplicar StorageClasses e Ingress
kubectl apply -f longhorn-postinstall.yaml

# (Opcional) Configurar discos SSD específicos
kubectl apply -f ssd.yaml
```

Acesse a UI: `https://longhorn.home.arpa`

### 3. Instalar Docker Registry

```bash
cd ../registry

# Aplicar todos os recursos (namespace, PVC, deployment, service, ingress)
kubectl apply -f registry-tls.yaml

# Configurar nodes para confiar no registry (via Ansible)
cd ansible
ansible-playbook -i ../../"01 - preparar-ambiente"/inventory/01-inventory.yaml playbook.yaml
```

Acesse: `https://registry.home.arpa`

**Testar push de imagem:**

```bash
# Tag de uma imagem
docker tag myapp:latest registry.home.arpa/myapp:latest

# Push para o registry
docker push registry.home.arpa/myapp:latest
```

### 4. Deploy de Aplicações

#### PostgreSQL

```bash
cd ../deployPostgres
./deploy.sh
```

#### Redis + RedisToggler API

```bash
cd ../redis

# Instalar Redis
./install.sh

# Deploy da API .NET
cd RedisToggler.Api
./deploy.sh
```

Acesse: `https://redis-toggler.home.arpa`

---

## 🔧 Componentes

### Longhorn Storage

**StorageClasses disponíveis:**
- `longhorn-fast` (default): Réplicas=2, discos SSD
- `longhorn`: Réplicas=3, storage padrão

**Configuração:**
```yaml
storageClass: longhorn-fast
accessModes: [ReadWriteOnce]
storage: 10Gi
```

### TLS e Certificados

Certificado wildcard auto-assinado armazenado no secret `wildcard-home-arpa`:

```bash
# Criar secret TLS (exemplo)
kubectl create secret tls wildcard-home-arpa \
  --cert=wildcard.crt \
  --key=wildcard.key \
  -n <namespace>
```

Usado por:
- Docker Registry
- Longhorn UI
- RedisToggler API

### Traefik Ingress

**Entrypoints configurados:**
- `web`: HTTP (80)
- `websecure`: HTTPS (443)

**Annotations comuns:**
```yaml
traefik.ingress.kubernetes.io/router.entrypoints: websecure
traefik.ingress.kubernetes.io/router.tls: "true"
```

---

## 🛠️ Troubleshooting

### Pods não iniciam

```bash
# Verificar eventos
kubectl describe pod <pod-name> -n <namespace>

# Verificar logs
kubectl logs <pod-name> -n <namespace>

# Verificar PVCs
kubectl get pvc -A
```

### Ingress não acessível

```bash
# Verificar serviço Traefik
kubectl get svc -n kube-system traefik

# Verificar ingress
kubectl get ingress -A

# Testar resolução DNS
nslookup registry.home.arpa

# Verificar certificados TLS
kubectl get secrets -A | grep tls
```

### Storage Issues (Longhorn)

```bash
# Status dos volumes
kubectl get volumes -n longhorn-system

# Status dos nós Longhorn
kubectl get nodes.longhorn.io -n longhorn-system

# Logs do manager
kubectl logs -l app=longhorn-manager -n longhorn-system
```

### Registry

```bash
# Testar conectividade
curl -k https://registry.home.arpa/v2/_catalog

# Verificar configuração do node
cat /etc/rancher/k3s/registries.yaml

# Restart k3s para aplicar mudanças
systemctl restart k3s
```

---

## 📝 Notas Adicionais

- **DNS:** Configure `/etc/hosts` ou servidor DNS para resolver `*.home.arpa` para `192.168.1.212` (morgul)
- **Firewall:** Certifique-se de que portas 80, 443, 6443 (k3s API) estão abertas
- **Recursos:** Cluster dimensionado para workloads leves/médios
- **Backup:** Configure snapshots do Longhorn para dados críticos

---

## 📚 Referências

- [k3s Documentation](https://docs.k3s.io/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Traefik Kubernetes Ingress](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)

---

**Mantido por:** ftathiago  
**Última atualização:** 2024
│   └── client.yaml
│
└── rancher/                    # 🐄 Rancher UI (experimental)
    └── apply/

Pré-requisitos
-------------
- Acesso SSH aos nós controladora e workers com privilégios `sudo`.
- `ansible` disponível na máquina de controle (onde você aplica os playbooks).
- `kubectl` configurado para se conectar ao cluster k3s após instalação.

Passo-a-passo — visão geral
--------------------------
1. Preparar inventário e variáveis
	 - Edite `01 - preparar-ambiente/inventory/01-inventory.yaml` para refletir os hosts e credenciais do seu ambiente.
	 - Variáveis importantes: `K3S_TOKEN` (usado para juntar workers), e credenciais SSH usadas pelo Ansible.

2. Instalar k3s no controller
	 - Use o playbook ou o script em `01 - preparar-ambiente/02-install-controller.yaml`.
	 - Exemplo (ad-hoc):
		 ```bash
		 ansible-playbook -i "01 - preparar-ambiente/inventory/01-inventory.yaml" "01 - preparar-ambiente/02-install-controller.yaml"
		 ```
	 - O playbook chama o instalador oficial do k3s (`https://get.k3s.io`). O token do cluster vem do inventário (`K3S_TOKEN`).

3. Instalar agentes (workers)
	 - Use o playbook na pasta `01 - preparar-ambiente/` para instalar agentes conectando ao controller com o token.

4. Configurar registry (opcional: se você quer um registry privado)
	 - `registry/apply.yaml` contém Deployment, Service (porta 5000), PVC e Ingress.
	 - `registry/tls/registry-tls.yaml` contém o Secret TLS (use `stringData` na sua máquina ou crie o Secret com `kubectl create secret tls ...`).
	 - Para que os nós puxem imagens do registry com TLS privado, configure os nós:
		 - Distribua a CA para `/etc/ssl/certs/registry-home-arpa.crt` (ou `/usr/local/share/ca-certificates`) e rode `update-ca-certificates`.
		 - Configure `/etc/rancher/k3s/registries.yaml` para que containerd confie no registry (veja `registry/tls/registries.yaml` como exemplo). Depois reinicie `k3s`.
	 - Há um playbook ansible exemplo em `registry/ansible/configure-registries.yaml` que copia a CA e escreve `registries.yaml` nos nós e reinicia o serviço `k3s`.

5. Instalar Ingress (Traefik)
	 - k3s instala Traefik por padrão; se você removeu ou alterou a instalação, verifique a configuração de entrypoints (web/websecure).
	 - Os ingress no repositório usam `spec.ingressClassName: traefik` e anotações Traefik. Para reescritas (ex.: remover `/api`) usamos Middlewares (`traefik.containo.us/v1alpha1` CRD) — ver `redis/RedisToggler.Api/eng/.k8s/deploy.yaml`.

6. Aplicar manifests das aplicações
	 - Exemplo para o registry e redis:
		 ```bash
		 kubectl apply -f registry/apply.yaml
		 kubectl apply -f redis/apply.yaml
		 ```
	 - Para o RedisToggler (exemplo) há manifests em `redis/RedisToggler.Api/eng/.k8s/` e um deploy template em `.deploy/`.

Diagnóstico e passos úteis
-------------------------
- Se o pod não puxa a imagem (ImagePullBackOff):
	- Verifique `kubectl -n <ns> describe pod <pod>` para mensagens de erro.
	- Se o runtime (containerd) reclama de TLS ou certificados, verifique `/etc/rancher/k3s/registries.yaml` e a presença do CA em `/etc/ssl/certs`.
	- Teste conectividade dentro do cluster com um pod `curlimages/curl` para `http://registry-service:5000/v2/`.

- Para criar o Secret TLS localmente sem commitar chaves privadas:
	```bash
	kubectl create secret tls docker-registry-tls-cert -n docker-registry --cert=registry.crt --key=registry.key
	```
	ou gerar o manifesto YAML já codificado em base64:
	```bash
	kubectl create secret tls docker-registry-tls-cert -n docker-registry --cert=registry.crt --key=registry.key --dry-run=client -o yaml > registry-tls-secret.yaml
	```

Ansible — exemplos úteis
-----------------------
- Copiar CA para nós e atualizar store do sistema (ad-hoc):
	```bash
	ansible all -b -i "01 - preparar-ambiente/inventory/01-inventory.yaml" \
		-m copy -a "src=registry/tls/registry.crt dest=/usr/local/share/ca-certificates/registry-home-arpa.crt mode=0644"

	ansible all -b -i "01 - preparar-ambiente/inventory/01-inventory.yaml" \
		-m shell -a "update-ca-certificates && systemctl restart k3s"
	```

- Playbook de exemplo incluído:
	- `registry/ansible/configure-registries.yaml` — copia CA, escreve `/etc/rancher/k3s/registries.yaml` e reinicia k3s.
	- `ingress/ansible/playbook.yaml` — instala CA do mkcert em `/usr/local/share/ca-certificates` e `/etc/ssl/certs`.

Boas práticas
------------
- Evite commitar chaves privadas no repositório. Use `stringData` apenas em ambientes controlados ou crie o Secret via `kubectl create secret tls` localmente.
- Para produção, prefira usar um registry com certificado válido por uma CA pública ou centralizar a CA no DNS/PKI da sua rede.
- Use `imagePullSecrets` se o registry exigir autenticação.

Ajuda adicional
---------------
Se quiser, eu posso:
- Gerar um playbook Ansible que aplica automaticamente todos os passos (copiar CA, configurar registries, reiniciar k3s, aplicar manifests).
- Atualizar manifests para usar `imagePullSecrets` ou expor o registry via NodePort para depuração.

Contribuições
-------------
Abra um pull request com sugestões de melhoria ou ajustes no inventário/playbooks para ambientes específicos.

Licença
-------
Use conforme desejar.

