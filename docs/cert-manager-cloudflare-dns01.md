# Certificados públicos automáticos no K3s com cert-manager e Cloudflare DNS-01

## Objetivo

Emitir e renovar automaticamente certificados publicamente confiáveis para os hostnames `*.blogdoft.dev` publicados pelo K3s. Isso permite:

- acesso externo por Cloudflare Tunnel;
- acesso direto na LAN usando split DNS, mesmo durante indisponibilidade de internet;
- validação TLS correta por browsers, APIs e clientes OIDC;
- uso de um hostname canônico público, como `keycloak.blogdoft.dev`.

O certificado Universal SSL da Cloudflare protege apenas a borda Cloudflare. Quando o DNS local resolve `*.blogdoft.dev` diretamente para o Traefik, o Traefik precisa apresentar seu próprio certificado confiável. Um Cloudflare Origin Certificate **não** atende esse caso, pois browsers e clientes LAN não confiam nele.

Este manual usa ACME DNS-01 da Let's Encrypt com a API da Cloudflare. O cert-manager cria o TXT `_acme-challenge`, a Let's Encrypt valida o domínio e o cert-manager mantém a renovação.

## Decisão de arquitetura

Prefira certificados por aplicação/Ingress:

```text
immich.blogdoft.dev    -> Secret immich-blogdoft-dev-tls no namespace immich
keycloak.blogdoft.dev  -> Secret keycloak-blogdoft-dev-tls no namespace keycloak
forgejo.blogdoft.dev   -> Secret forgejo-blogdoft-dev-tls no namespace forgejo
```

Esse modelo limita o impacto da chave privada de cada certificado ao namespace da aplicação e funciona naturalmente com `Ingress` e ingress-shim. Um wildcard `*.blogdoft.dev` também é possível via DNS-01, mas o Secret TLS é namespaced; não o copie indiscriminadamente entre namespaces.

Para Keycloak e serviços OIDC, o hostname público é canônico. Use split DNS para que esse mesmo nome chegue ao Traefik dentro da LAN:

```text
Internet: keycloak.blogdoft.dev -> Cloudflare -> Tunnel -> Traefik
LAN:      keycloak.blogdoft.dev -> 192.168.1.212 -> Traefik
```

## 1. Verificar pré-requisitos

O cluster já usa cert-manager para certificados internos `home.arpa`, mas confirme o estado antes da mudança:

```bash
kubectl get namespace cert-manager
kubectl -n cert-manager get deployment,pods
kubectl get clusterissuer
kubectl get ingress -A
```

Não substitua o `ClusterIssuer` interno `home-arpa-ca`. O emissor ACME público será adicional e usado somente nos Ingress com hostnames `*.blogdoft.dev`.

## 2. Criar token Cloudflare de menor privilégio

No painel Cloudflare, crie um **API Token**, não uma Global API Key, limitado à zona `blogdoft.dev`.

Permissões mínimas:

- `Zone / DNS / Edit`;
- `Zone / Zone / Read`.

Recursos de zona: inclua apenas `blogdoft.dev`.

Armazene o token apenas como Secret Kubernetes; nunca o inclua em manifestos Git, `values.yaml`, tickets ou chats. Por padrão, Secrets referenciados por um `ClusterIssuer` ficam no namespace de recursos de cluster do cert-manager, normalmente `cert-manager`. Confirme essa configuração antes de criar o Secret.

O repositório inclui o template `cert-manager/cloudflare-dns-api-token-secret.yaml.template` e o instalador `cert-manager/install.sh`. O script cria o namespace de forma idempotente e usa `envsubst` para aplicar o Secret sem gravar o token em um arquivo gerado:

```bash
read -r -s -p 'Token da API Cloudflare: ' CLOUDFLARE_DNSTOKEN
echo
export CLOUDFLARE_DNSTOKEN
./cert-manager/install.sh
unset CLOUDFLARE_DNSTOKEN
```

O token não aparece no template nem é escrito em um arquivo pelo instalador. Evite registrá-lo em histórico de shell, `values.yaml`, manifestos Git, tickets ou chats.

## 3. Criar emissores ACME de teste e produção

Use primeiro o emissor de staging para validar DNS, permissões e Ingress sem consumir o limite de certificados de produção.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare-staging
spec:
  acme:
    email: admin@blogdoft.dev
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-staging-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-dns-api-token
              key: api-token
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare-prod
spec:
  acme:
    email: admin@blogdoft.dev
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-dns-api-token
              key: api-token
```

Salve o manifesto no repositório GitOps **sem o token** e aplique:

```bash
kubectl apply -f clusterissuers-letsencrypt-cloudflare.yaml
kubectl get clusterissuer letsencrypt-cloudflare-staging letsencrypt-cloudflare-prod
kubectl describe clusterissuer letsencrypt-cloudflare-staging
```

O estado esperado é `Ready=True`. Caso haja erro de permissão, confirme as duas permissões do token e se ele está limitado à zona correta.

## 4. Adicionar hostname público e TLS ao Ingress

O cert-manager ingress-shim observa Ingresses anotados. Ao encontrar `cert-manager.io/cluster-issuer` e uma entrada em `spec.tls`, ele cria um recurso `Certificate` e o Secret TLS automaticamente.

O exemplo abaixo usa o Immich real do cluster: o Service é `immich-server`, namespace `immich`, porta `2283`. Faça esta mudança na origem GitOps/Helm que administra o Ingress — não use `kubectl edit` em um recurso reconciliado pelo Argo CD.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: immich-server
  namespace: immich
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare-staging
spec:
  ingressClassName: traefik
  rules:
    # Preserve esta regra se o acesso legado home.arpa continuar necessário.
    - host: immich.home.arpa
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: immich-server
                port:
                  number: 2283
    - host: immich.blogdoft.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: immich-server
                port:
                  number: 2283
  tls:
    # Mantenha o Secret interno existente separado.
    - hosts:
        - immich.home.arpa
      secretName: immich-tls
    - hosts:
        - immich.blogdoft.dev
      secretName: immich-blogdoft-dev-tls
```

