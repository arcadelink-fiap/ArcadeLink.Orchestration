# ArcadeLink.Orchestration

Repositório de orquestração da Fase 3 do Tech Challenge NETT — concentra a infraestrutura
compartilhada que não pertence a nenhum microsserviço específico: API Gateway (Kong), stack de
observabilidade (Prometheus + Grafana), cache distribuído (Redis) e o script auxiliar de setup de
filas para a Function serverless. MongoDB é infraestrutura compartilhada do ponto de vista de
implantação, mas só o Catalog o utiliza hoje.

## Papel deste repositório

Postgres e RabbitMQ continuam no repo âncora da Fase 2, `ArcadeLink.Users/k8s/` — não foram movidos
para cá. Este repositório existe só para a infra **nova** da Fase 3, que não pertence a nenhum
serviço específico: Redis, Kong e a stack de observabilidade. Cada um dos cinco repositórios de
serviço continua com seus próprios manifestos (`deployment.yaml`/`service.yaml`/`configmap.yaml`/
`secret.yaml`) — este repo não substitui nada, só complementa.

## Stack de observabilidade escolhida

Opção A do edital: **Prometheus + Grafana**, via manifestos Kubernetes (`k8s/prometheus/`,
`k8s/grafana/`). Users e Catalog expõem `/metrics` (`prometheus-net.AspNetCore`, via
`app.UseHttpMetrics()` + `app.MapMetrics()` em `Program.cs`); o Prometheus faz scrape a cada 15s
(`k8s/prometheus/configmap.yaml`, `scrape_interval: 15s`, alvos `users-api:80` e `catalog-api:80`);
o dashboard do Grafana (`k8s/grafana/configmap-dashboards.yaml`) cobre latência (p95), contagem de
requisições por status HTTP e taxa de erro. Payments não expõe `/metrics` — não é um alvo de scrape.

**Lacuna conhecida**: o dashboard do Grafana não é auto-provisionado ainda — falta um `datasource`
apontando para o Prometheus e um `provider.yaml` associando o ConfigMap de dashboards à UI. Até isso
ser fechado, configure manualmente pela UI do Grafana:

1. `Configuration → Data Sources → Add data source → Prometheus`, URL `http://prometheus:9090`.
2. `Dashboards → Import`, colar o JSON de `k8s/grafana/configmap-dashboards.yaml`.

## API Gateway (Kong)

Ponto de entrada único para Users e Catalog (Payments não é exposto — só orientado a eventos).
Configuração declarativa (`k8s/kong/kong-declarative-config.yaml`, modo DB-less — `KONG_DATABASE=off`
no `Deployment`). Valida o JWT emitido pelo Users (plugin `jwt`, consumer `arcadelink-users` com o
segredo HS256) e injeta `X-User-Id`/`X-User-Role` nos serviços downstream (plugin `post-function`,
lendo `claims.sub` e a claim de role do token), que confiam nesses headers em vez de validar o token
eles mesmos (ver "Autenticação via Gateway" nos READMEs de Users e Catalog). Um plugin global
`request-transformer` remove `X-User-Id`/`X-User-Role` de qualquer requisição recebida do cliente,
para que ninguém finja ser outro usuário passando esses headers diretamente ao Gateway.

Rotas declaradas em `kong-declarative-config.yaml`:

| Rota | Método(s) | Path | Protegida? |
|---|---|---|---|
| `users-public-auth` | POST | `/auth` | Não |
| `users-protected` | GET, DELETE | `/users` | Sim (`jwt` + injeta headers) |
| `catalog-public-reads` | GET | `/games` | Não |
| `catalog-protected` | POST, PUT, DELETE | `/games` | Sim (`jwt` + injeta headers) |
| `catalog-library` | GET | `/library` | Sim (`jwt` + injeta headers) |

A Admin API do Kong (porta 8001) só escuta em `127.0.0.1` dentro do Pod (`KONG_ADMIN_LISTEN`) — não
é exposta pelo `Service` (só a porta 8000, de proxy), só acessível via `kubectl exec`/
`port-forward` direto no Pod, de propósito: evita que qualquer um sobrescreva a configuração inteira
via `POST /config`, já que o modo DB-less não tem autenticação própria na Admin API.

## Persistência poliglota (MongoDB) e Cache (Redis)

**MongoDB** é usado só pelo Catalog, para enriquecer `GET /games/{id}` com dados não-relacionais
opcionais (`GameDetails`: descrição rica, tags, screenshots) sem tocar no schema do Postgres — ver
"Persistência poliglota (MongoDB)" no [README do Catalog](../ArcadeLink.Catalog/README.md).

