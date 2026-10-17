# Relatório e plano de segurança — morgul

## Objetivo e escopo

Este documento cobre o host `morgul`, que executa K3s, e a publicação **somente das aplicações do cluster** via Cloudflare Tunnel. Os demais serviços devem continuar disponíveis na LAN, mas não devem ser publicados na internet.

A avaliação foi feita por SSH, com coleta de configuração e serviços em escuta. Nenhuma correção descrita aqui deve ser aplicada sem validar seu impacto no ambiente.

## Estado observado

- O Apache foi parado e desabilitado no host e no playbook Ansible do controller.
- O Cloudflare Tunnel ainda não estava instalado ou ativo durante a avaliação.
- SSH aceita autenticação por senha para `sauron`, que possui `sudo`.
- O `fail2ban` está inativo e `unattended-upgrades` não está instalado.
- K3s e Docker gerenciam regras `nftables`; não se deve aplicar UFW sem avaliar a interação com esses componentes.

### Serviços em escuta na LAN

| Porta | Serviço | Publicar pelo Tunnel? |
| ---: | --- | --- |
| 22 | SSH | Não |
| 111 TCP/UDP | RPCbind | Não |
| 5432 | PostgreSQL em Docker | Não |
| 6443 | API do K3s | Não |
| 10250 | Kubelet | Não |
| 11434 | Ollama | Não |
| 9100 | Node Exporter | Não |
| 30433, 30839, 31293 | NodePorts do K3s | Não |
| Ingress HTTP/HTTPS do K3s | Aplicações do cluster | Sim, exclusivamente este |

Manter esses serviços na LAN é compatível com o objetivo. Um Cloudflare Tunnel só publica os serviços apontados nas regras `ingress`; ele não expõe automaticamente todas as portas do host. Ainda assim, serviços LAN devem ser tratados como acessíveis por qualquer dispositivo comprometido nessa rede.

## Achados e prioridades

| Gravidade | Achado | Risco | Correção prioritária |
| --- | --- | --- | --- |
| Crítica | Credencial SSH com sudo foi compartilhada em texto claro | A credencial deve ser considerada comprometida | Trocar a senha e adotar chaves SSH individuais |
| Alta | SSH aceita senha; sem Fail2ban | Tentativas de senha e acesso indevido a conta com sudo | Desabilitar senha após validar chaves e ativar Fail2ban |
| Alta | Possibilidade de configurar Tunnel para portas administrativas | Uma regra incorreta pode publicar API K3s, SSH ou banco | Tunnel somente para o Ingress HTTP/HTTPS; usar Access |
| Média | PostgreSQL exposto na LAN em `5432` | Clientes LAN não autorizados podem tentar autenticar | Restringir em `pg_hba.conf` a sub-redes/hosts necessários |
| Média | Ollama exposto na LAN em `11434` | Uso não autorizado de recursos e envio de dados à API | Restringir a VLAN/hosts autorizados quando possível |
| Média | API K3s, kubelet e NodePorts na LAN | Superfície de administração do cluster disponível na rede | Não fazer port-forward externo; limitar rede de administração |
| Média | RPCbind na porta `111` | Serviço RPC adicional e enumeração de serviços | Desabilitar apenas se não houver dependência NFS/RPC |
| Média | Node Exporter em `9100` | Métricas revelam dados do host e serviços | Permitir apenas o Prometheus/rede de monitoramento |
| Média | Sem atualizações automáticas | Janela maior para falhas conhecidas | Ativar `unattended-upgrades` |
| Baixa | SSH com X11 e sem keepalive | Funcionalidade desnecessária e sessões abandonadas | Desabilitar X11 e configurar keepalive |

## Sequência de implementação

> **Importante:** mantenha uma sessão SSH administrativa já conectada enquanto testa novas chaves. Só desabilite senha depois de validar login por chave a partir dos dois computadores.

### 1. Criar chaves SSH individuais

Não compartilhe a chave privada entre os computadores. Crie uma chave em cada um.

