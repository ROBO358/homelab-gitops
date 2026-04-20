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
| Cilium Gateway API | 🔲 | HTTP/HTTPS ルーティング（Envoy ベース）|
| cert-manager | 🔲 | TLS 証明書自動管理（LAN 向け）|
| cloudflared | 🔲 | Cloudflare Tunnel によるインターネット公開 |
| Longhorn | 🔲 | 永続ストレージ（ノードディスク使用）|
| External Secrets Operator | 🔲 | 1Password からシークレットを同期 |

### オブザーバビリティ

| コンポーネント | 状態 | 役割 |
|---|---|---|
| Hubble Relay | ✅ | クラスタ内ネットワークフロー収集 |
| Hubble UI | ✅ | ネットワークフローの可視化 |

---

## ネットワーク設計

### IP アドレス体系

| 用途 | レンジ / アドレス |
|---|---|
| ノード（LAN） | 192.168.1.201–213 |
| クラスタ API VIP | 192.168.1.200 |
| LoadBalancer プール | 192.168.1.100–199 |
| Gateway IP（予定） | 192.168.1.100（プールの先頭）|
| Pod CIDR | Kubernetes IPAM（Cilium 管理）|

### Cilium 機能構成 ✅

```
kube-proxy: 無効（Cilium eBPF で代替）
IPAM: kubernetes モード
暗号化: WireGuard（Pod 間通信、nodeEncryption: false）
L2 Announcements: 有効（worker のみ ARP 広告、interface: enp1s0）
Hubble: Relay + UI 有効
envoy: 無効（現在）→ Gateway API 導入時に有効化
```

### Gateway API 導入後の構成 🔲

```
envoy: 有効（standalone DaemonSet）
Gateway API: 有効
```

`GatewayClass` に `cilium` を使用し、外部の Ingress Controller を持ち込まない。

---

## トラフィックフロー

### LAN アクセス ✅（LoadBalancer サービス）/ 🔲（Gateway API）

```
LAN ユーザー
  │
  │ ARP request (192.168.1.100)
  ▼
Cilium L2 Announcements
  │ elected worker が ARP reply
  ▼
Gateway LoadBalancer IP (192.168.1.100:80/443)  🔲
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
        └── cilium.yaml                # Kustomization: cilium + cilium-config
              ├── cilium           →  infrastructure/cilium/controller/
              │     HelmRepository + HelmRelease (Cilium 1.19.2)
              └── cilium-config    →  infrastructure/cilium/config/
                    CiliumLoadBalancerIPPool + CiliumL2AnnouncementPolicy
```

### Gateway API + cloudflared 導入後 🔲

```
GitRepository (flux-system/flux-system)
  └── Kustomization: flux-system  →  clusters/yh-cluster/
        ├── flux-system/
        ├── cilium.yaml                # cilium + cilium-config（変更: envoy/gatewayAPI 有効化）
        ├── cloudflared.yaml           # Kustomization: cloudflared
        │     Deployment + Secret（External Secrets 経由）
        └── external-secrets.yaml     # Kustomization: external-secrets
              HelmRelease + ClusterSecretStore（1Password 接続）
```

アプリごとの `HTTPRoute` / `Gateway` リソースは各アプリの namespace に配置する。

---

## シークレット管理設計 🔲

```
1Password Vault
  └── "homelab" アイテム
        ├── cloudflared tunnel token
        ├── その他アプリシークレット
        └── ...

External Secrets Operator
  └── ClusterSecretStore（1Password Connect 経由）
        └── ExternalSecret → Kubernetes Secret（各 namespace）
```

Flux 自身の GitHub 認証情報（deploy key）は `flux bootstrap` が生成し、
`flux-system/flux-system` Secret として管理（1Password 対象外）。

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
