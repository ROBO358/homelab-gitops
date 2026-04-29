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
| cloudflared | 🔲 | Cloudflare Tunnel によるインターネット公開 |
| Longhorn 1.11.1 | ✅ | 永続ストレージ（worker NVMe /var/mnt/longhorn、3x レプリケーション、default StorageClass）|
| External Secrets Operator | ✅ | 1Password SDK で yh-cluster vault のシークレットを同期 |

### オブザーバビリティ

| コンポーネント | 状態 | 役割 |
|---|---|---|
| Hubble Relay | ✅ | クラスタ内ネットワークフロー収集 |
| Hubble UI | ✅ | ネットワークフローの可視化 |
| kube-prometheus-stack | 🔲 | 全メトリクス収集・Grafana・Alertmanager |
| Grafana Cloud | 🔲 | SLI メトリクス長期保存・外部ダッシュボード |
| Healthchecks.io | 🔲 | クラスタ全断の死活検知（Dead man's switch）|
| Cloudflare Workers | 🔲 | 主要エンドポイントの外形監視 |

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
- インターネット公開は **Cloudflare Tunnel (cloudflared)** 経由。Cloudflare が edge で TLS 終端するため cluster 内は HTTP で完結 → cert-manager 不要
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
| サービス A レコード（`<svc>.yh.k8s.tsuru.run`） | → `192.168.1.100`、**proxy OFF（灰色雲）** |
| ACME TXT レコード（`_acme-challenge.*`） | cert-manager が自動で書き換え（短命） |

proxy をオレンジ雲にすると Cloudflare edge に吸われて LAN に届かなくなるため必ず OFF にする。

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

### インターネット公開（Cloudflare Tunnel）🔲

```
インターネットユーザー
  │ HTTPS（Cloudflare が TLS 終端）
  ▼
Cloudflare Edge
  │ Cloudflare Tunnel（outbound 接続、ポート開放不要）
  ▼
cloudflared Pod（クラスタ内 Deployment）
  │ HTTP（クラスタ内部、tunnel 自体が暗号化済み）
  ▼
Gateway ClusterIP（L2 を経由しない）
  │ Cilium eBPF + Envoy
  ▼
HTTPRoute マッチング
  │
  ▼
Service → Pod
```

**設計上のポイント:**
- LAN・外部とも **同じ `Gateway` + `HTTPRoute`** を使う
- cloudflared は Gateway の **ClusterIP** を向く（LoadBalancer IP は不使用）
  - L2 Announcements の障害が外部公開に波及しない
  - クラスタ内で通信が完結し不要なネットワークラウンドトリップがない
- TLS は Cloudflare が終端。LAN アクセスの TLS は cert-manager（🔲）で別途管理

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
        └── rbac-humans.yaml           # Kustomization: rbac-humans
              └── rbac-humans      →  infrastructure/rbac-humans/
                    ClusterRoleBinding: ROBO358(OIDC) → view
```

### cloudflared 導入後 🔲

```
GitRepository (flux-system/flux-system)
  └── Kustomization: flux-system  →  clusters/yh-cluster/
        ├── flux-system/
        ├── gateway-api-crds.yaml
        ├── cilium.yaml
        ├── external-secrets.yaml      # 既存
        └── cloudflared.yaml           # Kustomization: cloudflared
              Deployment + ExternalSecret（ESO 経由で tunnel token を 1Password から取得）
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
        ├── cloudflared tunnel token（🔲 cloudflared 導入時）
        ├── その他アプリシークレット
        └── ...

External Secrets Operator（ESO v2.3.0）
  └── ClusterSecretStore: onepassword（1Password SDK provider）
        └── ExternalSecret → Kubernetes Secret（各 namespace）
```

Flux 自身の GitHub 認証情報（deploy key）は `flux bootstrap` が生成し、
`flux-system/flux-system` Secret として管理（1Password 対象外）。

---

## 監視アーキテクチャ 🔲

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
│  │  ├── Warning / Critical → Slack               │   │
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
        └── クラスタ停止時も参照可能

Cloudflare Workers Cron Triggers
└── 主要エンドポイントを外部から定期 probe
    └── cloudflared Tunnel の死活も兼ねる
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
  ├── grafana-cloud-credentials   → ESO → Secret（remoteWrite 認証）
  ├── grafana-admin-password      → ESO → Secret（in-cluster Grafana 管理者）
  ├── healthchecks-url            → ESO → Secret（Alertmanager Watchdog webhook）
  └── slack-webhook-url           → ESO → Secret（Alertmanager 通知先）
```

### GitOps 配置

```
infrastructure/
  monitoring/
    controller/
      namespace.yaml
      helmrepository.yaml           # prometheus-community
      helmrelease.yaml              # kube-prometheus-stack
      kustomization.yaml            #   scrape interval / remoteWrite / Alertmanager 設定込み
    config/
      prometheusrule-sli.yaml       # Recording Rules + アラート定義
      externalsecret-grafana-cloud.yaml
      externalsecret-grafana-admin.yaml
      externalsecret-healthchecks.yaml
      externalsecret-slack.yaml
      certificate.yaml              # grafana.yh.k8s.tsuru.run TLS
      gateway.yaml
      httproute.yaml
      kustomization.yaml

clusters/yh-cluster/
  monitoring.yaml                   # dependsOn: longhorn / external-secrets-config / cert-manager-config
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