No computador atual:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/morgul_admin_ed25519 -C "admin -> morgul"
ssh-copy-id -i ~/.ssh/morgul_admin_ed25519.pub sauron@morgul
ssh -i ~/.ssh/morgul_admin_ed25519 sauron@morgul
```

No computador `enterprise`:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/morgul_enterprise_ed25519 -C "enterprise -> morgul"
ssh-copy-id -i ~/.ssh/morgul_enterprise_ed25519.pub sauron@morgul
ssh -i ~/.ssh/morgul_enterprise_ed25519 sauron@morgul
```

Opcionalmente, crie `~/.ssh/config` em cada computador:

```sshconfig
Host morgul
    HostName morgul
    User sauron
    IdentityFile ~/.ssh/morgul_admin_ed25519
    IdentitiesOnly yes
```

No `enterprise`, use o caminho da chave `morgul_enterprise_ed25519`.

### 2. Trocar a senha e endurecer SSH

No `morgul`, depois dos testes de ambas as chaves:

```bash
passwd sauron

sudo tee /etc/ssh/sshd_config.d/20-hardening.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

sudo sshd -t && sudo systemctl reload ssh
```

Teste novamente a partir dos dois computadores. Em caso de problema, use a sessão SSH antiga ou console local para remover o arquivo de endurecimento e recarregar SSH.

### 3. Habilitar atualizações e bloqueio de tentativas

```bash
sudo apt update
sudo apt install -y unattended-upgrades fail2ban
sudo systemctl enable --now unattended-upgrades fail2ban
```

Verifique:

```bash
systemctl is-active unattended-upgrades fail2ban
sudo fail2ban-client status sshd
```

### 4. Validar serviços RPC/NFS antes de mexer em RPCbind

NFS compartilha diretórios pela rede. O `rpcbind` atende na porta `111` e informa aos clientes em quais portas estão serviços RPC, incluindo componentes comuns de NFSv3. Não o desabilite se houver uso de NFS ou outro RPC dependente.

```bash
sudo rpcinfo -p
sudo exportfs -v
systemctl status nfs-server rpcbind
```

Se não houver dependência:

```bash
sudo systemctl disable --now rpcbind rpcbind.socket
```

### 5. Conferir e restringir os serviços LAN

Liste os pontos de publicação do K3s antes de qualquer mudança:

```bash
sudo k3s kubectl get svc -A -o wide
sudo k3s kubectl get ingress -A
```

- Mantenha a API K3s (`6443`), kubelet (`10250`) e NodePorts fora do Tunnel e sem encaminhamento no roteador.
- Para PostgreSQL, mantenha somente os usuários, bancos e entradas de `pg_hba.conf` necessários para sua LAN.
- Permita o Node Exporter somente à origem que executa Prometheus.
- Se Ollama não deve estar disponível a toda a LAN, restrinja-o à sub-rede/VLAN apropriada; não o publique pelo Tunnel.

## Publicação segura pelo Cloudflare Tunnel

### 1. Descobrir o Ingress correto

```bash
sudo k3s kubectl get ingress -A
sudo k3s kubectl get svc -A -o wide
sudo k3s kubectl get pods -A | grep -Ei 'traefik|nginx|ingress'
```

O serviço do Tunnel deve ser somente o listener HTTP/HTTPS do Ingress. Não use API K3s, SSH, banco, Ollama, Node Exporters ou NodePorts como origem.

### 2. Executar o Tunnel dentro do K3s

Execute o `cloudflared` como um `Deployment`, sem `hostNetwork`, sem `hostPort` e sem `Service` Kubernetes. Assim, ele só faz conexões de saída para a Cloudflare e alcança as aplicações por DNS interno do cluster. O pod não precisa de permissão Kubernetes nem de acesso às portas administrativas do nó.

### 3. Hostnames canônicos, certificados e acesso sem internet

Para aplicações públicas — especialmente serviços com OIDC, redirects ou `issuer`, como Keycloak e APIs `code-brain` — use o hostname público como nome canônico. Exemplo: `keycloak.blogdoft.dev`. Não troque esse cabeçalho por `keycloak.home.arpa` no Tunnel: isso causa divergência de URLs, callbacks e validação de tokens.

