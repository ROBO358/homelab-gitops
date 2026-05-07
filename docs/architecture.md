# アーキテクチャ設計

## 凡例

- ✅ 構築済み
- 🔲 設計済み・未実装

---

## クラスタ概要 ✅

| 項目 | 値 |
|---|---|
| クラスタ名 | yh-cluster |
| OS | Talos Linux v1.12.6 |
| Kubernetes | v1.35.2 |
| Control Plane | 3 台（HA 構成） |
| Worker | 3 台 |
| クラスタ管理 | [yh-talos](https://github.com/ROBO358/yh-talos) リポジトリ |
| GitOps 管理 | [homelab-gitops](https://github.com/ROBO358/homelab-gitops) リポジトリ（本リポジトリ）|

### ノード構成

| ノード | ロール | IP |
|---|---|---|
| c1-k8s-yh | control-plane | 192.168.1.201 |
| c2-k8s-yh | control-plane | 192.168.1.202 |
| c3-k8s-yh | control-plane | 192.168.1.203 |
| w1-k8s-yh | worker | 192.168.1.211 |
| w2-k8s-yh | worker | 192.168.1.212 |
| w3-k8s-yh | worker | 192.168.1.213 |

クラスタ API VIP: `192.168.1.200:6443`（Talos Virtual IP）

---

## コンポーネント構成

### インフラ層

| コンポーネント | 状態 | 役割 |
|---|---|---|
| Flux v2.8.5 | ✅ | GitOps エンジン（main ブランチを 1 分ごとに同期）|
| Cilium 1.19.2 | ✅ | CNI / kube-proxy 置き換え / 暗号化 / LB / Gateway |
| Cilium Gateway API | ✅ | HTTP/HTTPS ルーティング（Envoy ベース）|
| cert-manager 1.16.2 | ✅ | TLS 証明書自動発行（Let's Encrypt DNS-01 / Cloudflare）|
| Dex v2 | ✅ | GitHub OIDC bridge（`dex.yh.k8s.tsuru.run`）|
| cloudflare-kubernetes-gateway v0.8.2 | ✅ | Cloudflare Tunnel Gateway API controller (pl4nty) — HTTPRoute で Tunnel ingress + DNS CNAME 自動管理 |
| Cloudflare Access | ✅ | `*-yh-k8s.tsuru.run` の認証ゲートウェイ（GitHub OAuth、wildcard policy）|
| Longhorn 1.11.1 | ✅ | 永続ストレージ（worker NVMe /var/mnt/longhorn、3x レプリケーション、default StorageClass）|
| External Secrets Operator | ✅ | 1Password SDK で yh-cluster vault のシークレットを同期 |

### オブザーバビリティ

| コンポーネント | 状態 | 役割 |
|---|---|---|
| Hubble Relay | ✅ | クラスタ内ネットワークフロー収集 |
| Hubble UI | ✅ | ネットワークフローの可視化 |
| kube-prometheus-stack | ✅ | 全メトリクス収集・Grafana・Alertmanager |
| Grafana Cloud | ✅ | SLI メトリクス長期保存・外部ダッシュボード |
| Healthchecks.io | ✅ | クラスタ全断の死活検知（Dead man's switch）|
| Cloudflare Workers | ✅ | 主要エンドポイントの外形監視（grafana-yh-k8s / dex-yh-k8s、毎分・初回失敗即通知）|

---

## OIDC 認証設計

### Phase A-1 ✅ — Dex を HTTPS 公開

```
LAN ユーザー（ブラウザ / kubelogin）
  │  HTTPS（LE prod cert、ブラウザ信頼済み）
  ▼
Cloudflare DNS: dex.yh.k8s.tsuru.run A 192.168.1.100（proxy OFF）
  │
  ▼
Gateway LB IP 192.168.1.100:443（Cilium L2 Announcements）
  │  TLS 終端（cert-manager が発行した dex-tls Secret）
  ▼
HTTPRoute → Service dex（port 5556）→ Dex Deployment（2 replicas）
  │  OAuth redirect
  ▼
GitHub OAuth
```

**Dex 構成:**
- Connector: GitHub（org: ROBO358）
- Static client: `kubelogin`（public client / PKCE、redirectURI: `localhost:8000/18000`）
- Storage: kubernetes（CRD）
- GitHub OAuth App credentials: 1Password `yh-cluster/dex-github-oauth` → ESO ExternalSecret → `dex-github-client` Secret

### Phase A-2 ✅ — kube-apiserver OIDC + kubelogin + RBAC

```
kubectl --context oidc@yh-cluster get pod -A
  │
  │ exec plugin: kubectl oidc-login get-token
  ▼
ブラウザ自動起動 → GitHub OAuth → Dex → ID Token (JWT)
  │ preferred_username=ROBO358, iss=https://dex.yh.k8s.tsuru.run, aud=kubelogin
  ▼
kubectl が Authorization: Bearer <JWT> でリクエスト
  │
  ▼
kube-apiserver（oidc-issuer-url: https://dex.yh.k8s.tsuru.run）
  │ JWKS を Dex から取得して JWT 検証 → username = "ROBO358"
  ▼
RBAC evaluation
  │ ClusterRoleBinding: oidc-user-robo358-view
  │   subjects: [{kind: User, name: ROBO358}]
  │   roleRef: {kind: ClusterRole, name: view}
  ▼
read-only 系 verb: allowed ✅  /  write 系・Secret: Forbidden ❌
```

**kube-apiserver OIDC フラグ（yh-talos `talconfig.yaml` で設定）:**

| フラグ | 値 | 備考 |
|---|---|---|
| `--oidc-issuer-url` | `https://dex.yh.k8s.tsuru.run` | Dex の issuer URL |
| `--oidc-client-id` | `kubelogin` | Dex static client ID |
| `--oidc-username-claim` | `preferred_username` | GitHub login `ROBO358` をそのまま使用 |
| `--oidc-groups-claim` | `groups` | 現時点で空配列（orgs なし）、将来の拡張用 |
| `--oidc-ca-file` | **未指定** | Dex cert は Let's Encrypt public CA。system bundle で検証可能 |

---

## TLS 証明書管理 ✅

### 設計方針

- LAN 公開サービスも **Let's Encrypt DNS-01** で証明書を発行する
  - DNS-01 は A レコードを検証しないため LAN IP (RFC1918) でも発行可能
  - public CA 証明書なので kube-apiserver・ブラウザが無設定で信頼（CA 配布不要）
- インターネット公開は **Cloudflare Tunnel (pl4nty Gateway API controller)** 経由。各 app は `HTTPRoute` を宣言するだけで Tunnel ingress + DNS CNAME が自動作成される
- 公開ホスト名はすべて `*-yh-k8s.tsuru.run` 形式（VAP で強制）。**Cloudflare Access** が wildcard policy で既定保護（GitHub OAuth、自分のみ許可）
- Cloudflare が edge で TLS 終端するため cluster 内は HTTP で完結 → cert-manager 不要
- 自己署名 CA は現時点で用途なし（YAGNI）

### ClusterIssuer 構成

| ClusterIssuer | 用途 |
|---|---|
| `letsencrypt-staging` | smoke test 専用。prod のレートリミット消費なし |
| `letsencrypt-prod` | 実サービス全般（Dex、Longhorn UI、Hubble UI 等） |

DNS-01 challenge は Cloudflare API Token で `tsuru.run` ゾーンへ TXT レコードを書き込み（Cloudflare では `yh.k8s.tsuru.run` はゾーンではなくサブドメインのため、ゾーン単位の `tsuru.run` で指定）。cert-manager の ClusterIssuer `dnsZones: [yh.k8s.tsuru.run]` は cert-manager 内部のセレクターであり Cloudflare の zone 設定とは独立。Token は 1Password → ESO 経由で自動同期。

### DNS: Cloudflare A レコードの登録方針

| 種別 | Cloudflare 設定 |
|---|---|
| サービス A レコード（`<svc>.yh.k8s.tsuru.run`） | → LB IP（例: `192.168.1.100`）、**proxy OFF（灰色雲）** |
| Tunnel CNAME（`<svc>-yh-k8s.tsuru.run`） | → `<tunnel-id>.cfargotunnel.com`、**proxy ON（オレンジ雲）**、pl4nty が HTTPRoute 検知時に自動 upsert |
| ACME TXT レコード（`_acme-challenge.*`） | cert-manager が自動で書き換え（短命） |

LAN 向け A レコードは proxy をオレンジ雲にすると Cloudflare edge に吸われて LAN に届かなくなるため必ず OFF にする。

---

## ネットワーク設計

### IP アドレス体系

| 用途 | レンジ / アドレス |
|---|---|
| ノード（LAN） | 192.168.1.201–213 |
| クラスタ API VIP | 192.168.1.200 |
| LoadBalancer プール | 192.168.1.100–199 |
| Gateway IP | 192.168.1.100（プールの先頭、L2 Announcements で広告）|
| Pod CIDR | Kubernetes IPAM（Cilium 管理）|

### Cilium 機能構成 ✅

```
kube-proxy: 無効（Cilium eBPF で代替）
IPAM: kubernetes モード
暗号化: WireGuard（Pod 間通信、nodeEncryption: false）
L2 Announcements: 有効（worker のみ ARP 広告、interface: enp1s0）
Hubble: Relay + UI 有効
envoy: 有効（standalone DaemonSet）
Gateway API: 有効（GatewayClass: cilium）
```

`GatewayClass` に `cilium` を使用し、外部の Ingress Controller を持ち込まない。

---

## トラフィックフロー

### LAN アクセス ✅（LoadBalancer サービス + Gateway API）

```
LAN ユーザー
  │
  │ ARP request (192.168.1.100)
  ▼
Cilium L2 Announcements
  │ elected worker が ARP reply
  ▼
Gateway LoadBalancer IP (192.168.1.100:80/443)  ✅
  │
  │ Cilium eBPF + Envoy
  ▼
HTTPRoute マッチング
  │
  ▼
Service → Pod
```

### インターネット公開（Cloudflare Tunnel + Access）✅

```
インターネットユーザー
  │ HTTPS（Cloudflare が TLS 終端）
  ▼
Cloudflare Access（GitHub OAuth 認証）
  │ 認証通過（Service Token も許可: Workers probe 用）
  ▼
Cloudflare Edge
  │ Cloudflare Tunnel（outbound 接続、ポート開放不要）
  ▼
cloudflared Pod（pl4nty controller が Deployment として管理）
  │ HTTP（クラスタ内部、tunnel 自体が暗号化済み）
  ▼
Service → Pod
```

**設計上のポイント:**
- 各 app は **`HTTPRoute` を宣言するだけ**で公開できる（Tunnel ingress + DNS CNAME は pl4nty が自動作成）
- LAN 向け（`*.yh.k8s.tsuru.run`）と Tunnel 向け（`*-yh-k8s.tsuru.run`）でドメインを分離
  - LAN: Gateway LB IP 経由（Cilium Gateway + cert-manager TLS）
  - Tunnel: `*-yh-k8s.tsuru.run` → pl4nty Gateway（`cloudflare-gateway/yh-cluster`）に parentRef
- Cloudflare Access が `*-yh-k8s.tsuru.run` 全体を wildcard app で既定保護（GitHub OAuth）
  - 追加設定なしで新 app を公開しても自分のみアクセス可
  - public 化が必要な場合は `cloudflare-zero-trust/terraform/apps/<svc>.tf` で per-app bypass policy を追加
- **Gateway 削除で Tunnel も消える**（pl4nty finalizer）→ `protect-cloudflare-gateway` VAP で flux-system-root 以外の DELETE を拒否
- TLS は Cloudflare が終端。LAN アクセスの TLS は cert-manager（✅）で別途管理

### Pod 間通信 ✅

```
Pod A ──WireGuard 暗号化トンネル──▶ Pod B
         (cilium_wg0 interface)
```

ホストネットワーク間の暗号化は無効（`nodeEncryption: false`）。

---

## Flux 同期構造

### 現在 ✅

```
GitRepository (flux-system/flux-system)
  └── Kustomization: flux-system  →  clusters/yh-cluster/
        ├── flux-system/               # Flux 本体
        ├── gateway-api-crds.yaml      # Kustomization: gateway-api-crds
        │     └── gateway-api-crds  →  infrastructure/gateway-api-crds/
        │           Gateway API v1.4.1 標準 CRDs (5 種)
        ├── cilium.yaml                # Kustomization: cilium + cilium-config (dependsOn: gateway-api-crds)
        │     ├── cilium           →  infrastructure/cilium/controller/
        │     │     HelmRepository + HelmRelease (Cilium 1.19.2, envoy + gatewayAPI 有効)
        │     └── cilium-config    →  infrastructure/cilium/config/
        │           CiliumLoadBalancerIPPool + CiliumL2AnnouncementPolicy
        ├── external-secrets.yaml      # Kustomization: external-secrets + external-secrets-config
        │     ├── external-secrets  →  infrastructure/external-secrets/controller/
        │     │     Namespace + HelmRepository + HelmRelease (ESO v2.3.0)
        │     └── external-secrets-config  →  infrastructure/external-secrets/config/
        │           ClusterSecretStore（1Password SDK、vault: yh-cluster）
        ├── longhorn.yaml              # Kustomization: longhorn
        │     └── longhorn  →  infrastructure/longhorn/controller/
        │           Namespace (pod-security: privileged) + HelmRepository + HelmRelease (Longhorn 1.11.1)
        │           defaultDataPath: /var/mnt/longhorn, 3x replicas, default StorageClass
        ├── cert-manager.yaml          # Kustomization: cert-manager + cert-manager-config
        │     ├── cert-manager      →  infrastructure/cert-manager/controller/
        │     │     Namespace + HelmRepository + HelmRelease (cert-manager v1.16.2)
        │     └── cert-manager-config  →  infrastructure/cert-manager/config/
        │           ExternalSecret（Cloudflare API Token）+ ClusterIssuer x2 (staging/prod)
        ├── dex.yaml                   # Kustomization: dex + dex-config (dependsOn: cert-manager-config + external-secrets-config)
        │     ├── dex              →  infrastructure/dex/controller/
        │     │     Namespace + HelmRepository + HelmRelease (Dex v2.44.0 / chart 0.24.0)
        │     └── dex-config       →  infrastructure/dex/config/
        │           ExternalSecret（GitHub OAuth client）+ Certificate（LE prod）
        │           + Gateway（dex-gateway、LB IP 192.168.1.100）+ HTTPRoute
        ├── rbac-humans.yaml           # Kustomization: rbac-humans
        │     └── rbac-humans      →  infrastructure/rbac-humans/
        │           ClusterRoleBinding: ROBO358(OIDC) → view
        ├── cloudflare-gateway.yaml    # Kustomization: cloudflare-gateway + cloudflare-gateway-config
        │     ├── cloudflare-gateway  →  infrastructure/cloudflare-gateway/controller/
        │     │     Namespace（cloudflare-gateway）+ GitRepository（pl4nty v0.8.2）
        │     │     ※ Kustomization path: pl4nty repo の ./config/default（controller 一式）
        │     └── cloudflare-gateway-config  →  infrastructure/cloudflare-gateway/config/
        │           ExternalSecret（cloudflare: ACCOUNT_ID + TOKEN）
        │           GatewayClass（cloudflare）+ Gateway（yh-cluster）+ ReferenceGrant
        ├── monitoring.yaml            # Kustomization: monitoring + monitoring-config
        │     ├── monitoring       →  infrastructure/monitoring/controller/
        │     │     Namespace + SA + HelmRepository + HelmRelease（kube-prometheus-stack 84.4.0）
        │     │     ExternalSecret x4（grafana-admin / grafana-cloud / healthchecks / discord-int-grafana）
        │     └── monitoring-config  →  infrastructure/monitoring/config/
        │           PrometheusRule x2（sli recording rules + alerts）
        │           CiliumNetworkPolicy（/metrics は Prometheus SA からのみ、cloudflare-gateway ns → port 3000 許可）
        │           Certificate + Gateway + HTTPRoute（grafana.yh.k8s.tsuru.run）
        │           HTTPRoute（grafana-yh-k8s.tsuru.run → cloudflare-gateway/yh-cluster）
        └── policies.yaml              # Kustomization: policies（ValidatingAdmissionPolicy）
              └── policies         →  infrastructure/policies/
                    restrict-tunnel-hostname（HTTPRoute hostname suffix *-yh-k8s.tsuru.run 強制）
                    protect-cloudflare-gateway（cloudflare-gateway ns の Gateway DELETE 保護）
                    restrict-rbac-rules（ClusterRole wildcard verb 禁止）
```

アプリごとの `HTTPRoute` / `Gateway` リソースは各アプリの namespace に配置する。

---

## シークレット管理設計 ✅

```
1Password
  ├── Vault: Private
  │     └── "Service Account Auth Token: yh-cluster"（ESO 認証用 SA Token）
  │           ※ task eso:bootstrap-secret で cluster に手動投入（Flux 管理外）
  └── Vault: yh-cluster（クラスタ固有シークレット）
        ├── cloudflare-gateway-api-token（pl4nty controller 用: account-id + api-token）
        ├── cloudflare-access-github-oauth（Cloudflare Access GitHub IdP: client-id + client-secret）
        ├── monitoring-grafana-admin（Grafana 管理者パスワード）
        ├── monitoring-grafana-cloud（Grafana Cloud remoteWrite: instance ID + API token）
        ├── monitoring-healthchecks（Healthchecks.io: webhook URL + project UUID + API key）
        ├── monitoring-discord-int-grafana（In-Cluster Alertmanager → Discord: webhook-url に /slack suffix 必須）
        ├── monitoring-discord-grafana-cloud（Grafana Cloud → Discord: ネイティブ Discord webhook URL）
        ├── monitoring-discord-worker（Cloudflare Workers probe → Discord: ネイティブ Discord webhook URL）
        ├── grafana-cloud-terraform（Terraform 用 Grafana SA token + connections token + stack ID）
        └── その他アプリシークレット

External Secrets Operator（ESO v2.3.0）
  └── ClusterSecretStore: onepassword（1Password SDK provider）
        └── ExternalSecret → Kubernetes Secret（各 namespace）
```

Flux 自身の GitHub 認証情報（deploy key）は `flux bootstrap` が生成し、
`flux-system/flux-system` Secret として管理（1Password 対象外）。

---

## 監視アーキテクチャ ✅

### 設計方針

クラスタが丸ごと落ちると In-Cluster の監視も道連れになるため、**3 層に分けて単一障害点を排除**する。

| 層 | コンポーネント | 役割 | クラスタ全断時 |
|---|---|---|---|
| In-Cluster | kube-prometheus-stack | 全メトリクス収集・詳細分析・即時アラート | 共倒れ |
| Cloud | Grafana Cloud（無料枠） | SLI 長期保存・外部ダッシュボード | 参照可能 |
| Blackbox | Healthchecks.io | heartbeat 途絶でクラスタ全断を検知 | 通知発火 |
| Blackbox | Cloudflare Workers | エンドポイント外形監視・Tunnel 死活確認 | 通知発火 |

### 全体構成図

```
┌─────────────────────────────────────────────────────┐
│                  yh-cluster (In-Cluster)             │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │ kube-prometheus-stack                         │   │
│  │                                               │   │
│  │  Prometheus                                   │   │
│  │  ├── node-exporter           5s scrape        │   │
│  │  ├── kube-state-metrics     15s scrape        │   │
│  │  ├── cAdvisor               15s scrape        │   │
│  │  ├── Cilium / CoreDNS       15s scrape        │   │
│  │  └── ServiceMonitor (apps)  15s scrape        │   │
│  │       保持期間: 7 日                           │   │
│  │                                               │   │
│  │  Recording Rules                              │   │
│  │  └── 生メトリクス → sli:* に事前集計          │   │
│  │                                               │   │
│  │  Grafana（詳細ダッシュボード）                 │   │
│  │  └── 開発者・運用者向け日常分析                │   │
│  │                                               │   │
│  │  Alertmanager                                 │   │
│  │  ├── Warning / Critical → Discord(int-grafana)│   │
│  │  └── Watchdog heartbeat ──────────────────────┼──→ Healthchecks.io
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  CiliumNetworkPolicy                                 │
│  └── /metrics は Prometheus SA からのみ許可          │
│                │                                     │
│                │ remoteWrite (sli:* のみ通過)        │
└────────────────┼─────────────────────────────────────┘
                 ▼
        Grafana Cloud（無料枠）
        ├── SLI メトリクス長期保存（14 日）
        ├── クラスタ健全性ダッシュボード
        ├── アラート（CertificateExpiringSoon / RemoteWriteAbsent）→ Discord(ext-grafana)
        └── クラスタ停止時も参照可能

Cloudflare Workers Cron Triggers（毎分）
└── 主要エンドポイントを外部から定期 probe（grafana-yh-k8s / dex-yh-k8s）
    ├── CF Access Service Token で認証（CF-Access-Client-Id/Secret ヘッダ）
    └── 初回失敗で即 Discord 通知
```

### メトリクスのフロー

```
全メトリクス（生）
  └── In-Cluster Prometheus のみ保持（7 日）

Recording Rules で事前集計
  ├── sli:http_error_rate:ratio_rate5m
  ├── sli:node_availability:bool
  ├── sli:pod_restart_rate:rate5m
  ├── sli:apiserver_availability:ratio_rate5m
  └── sli:certificate_expiry_days       ← cert-manager メトリクスから

sli:* のみ remoteWrite → Grafana Cloud（14 日保持）
```

### Scrape 設定

| ターゲット | scrape_interval | 備考 |
|---|---|---|
| node-exporter | 5s | ノードリソースは高頻度で収集 |
| kube-state-metrics | 15s | K8s オブジェクト状態 |
| cAdvisor | 15s | コンテナリソース |
| Cilium / CoreDNS | 15s | インフラコンポーネント |
| ServiceMonitor (apps) | 15s | アプリメトリクス |

### アラート設計

```
In-Cluster Alertmanager
  ├── NodeNotReady / DiskPressure / MemoryPressure
  ├── PodCrashLooping / OOMKilled
  ├── 証明書有効期限 7 日前（certmanager_certificate_expiration）
  ├── リソース枯渇（CPU / Memory 使用率閾値超過）
  └── Watchdog → Healthchecks.io（1 分ごと heartbeat）

Healthchecks.io
  └── heartbeat 途絶（クラスタ全断）→ メール通知

Cloudflare Workers
  └── エンドポイント無応答（Tunnel 障害・Gateway 障害）→ Webhook 通知
```

### TLS 証明書監視の方針

| 証明書の種類 | 監視方法 | 理由 |
|---|---|---|
| LAN 向け（cert-manager / Let's Encrypt）| Prometheus（`certmanager_certificate_expiration`）| Cloudflare が外部 TLS を終端するため外形監視では見えない |
| 外部向け（Cloudflare Edge）| Cloudflare ダッシュボード側で管理 | クラスタ管理外 |

### シークレット管理（既存パターンと統一）

```
1Password（yh-cluster vault）
  ├── monitoring-grafana-cloud       → ESO → Secret（username: Prometheus instance ID, password: Cloud Access Policy token）
  ├── monitoring-grafana-admin       → ESO → Secret（username + password: Grafana 管理者認証情報）
  ├── monitoring-healthchecks        → ESO → Secret（webhook-url: Healthchecks.io ping URL）
  ├── monitoring-discord-int-grafana → ESO → Secret（webhook-url: Discord URL + /slack suffix 必須、Alertmanager slack_configs 用）
  └── monitoring-discord-grafana-cloud → Terraform variable（Discord native URL、Grafana Cloud contact point 用）
```

### GitOps 配置

```
infrastructure/
  monitoring/
    controller/
      namespace.yaml
      sa.yaml                       # helm-monitoring SA + scoped CRB + ns admin RoleBinding
      helmrepository.yaml           # prometheus-community
      helmrelease.yaml              # kube-prometheus-stack（Alertmanager config / remoteWrite 設定込み）
      externalsecret-grafana-admin.yaml
      externalsecret-grafana-cloud.yaml
      externalsecret-healthchecks.yaml
      externalsecret-discord.yaml   # monitoring-discord-int-grafana（/slack suffix 必須）
      kustomization.yaml
    config/
      prometheusrule-sli.yaml       # sli:* Recording Rules（5種）
      prometheusrule-alerts.yaml    # クラスタアラート（Watchdog / Node / Pod / 証明書 / リソース）
      networkpolicy-metrics.yaml    # CiliumNetworkPolicy: intra-ns 自由 / Prometheus scrape / cloudflare-gateway → port 3000
      certificate.yaml              # grafana.yh.k8s.tsuru.run TLS（LAN 向け）
      gateway.yaml                  # Gateway（cilium, 192.168.1.101:443）
      httproute.yaml                # HTTPRoute → monitoring-grafana:80（LAN: grafana.yh.k8s.tsuru.run）
      httproute-tunnel.yaml         # HTTPRoute → monitoring-grafana:80（Tunnel: grafana-yh-k8s.tsuru.run）
      kustomization.yaml

clusters/yh-cluster/
  monitoring.yaml                   # 2 Kustomization（controller + config）
                                    # dependsOn: flux-rbac / longhorn / external-secrets-config / cert-manager-config
```

---

## Cilium bootstrap / Flux 引き継ぎパターン ✅

Cilium は **yh-talos** 側で Talos `inlineManifests` によりブートストラップされる。
Flux 導入後は HelmRelease が Helm adoption アノテーション経由で管理を引き継ぐ。

```
yh-talos (talhelper)
  ├── inlineManifests に最小構成の Cilium Helm Chart を埋め込み
  │     (adoption annotations: meta.helm.sh/release-name=cilium)
  └── クラスタ起動時に Cilium を展開

homelab-gitops (Flux)
  └── HelmRelease が既存リソースを adopt（Helm 3.2+ PR #7649）
        以降はすべての設定変更・バージョン更新をこのリポジトリで管理
```

Cilium バージョンは **両リポジトリの Taskfile.yml `CILIUM_VERSION` を必ず一致させる**。

---

## Flux RBAC 構成（Phase B + B-Next/1）✅

### 概要

kustomize-controller / helm-controller は **impersonation 経由**でのみ Kubernetes リソースを操作する。
controller 自身の SA には `impersonate` + Flux CRD 権限のみを付与し、`cluster-admin` は保持しない。

### Impersonation フロー

```
kustomize-controller pod (SA: kustomize-controller)
  ├── Bindings
  │     flux-impersonator ClusterRoleBinding → flux-impersonator ClusterRole
  │       rules: impersonate users/groups/serviceaccounts
  │     crd-controller-flux-system ClusterRoleBinding (Flux 既定)
  │       rules: Flux CRD CRUD
  │
  ├── Kustomization に spec.serviceAccountName が設定されている場合
  │     → controller は指定 SA を impersonate して API 操作
  │     例: cilium Kustomization → flux-cilium SA (cluster-admin via flux-cilium-applier)
  │
  └── spec.serviceAccountName が未設定の場合
        → --default-service-account=flux-system-root にフォールバック
        例: flux-rbac Kustomization → flux-system-root SA (cluster-admin via flux-system-root-applier)
```

### per-Kustomization SA 対応表

| Kustomization | SA 名 | ClusterRoleBinding |
|---|---|---|
| flux-system (root) | flux-system-root | flux-system-root-applier → cluster-admin |
| flux-rbac | (--default → flux-system-root) | 同上 |
| gateway-api-crds | flux-gateway-api-crds | flux-gateway-api-crds-applier → cluster-admin |
| cilium | flux-cilium | flux-cilium-applier → cluster-admin |
| cilium-config | flux-cilium-config | flux-cilium-config-applier → cluster-admin |
| external-secrets | flux-external-secrets | flux-external-secrets-applier → cluster-admin |
| external-secrets-config | flux-external-secrets-config | flux-external-secrets-config-applier → cluster-admin |
| longhorn | flux-longhorn | flux-longhorn-applier → cluster-admin |
| cert-manager | flux-cert-manager | flux-cert-manager-applier → cluster-admin |
| cert-manager-config | flux-cert-manager-config | flux-cert-manager-config-applier → cluster-admin |
| dex | flux-dex | flux-dex-applier → cluster-admin |
| dex-config | flux-dex-config | flux-dex-config-applier → cluster-admin |
| rbac-humans | flux-rbac-humans | flux-rbac-humans-applier → cluster-admin |
| cloudflare-gateway | flux-cloudflare-gateway | flux-cloudflare-gateway-applier → cluster-admin |
| cloudflare-gateway-config | flux-cloudflare-gateway-config | flux-cloudflare-gateway-config-applier → cluster-admin |
| monitoring | flux-monitoring | flux-monitoring-applier → cluster-admin |
| monitoring-config | flux-monitoring-config | flux-monitoring-config-applier → cluster-admin |

全 SA は `flux-system` namespace に配置し、label `app.kubernetes.io/part-of: flux-rbac` で識別する。

### Bootstrap SA の特殊処理

`flux-system-root` SA は `clusters/yh-cluster/flux-system/kustomization.yaml` の `resources` に直接追加した `flux-system-root.yaml` で管理する。`flux-rbac` Kustomization 管理下に置くと「flux-rbac 自身が必要とする SA を flux-rbac が作る」という chicken-and-egg が発生するため。

### per-HelmRelease SA 対応表（Phase B-Next/1）

helm-controller は各 HelmRelease の `spec.serviceAccountName` を impersonate して Helm 操作を行う。SA は HelmRelease と**同じ namespace** に配置する（helm-controller の SA 解決は HR の namespace を基準にするため）。

| HelmRelease | namespace | SA 名 | ClusterRoleBinding |
|---|---|---|---|
| cilium | kube-system | helm-cilium | helm-cilium-applier → cluster-admin |
| cert-manager | cert-manager | helm-cert-manager | helm-cert-manager-applier → cluster-admin |
| dex | dex | helm-dex | helm-dex-applier → cluster-admin |
| external-secrets | external-secrets | helm-external-secrets | helm-external-secrets-applier → cluster-admin |
| longhorn | longhorn-system | helm-longhorn | helm-longhorn-applier → cluster-admin |
| kube-prometheus-stack | monitoring | helm-monitoring | helm-monitoring-applier → cluster-admin |

各 SA は `infrastructure/<chart>/controller/sa.yaml` で定義し、component の controller Kustomization が管理する（flux-rbac 管理外）。理由: component 自身が namespace を作成するため、flux-rbac 実行時点では namespace が存在せず SA 作成が失敗する。

### Impersonation フロー（helm-controller）

```
helm-controller pod (SA: helm-controller)
  ├── Bindings
  │     flux-impersonator ClusterRoleBinding → flux-impersonator ClusterRole
  │       rules: impersonate users/groups/serviceaccounts
  │     crd-controller-flux-system ClusterRoleBinding (Flux 既定)
  │       rules: Flux CRD CRUD
  │
  └── HelmRelease に spec.serviceAccountName が設定されている場合
        → controller は指定 SA を impersonate して Helm install/upgrade/rollback
        例: cilium HR → helm-cilium SA (cluster-admin via helm-cilium-applier, kube-system NS)
```

**注意:** `--default-service-account` は kustomize-controller のみに設定（helm-controller には設定しない）。helm-controller は SA を HR 自身の namespace で解決するため、`--default-service-account` を設定すると全 HR namespace に同名 SA が必要になる。

### controller フラグ

| フラグ | 対象 | 値 | 目的 |
|---|---|---|---|
| `--no-cross-namespace-refs=true` | kustomize-controller, helm-controller | true | sourceRef がクロス NS 参照することを禁止 |
| `--default-service-account` | kustomize-controller のみ | flux-system-root | serviceAccountName 未設定の Kustomization に適用するデフォルト SA |

これらは `clusters/yh-cluster/flux-system/kustomization.yaml` の `patches` セクションで Deployment に JSON Patch 追加する。`flux bootstrap` で `gotk-*.yaml` が再生成されても `kustomization.yaml` の patches は保持される。

### security gain

- **audit log**: kustomize-controller は `system:serviceaccount:flux-system:flux-<name>`、helm-controller は `system:serviceaccount:<ns>:helm-<chart>` で操作元を識別可能
- **blast radius 縮小**: controller pod の token が漏洩しても `impersonate` 権のみ。cluster-admin 直接操作は不可
- **将来の tenant 設計基盤**: SA ごとに Role を絞ることで namespace-scoped 権限への移行が容易

---

## Cloudflare Tunnel + Access 設計 ✅

### ドメイン体系

| ドメイン形式 | 例 | 用途 | アクセス経路 |
|---|---|---|---|
| `<svc>.yh.k8s.tsuru.run` | `grafana.yh.k8s.tsuru.run` | LAN 専用 | Cilium Gateway LB IP（proxy OFF）|
| `<svc>-yh-k8s.tsuru.run` | `grafana-yh-k8s.tsuru.run` | インターネット公開 | Cloudflare Tunnel（proxy ON）|

### Tunnel 管理フロー

```
app 開発者
  │ HTTPRoute を infrastructure/<svc>/config/httproute-tunnel.yaml に追加
  │ parentRefs: [{name: yh-cluster, namespace: cloudflare-gateway}]
  │ hostnames: [<svc>-yh-k8s.tsuru.run]
  ▼
Flux が apply → pl4nty controller が HTTPRoute を検知
  ├── Cloudflare API: Tunnel ingress config 更新
  └── Cloudflare API: DNS CNAME upsert（<svc>-yh-k8s.tsuru.run → <tunnel-id>.cfargotunnel.com）

Cloudflare Access（wildcard *-yh-k8s.tsuru.run）
  └── 追加設定なしで自動保護（GitHub OAuth、自分のみ許可）
```

### Access ライフサイクル

Access policy は Tunnel / Gateway とは**独立した** Cloudflare アカウントリソース（Terraform 管理）。K8s manifest を削除しても Access app は残存する（「最後の砦」として機能）。

| 操作 | Tunnel / DNS CNAME | Access policy |
|---|---|---|
| HTTPRoute 追加 | 自動作成 | wildcard で自動保護（追加設定不要）|
| HTTPRoute 削除 | Tunnel ingress 削除・DNS orphan 残存 | 残存 |
| Gateway 削除（flux-system-root のみ可）| Tunnel 削除 | 残存 |
| `task cf-access:apply` | 影響なし | 作成 / 更新 |

### per-app Access 制御

| ケース | 必要な作業 |
|---|---|
| 新 app を「自分のみ」で公開 | HTTPRoute 追加のみ（wildcard が自動保護）|
| 新 app を public 化 | `cloudflare-zero-trust/terraform/apps/<svc>.tf` に bypass policy 追加 → `task cf-access:apply` |
| app を撤去 | HTTPRoute 削除 + `apps/<svc>.tf` 削除 → `task cf-access:apply` |

### Terraform 管理リソース（cloudflare-zero-trust/terraform/）

| リソース | 内容 |
|---|---|
| `identity-provider.tf` | GitHub OAuth IdP（`cloudflare-access-github-oauth` から client ID/Secret）|
| `application-wildcard.tf` | wildcard app `*-yh-k8s.tsuru.run` + Allow self only policy + Workers probe Service Token |
| `apps/` | per-app exception（bypass / specific allow。wildcard より具体的なホスト名が優先）|

### VAP（ValidatingAdmissionPolicy）

| ポリシー | 対象 | 内容 |
|---|---|---|
| `restrict-tunnel-hostname` | HTTPRoute（親: cloudflare Gateway）| hostname が `*-yh-k8s.tsuru.run` で終わらないと Deny |
| `protect-cloudflare-gateway` | Gateway DELETE（cloudflare-gateway ns）| flux-system-root 以外からの DELETE を Deny |
| `restrict-rbac-rules` | ClusterRole | `verbs: ["*"]` を custom API group で使用すると Deny |