O exemplo acima troca o `ClusterIssuer` da anotação para staging. Como uma anotação vale para o Ingress inteiro, mantenha certificados internos e públicos em Ingresses separados se os dois dependem de emissores diferentes. A opção mais segura é preservar o Ingress `immich-server` atual para `home.arpa` e criar um novo Ingress, como `immich-public`, apenas para `immich.blogdoft.dev`, com a anotação ACME e o Secret público.

Exemplo de Ingress público separado:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: immich-public
  namespace: immich
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare-staging
spec:
  ingressClassName: traefik
  rules:
    - host: immich.blogdoft.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: immich-server
                port:
                  number: 2283
  tls:
    - hosts:
        - immich.blogdoft.dev
      secretName: immich-blogdoft-dev-tls
```

## 5. Validar staging e promover para produção

Depois de sincronizar o manifesto pelo Argo CD, acompanhe a emissão:

```bash
kubectl -n immich get certificate,certificaterequest,order,challenge
kubectl -n immich describe certificate immich-blogdoft-dev-tls
kubectl -n immich get secret immich-blogdoft-dev-tls
```

O certificado staging não será confiado por browsers. Quando a emissão estiver `Ready=True`, troque somente a anotação para produção:

```yaml
cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod
```

Depois acompanhe novamente os recursos. Teste de dentro da LAN, usando o split DNS:

```bash
curl -I --resolve immich.blogdoft.dev:443:192.168.1.212 https://immich.blogdoft.dev/
```

O certificado emitido deve ter `immich.blogdoft.dev` como SAN e ser confiado sem instalar uma CA local.

## 6. Publicar pelo Cloudflare Tunnel

Depois de o Ingress e TLS público estarem prontos, adicione o hostname ao ConfigMap do Deployment `cloudflared`:

```yaml
ingress:
  - hostname: immich.blogdoft.dev
    service: http://traefik.kube-system.svc.cluster.local:80
  - service: http_status:404
```

Não defina `httpHostHeader: immich.home.arpa` para aplicações que devem preservar o hostname público. O Traefik deve receber `Host: immich.blogdoft.dev` e casar com o Ingress público.

Crie o registro DNS do Tunnel e aplique o Deployment:

```bash
cloudflared tunnel route dns SEU-UUID immich.blogdoft.dev
kubectl -n cloudflared rollout restart deployment/cloudflared
kubectl -n cloudflared rollout status deployment/cloudflared
```

## 7. Migrar todos os serviços públicos

Sim, a emissão, renovação e atualização de Secrets pode ser automática no Kubernetes. A migração de todos os serviços não é automática sem declarar a intenção de cada um: cada serviço público precisa de um hostname, uma rota de Ingress e TLS/annotation ou `Certificate` correspondente.

Processo recomendado por aplicação:

1. Escolher o hostname público, como `forgejo.blogdoft.dev`.
2. Adicionar um Ingress público separado que preserve esse hostname e aponte ao Service existente.
3. Adicionar `cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod` e `spec.tls.secretName` exclusivo.
4. Adicionar a regra de hostname ao ConfigMap do Tunnel e criar o CNAME para o mesmo UUID.
5. Criar a política Cloudflare Access quando apropriado.
6. Validar tanto pela LAN sem internet quanto externamente.

O cert-manager renova os certificados antes do vencimento e atualiza o Secret TLS. O Traefik observa os Secrets e recarrega o material TLS automaticamente; não é necessário reiniciar as aplicações para uma renovação normal.

Para serviços OIDC, migre nesta ordem: Keycloak primeiro, depois as aplicações clientes. Mantenha o `issuer` e as redirect URIs no hostname público canônico. Não use Cloudflare Access como barreira global à frente dos endpoints OIDC públicos do Keycloak; separe e proteja o console administrativo em outro hostname.

## Operação e segurança

Verificações recorrentes:

```bash
kubectl get certificate -A
kubectl get certificaterequest,order,challenge -A
kubectl -n cert-manager logs deployment/cert-manager --tail=100
```

Boas práticas:

- Restrinja RBAC de criação/edição de Ingress e Certificate: quem altera um Ingress anotado pode solicitar certificados e direcionar Secrets.
- Mantenha o token Cloudflare com escopo apenas para a zona e permissões DNS necessárias.
- Monitore a expiração e o estado `Ready` dos recursos `Certificate`.
- Use o emissor staging em mudanças de DNS/manifesto e produção somente após validar.
- Não exponha a API Kubernetes, kubelet, SSH, banco de dados ou NodePorts via Tunnel.

## Referências oficiais

- [cert-manager: Ingress anotado e ingress-shim](https://cert-manager.io/docs/usage/ingress/)
- [cert-manager: Cloudflare DNS-01](https://cert-manager.io/v1.9-docs/configuration/acme/dns01/cloudflare/)
- [cert-manager: renovação de Certificate](https://cert-manager.io/docs/usage/certificate/)