Use **split DNS** para manter o mesmo hostname funcional em caso de falha de internet:

```text
Internet: keycloak.blogdoft.dev -> Cloudflare -> Tunnel -> Traefik
LAN:      keycloak.blogdoft.dev -> 192.168.1.212 -> Traefik
```

Configure o resolvedor DNS da LAN (roteador, Pi-hole, AdGuard Home, Unbound ou dnsmasq) para devolver `192.168.1.212` para cada hostname público necessário, ou use um wildcard `*.blogdoft.dev` se todo esse domínio for hospedado no cluster.

Como o cliente LAN falará diretamente com o Traefik por HTTPS, o Traefik deve ter um certificado válido para `*.blogdoft.dev` ou para cada hostname público. O certificado de borda da Cloudflare não é apresentado a clientes que acessam o Traefik diretamente. Emita o certificado no `cert-manager` por ACME DNS-01 usando a zona Cloudflare. Não use Cloudflare Origin Certificate para esse caso: navegadores e clientes LAN não o reconhecem como uma CA pública.

Cada Ingress deve aceitar explicitamente o hostname público e encaminhá-lo ao mesmo Service da aplicação. Mantenha o hostname `*.home.arpa` como rota adicional apenas se quiser preservar o acesso interno legado.

Para Keycloak, use o hostname público fixo e aceite os cabeçalhos do proxy configurado:

```text
KC_HOSTNAME=https://keycloak.blogdoft.dev
KC_PROXY_HEADERS=xforwarded
KC_HTTP_ENABLED=true
```

O `issuer` OIDC, os endpoints discovery/JWKS, callbacks e URLs de e-mail devem usar sempre `https://keycloak.blogdoft.dev`. Não coloque uma política Cloudflare Access geral nos endpoints OIDC públicos do Keycloak, pois ela pode bloquear os fluxos de login das aplicações. Use um hostname administrativo separado, como `keycloak-admin.blogdoft.dev`, protegido por Access.

Crie o túnel e a rota DNS em uma estação administrativa autenticada na Cloudflare. Guarde o arquivo JSON de credenciais fora do repositório:

```bash
cloudflared tunnel create k3s-apps
cloudflared tunnel route dns SEU-UUID immich.blogdoft.dev

kubectl create namespace cloudflared
kubectl -n cloudflared create secret generic cloudflared-tunnel-credentials \
  --from-file=credentials.json=/caminho-seguro/SEU-UUID.json
```

O manifesto abaixo é um exemplo para o **Immich real deste cluster**. Ele encaminha ao Service interno do Traefik (`traefik.kube-system.svc.cluster.local:80`) e preserva o hostname público. Antes de aplicá-lo, adicione `immich.blogdoft.dev` ao Ingress do Immich, apontando ao Service `immich-server` na porta `2283`, e emita o certificado público correspondente no Traefik. Assim, tráfego externo e LAN usam o mesmo hostname, enquanto o Tunnel não publica NodePorts nem qualquer porta do host.

DNS e Ingress são camadas diferentes: o DNS público aponta `immich.blogdoft.dev` para o Tunnel; o DNS LAN aponta o mesmo hostname para o Traefik local; o Ingress do Traefik aplica a rota com base no `Host` público preservado.