**Redis** é usado pelos três serviços de Fase 3 expostos a leitura/consulta: Users cacheia o lookup
de usuário por e-mail no login, Catalog cacheia as respostas de `GET /games`/`GET /games/{id}`
(cache-aside, TTL 60s), e Payments cacheia `Payments:ApprovalRate` (TTL 30s) para evitar reler
`IOptions` a cada mensagem consumida. Cada serviço usa sua própria chave de cache — não há
compartilhamento de dados entre serviços via Redis, só a mesma instância de infraestrutura. Ver o
README de cada serviço para o detalhe de TTLs e chaves.

## Serviços substituídos

`ArcadeLink.Notifications` (Web API sempre no ar, da Fase 2) foi substituído por
`ArcadeLink.NotificationsFunction` (Azure Function serverless, acionada por trigger RabbitMQ) — ver o
repositório [`ArcadeLink.NotificationsFunction`](../ArcadeLink.NotificationsFunction/README.md). O
`ArcadeLink.Notifications` original não recebe mais deploy (saiu do fluxo de `kubectl apply` da Fase
3 — não faz parte da ordem de subida abaixo), mas seu histórico Git continua existindo como registro
da Fase 2.

## Como subir o ambiente completo (Kubernetes)

1. `ArcadeLink.Users/k8s/` — infra herdada da Fase 2 (Postgres, RabbitMQ) + `users-api`. Vem primeiro
   porque tudo depende do Postgres/RabbitMQ compartilhados, e o Users é o serviço que emite o JWT que
   o Kong valida.
2. Este repo, `k8s/kong/`, `k8s/redis/`, `k8s/prometheus/` e `k8s/grafana/`:
   ```bash
   kubectl apply -f k8s/redis/ -f k8s/mongodb/ -f k8s/prometheus/ -f k8s/grafana/ -f k8s/kong/
   ```
3. `ArcadeLink.Catalog/k8s/` e `ArcadeLink.Payments/k8s/` — os outros dois serviços expostos/
   consumidores de evento.
4. `bash scripts/setup-function-queues.sh` (contra o RabbitMQ do cluster, tipicamente via
   `kubectl port-forward svc/rabbitmq 15672:15672` para a management API primeiro) — cria as duas
   filas que a Function precisa (`function-user-created-event`, `function-payment-processed-event`) e
   faz o bind delas aos exchanges que Users/Payments já publicam. Sem um consumer MassTransit rodando
   (como o antigo `ArcadeLink.Notifications`), nada mais cria essa topologia automaticamente.
5. Rodar a Function localmente: `cd` no repo `ArcadeLink.NotificationsFunction`, seguir o README de
   lá (`func start` — não há deploy real no Azure neste desafio, só emulação local).

`kubectl get pods` — todos devem chegar a `Running`. Para testar via Gateway:
`kubectl port-forward svc/kong 8000:8000` e usar os exemplos marcados `[Kong]` (headers
`X-User-Id`/`X-User-Role` já resolvidos pelo Gateway) nos arquivos `.http` de Users/Catalog, apontando
para `http://localhost:8000` em vez do host/porta direto do serviço.

## Variáveis de ambiente / configuração

Nenhum componente deste repositório é configurado via variável de ambiente do lado dos serviços
consumidores — Redis e MongoDB não têm secret/config própria aqui, só os `Service`s que expõem a
porta padrão para quem precisar deles:

| Componente | Service (DNS interno) | Porta padrão | Observação |
|---|---|---|---|
| Redis | `redis` | `6379` | Sem auth (dev). Usado por Users/Catalog/Payments — cada um lê `Redis__ConnectionString` do próprio `appsettings.json`/`ConfigMap`. |
| MongoDB | `mongodb` | `27017` | Sem auth (dev). Só o Catalog usa (`Mongo__ConnectionString`/`Mongo__Database`). |
| Kong | `kong` | `8000` (proxy) | Admin API (`8001`) só em `127.0.0.1` dentro do Pod, não exposta pelo `Service`. |
| Prometheus | `prometheus` | `9090` | Alvo do datasource do Grafana. |
| Grafana | `grafana` | `3000` | Dashboard precisa ser importado manualmente — ver seção de observabilidade acima. |

O segredo do JWT no plugin `jwt` do Kong (`kong-declarative-config.yaml`, consumer
`arcadelink-users`) precisa bater byte a byte com `Jwt:Key`/`Jwt__Key` do `ArcadeLink.Users` — hoje
os dois usam o mesmo placeholder de desenvolvimento
(`dev-only-change-me-arcadelink-shared-jwt-signing-key-32bytes-min`); se um mudar sem o outro, o
Kong começa a rejeitar todos os tokens emitidos pelo Users com 401.

## Pendências conhecidas (aceitas para o escopo do desafio)

- **Sem `NetworkPolicy`**: um Pod dentro do cluster ainda pode falar direto com `users-api`/
  `catalog-api`, contornando o Kong — nada impede hoje que um serviço vizinho no mesmo namespace
  pule a validação de JWT do Gateway.
- **Provisionamento automático do dashboard do Grafana incompleto** — falta datasource +
  `provider.yaml` (ver seção de observabilidade acima); hoje é um passo manual pela UI.
