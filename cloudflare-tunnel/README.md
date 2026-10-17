# Cloudflare Tunnel no K3s

O Deployment e a configuração do `cloudflared` são versionados em `k3s-apps` e
reconciliados pelo Argo CD. Este diretório mantém somente o elemento que não
pode ir ao Git: o arquivo de credenciais do Tunnel. O Tunnel aceita apenas
`*.blogdoft.dev`, encaminha a requisição para o Service interno do Traefik e
preserva o Host original.

## Pré-requisitos

### Instalar o CLI no computador de administração

Em Debian ou Ubuntu, instale o pacote assinado pela Cloudflare:

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt-get update
sudo apt-get install cloudflared
cloudflared --version
```

Instale-o no computador de administração, não no `morgul`: o `cloudflared`
será executado pelos Pods Kubernetes. Consulte a [página oficial de
downloads](https://developers.cloudflare.com/tunnel/downloads/) para macOS,
Windows e outras distribuições.

### Criar o Tunnel localmente

Crie o Tunnel localmente uma única vez e guarde o arquivo de credenciais fora
do repositório:

```bash
cloudflared tunnel login
cloudflared tunnel create k3s-apps
```

No arquivo `.env`, informe o caminho absoluto do JSON criado por esse comando:

```bash
export CLOUDFLARE_TUNNEL_CREDENTIALS_FILE="$HOME/.cloudflared/<uuid-do-tunnel>.json"
```

O `credentials.json` é um segredo: não o copie para este diretório e não o
adicione ao Git.

No DNS público da zona `blogdoft.dev`, crie um CNAME proxied (`laranja`) para:

```text
*.blogdoft.dev  CNAME  <uuid-do-tunnel>.cfargotunnel.com
```

O registro curinga cobre subdomínios, mas não o domínio raiz `blogdoft.dev`.
Crie um registro específico se também precisar publicar a raiz.

## Instalação e validação

```bash
./cloudflare-tunnel/install.sh
kubectl -n cloudflare-tunnel rollout status deployment/cloudflared
kubectl -n cloudflare-tunnel get pods
kubectl -n cloudflare-tunnel logs deployment/cloudflared --tail=100
```

Antes de expor uma aplicação, crie um `Ingress` público no K3s para o hostname
correspondente, por exemplo `immich.blogdoft.dev`. O wildcard do Tunnel não
cria regras no Traefik: hosts sem Ingress correspondente devem receber 404.

Para atualizar a configuração, altere os manifests em `k3s-apps`. Para
substituir as credenciais, aponte a variável para o novo JSON e execute o
instalador novamente. Faça commit e push dos manifests em `k3s-apps` antes de
executar o instalador, para que o Argo CD crie o Deployment.