Substitua `SEU-UUID` e a imagem pelo digest da versão de `cloudflared` que você validou antes de aplicar.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: cloudflared
data:
  config.yml: |
    tunnel: SEU-UUID
    credentials-file: /etc/cloudflared/credentials/credentials.json
    no-autoupdate: true
    ingress:
      - hostname: immich.blogdoft.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - service: http_status:404
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflared
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: cloudflared
  template:
    metadata:
      labels:
        app.kubernetes.io/name: cloudflared
    spec:
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared@sha256:SUBSTITUA_PELO_DIGEST_VALIDADO
          args: ["tunnel", "--config", "/etc/cloudflared/config.yml", "run"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
            runAsNonRoot: true
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 128Mi
          volumeMounts:
            - name: config
              mountPath: /etc/cloudflared/config.yml
              subPath: config.yml
              readOnly: true
            - name: credentials
              mountPath: /etc/cloudflared/credentials
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: cloudflared-config
        - name: credentials
          secret:
            secretName: cloudflared-tunnel-credentials
```

Salve o manifesto fora de diretórios que o Argo CD já reconcilia, ou adicione-o ao repositório GitOps apropriado, e aplique:

```bash
kubectl apply -f cloudflared-immich.yaml
kubectl -n cloudflared rollout status deployment/cloudflared
kubectl -n cloudflared logs deployment/cloudflared --tail=100
```

Configure `immich.blogdoft.dev` como uma aplicação Cloudflare Access antes de testar o acesso público. Para cada nova aplicação, use uma regra separada por hostname público e adicione esse hostname ao Ingress correspondente; não crie uma regra genérica que encaminhe todos os hosts ao Traefik.

Por exemplo, as aplicações podem preservar seus hostnames públicos assim:

```yaml
ingress:
  - hostname: immich.blogdoft.dev
    service: http://traefik.kube-system.svc.cluster.local:80
  - hostname: forgejo.blogdoft.dev
    service: http://traefik.kube-system.svc.cluster.local:80
  - hostname: open-webui.blogdoft.dev
    service: http://traefik.kube-system.svc.cluster.local:80
  - hostname: keycloak.blogdoft.dev
    service: http://traefik.kube-system.svc.cluster.local:80
  - service: http_status:404
```

Não configure regras equivalentes a:

```yaml
service: http://192.168.1.212:6443
service: tcp://192.168.1.212:22
service: tcp://192.168.1.212:5432
service: http://192.168.1.212:11434
```

### 4. Proteger cada hostname no Cloudflare Access

Antes de publicar cada aplicação, crie uma aplicação Access no Cloudflare Zero Trust e exija:

- autenticação;
- MFA;
- usuários ou grupos explicitamente autorizados;
- ausência de uma política ampla como `Everyone`, salvo para uma aplicação deliberadamente pública.

Mesmo com Cloudflare Access, mantenha autenticação e autorização dentro de cada aplicação.

Não aplique Access de forma ampla ao hostname OIDC público do Keycloak. Para o console administrativo, use um hostname e Ingress separados e proteja somente esse hostname com Access.

## Gestão do cluster pelo enterprise

SSH por chave permite administrar o host diretamente:

```bash
ssh morgul 'kubectl get nodes'
ssh morgul 'kubectl get pods -A'
```

Para usar `kubectl` localmente no `enterprise`, copie o kubeconfig e proteja-o como uma credencial administrativa:

```bash
mkdir -p ~/.kube
scp sauron@morgul:/etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

Altere o `server:` de `127.0.0.1:6443` para o endereço LAN do `morgul`, por exemplo:

```yaml
server: https://192.168.1.212:6443
```

Teste:

```bash
kubectl get nodes
```

O kubeconfig padrão de K3s normalmente tem privilégios administrativos completos. Para múltiplas pessoas ou dispositivos com diferentes níveis de confiança, crie credenciais individuais com RBAC limitado.

## Verificação final

```bash
# Apache deve continuar parado
systemctl is-active apache2
systemctl is-enabled apache2

# Verifique as portas e processos expostos na LAN
sudo ss -lntup

# Verifique as regras de publicação do cluster
sudo k3s kubectl get ingress -A
sudo k3s kubectl get svc -A -o wide

# Verifique o Tunnel no K3s
kubectl -n cloudflared get deployment,pods
kubectl -n cloudflared rollout status deployment/cloudflared
kubectl -n cloudflared logs deployment/cloudflared --tail=100
```

Não compartilhe em tickets, chats ou repositórios o arquivo de credenciais do Tunnel, chaves privadas SSH, tokens Kubernetes, senhas ou o conteúdo de kubeconfigs administrativos.
