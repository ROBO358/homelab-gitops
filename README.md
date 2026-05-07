# homelab-gitops

Flux v2 GitOps repository for `yh-cluster` (Talos Linux cluster).

This repository manages:

- Flux v2 configuration and sync
- **Cilium runtime management** — HelmRelease + `CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy`
- Infrastructure components (LoadBalancer, Gateway API, Storage, Secrets — see Roadmap)
- Application workloads

Talos machine configuration, cluster lifecycle, and **CNI (Cilium) bootstrap manifest** are managed in [yh-talos](https://github.com/ROBO358/yh-talos).

See [docs/architecture.md](./docs/architecture.md) for system design including network topology, traffic flows, and planned components.
See [CLAUDE.md](./CLAUDE.md) for repository structure, operational rules, and the Cilium bootstrap / Flux handoff pattern.

## Structure

```
clusters/
  yh-cluster/
    flux-system/            # Flux bootstrap artifacts (do not edit)
    apps.yaml               # App bootstrap Kustomization (→ apps/)
    <component>.yaml        # Flux Kustomization per infrastructure component
infrastructure/
  <component>/
    controller/             # HelmRepository, HelmRelease, namespace
    config/                 # Component-specific CRs (IP pools, policies)
apps/
  kustomization.yaml        # Lists all app sub-dirs (add 1 line per new app)
  <app>/                    # One directory per app — single unit of responsibility
    namespace.yaml          # Namespace + PodSecurity (owned by platform)
    rbac.yaml               # flux-<app> SA + ClusterRole + Binding
    referencegrant.yaml     # Allow HTTPRoute from <app> ns to cloudflare Gateway
    source.yaml             # GitRepository + Flux Kustomization for the app repo
```

**Boundary**: `infrastructure/` = shared cluster platform; `apps/` = per-app platform glue;
`<app>-k8s/manifests/` (separate repo) = per-app workload content.

## Roadmap

### Done
- [x] Flux v2 bootstrap
- [x] Cilium runtime — HelmRelease + WireGuard encryption + Hubble + `CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy`
- [x] Cilium Gateway API — `GatewayClass cilium` + Envoy DaemonSet + Gateway API v1.4.1 CRDs
- [x] External Secrets Operator + 1Password SDK — `ClusterSecretStore` syncing secrets from 1Password `yh-cluster` vault
- [x] Longhorn — persistent storage on worker NVMe (`/var/mnt/longhorn`) with 3x replication, default StorageClass
- [x] cert-manager — Let's Encrypt DNS-01 via Cloudflare (`letsencrypt-staging` + `letsencrypt-prod` ClusterIssuer)
- [x] Dex OIDC bridge — GitHub connector, HTTPS via cert-manager + Cilium Gateway (`dex.yh.k8s.tsuru.run`)
- [x] RBAC/OIDC Phase A-2 — kube-apiserver OIDC flags (yh-talos) + kubelogin + `ROBO358 → view` ClusterRoleBinding
- [x] RBAC/OIDC Phase B — Flux controller `cluster-admin` 剥離 / per-Kustomization SA + impersonation
- [x] RBAC/OIDC Phase B-Next/1 — helm-controller `cluster-admin` 剥離 / per-HelmRelease SA + impersonation
- [x] RBAC/OIDC Phase B-Next/2 — config SA + helm-dex の権限縮小（scoped ClusterRole + `helm-dex`: dex ns admin + 限定 cluster RBAC）

- [x] RBAC/OIDC Phase B-Next/3a — helm-longhorn の権限縮小（scoped ClusterRole + longhorn-system admin、`bind` を longhorn-role/cluster-admin に限定）
- [x] RBAC/OIDC Phase B-Next/3b — helm-external-secrets の権限縮小（scoped ClusterRole + external-secrets ns admin、`bind` を chart ClusterRole 5種に限定）
- [x] RBAC/OIDC Phase B-Next/3c — helm-cert-manager の権限縮小（scoped ClusterRole + cert-manager/kube-system admin、`bind` を chart ClusterRole 13種に限定）
- [x] RBAC/OIDC Phase B-Next/3d — helm-cilium の権限縮小（scoped ClusterRole + kube-system admin、`bind` を cilium/cilium-operator/hubble-ui に限定）
- [x] RBAC/OIDC Phase B-Next/3e — flux-{cilium,external-secrets,longhorn,cert-manager,dex} controller SA x5 の権限縮小（cluster-admin 全剥離 / scoped role + bind 限定）
- [x] RBAC/OIDC Phase C — Break-Glass kubeconfig 1Password 退避（`yh-cluster-break-glass-kubeconfig` document）/ ローカル admin context 全削除
- [x] RBAC/OIDC Phase D — ValidatingAdmissionPolicy で escalate/impersonate/cluster-admin 権限昇格を admission レベルで阻止（`restrict-rbac-rules` + `restrict-rbac-binding`、Deny mode）
- [x] Monitoring M1-M5 — kube-prometheus-stack + Grafana Cloud remoteWrite（sli:* のみ）+ Healthchecks.io heartbeat + Discord アラート + `grafana.yh.k8s.tsuru.run` TLS UI
- [x] Cloudflare Workers 外形監視 — `grafana-yh-k8s.tsuru.run` / `dex-yh-k8s.tsuru.run` を 5 分ごとに probe、障害時 Discord 通知（`workers/probe/`、`task worker:deploy`）
- [x] Cloudflare Access — GitHub OAuth 既定保護（`*-yh-k8s.tsuru.run` wildcard app + 自分のみ allow policy）Terraform 管理（`cloudflare-zero-trust/terraform/`、`task cf-access:apply`）
- [x] Cloudflare Tunnel — Gateway API 化（pl4nty/cloudflare-kubernetes-gateway v0.8.2）既存 Tunnel adopt / 各 app が HTTPRoute で宣言 / DNS CNAME 自動作成 / VAP でホスト名 suffix 強制 / Access wildcard で既定保護
- [x] App GitOps pattern — `apps/<app>/` 1 ディレクトリで完結する per-app 管理パターン確立（RBAC monotonicity 原則による責任分界 / `sample-app-k8s` テンプレートリポジトリ）

## アプリケーションを追加する

新しいアプリを `yh-cluster` に追加するための完全ガイド。前提: kubectl, git, gh CLI, op CLI が利用可能であること。

### 概要

```
ROBO358/<app-name>-k8s          # app リポ（あなたが作る）
├── src/                         # ソースコード + Dockerfile
├── manifests/                   # K8s manifests (workload content)
│   ├── kustomization.yaml       # images: で GHA が tag を更新する
│   └── ...                      # Deployment, Service, Certificate, etc.
└── .github/workflows/build.yml  # build → ghcr.io push → manifests tag 更新

ROBO358/homelab-gitops           # このリポ（platform 側）
└── apps/<app-name>/             # ★ここに 5 ファイルを追加するだけ
    ├── kustomization.yaml
    ├── namespace.yaml           # platform が Namespace を所有
    ├── rbac.yaml                # Flux SA + ClusterRole
    ├── referencegrant.yaml      # Cloudflare Tunnel の cross-ns 許可
    └── source.yaml              # GitRepository + Flux Kustomization
```

### 手順

#### Step 1 — app リポを作成する

```bash
# GitHub でリポジトリを作成
gh repo create ROBO358/<app-name>-k8s --public   # or --private

# sample-app-k8s をテンプレートとして clone
git clone --depth=1 https://github.com/ROBO358/sample-app-k8s /tmp/sample-app-k8s
cp -r /tmp/sample-app-k8s/. ~/k8s/<app-name>-k8s/
rm -rf ~/k8s/<app-name>-k8s/.git
cd ~/k8s/<app-name>-k8s
git init && git remote add origin https://github.com/ROBO358/<app-name>-k8s.git
```

#### Step 2 — ソースコードを実装する

`src/` の Dockerfile と nginx 設定を自分の実装に差し替える。nginx を使わない場合は Dockerfile ごと書き換えて OK。

#### Step 3 — manifests/ を編集する

```bash
# hostname と image name を置換
APP=<app-name>
sed -i "s/sample-app/${APP}/g" manifests/*.yaml

# Cilium Gateway の IP を確認して採番（重複チェック）
kubectl get svc -A | grep LoadBalancer
# → 未使用 IP を決定（例: 192.168.1.103）
sed -i "s/192.168.1.102/192.168.1.103/g" manifests/gateway.yaml
```

編集対象:

| ファイル | 変更箇所 |
|---|---|
| `manifests/kustomization.yaml` | `images[0].name` を `ghcr.io/ROBO358/<app-name>-k8s` に |
| `manifests/gateway.yaml` | `io.cilium/lb-ipam-ips` を採番した IP に |
| `manifests/httproute.yaml` | `hostnames` を `<app-name>.yh.k8s.tsuru.run` に |
| `manifests/httproute-tunnel.yaml` | `hostnames` を `<app-name>-yh-k8s.tsuru.run` に（末尾 `-yh-k8s.tsuru.run` 必須）|
| `manifests/certificate.yaml` | `commonName` / `dnsNames` を `<app-name>.yh.k8s.tsuru.run` に |

#### Step 4 — app リポを push して GHA を通す

```bash
git add -A && git commit -m "feat: initial commit"
git push -u origin main

# GHA が完了するまで待つ（約 2-3 分）
gh run watch -R ROBO358/<app-name>-k8s

# ghcr の package を Public に設定（public リポの場合）
# https://github.com/users/ROBO358/packages/container/<app-name>-k8s
# → Package settings → Change visibility → Public
```

GHA が成功すると `manifests/kustomization.yaml` に `sha-xxxxxxx` の bot commit が入る。

#### Step 5 — DNS A レコードを追加する（Cloudflare）

Cloudflare DNS 管理画面で:

- **Type**: A
- **Name**: `<app-name>.yh.k8s.tsuru.run`
- **IPv4 address**: 採番した IP（例: `192.168.1.103`）
- **Proxy status**: **DNS only（灰色雲）** ← オレンジ雲にしないこと

#### Step 6 — homelab-gitops に app を登録する

```bash
cd ~/k8s/homelab-gitops

# テンプレートをコピーして置換
cp -r apps/sample-app apps/<app-name>
sed -i "s/sample-app/<app-name>/g" apps/<app-name>/*.yaml

# source.yaml の GitRepository URL を新リポに変更
# → url: https://github.com/ROBO358/<app-name>-k8s

# apps/kustomization.yaml に 1 行追記
echo "  - <app-name>" >> apps/kustomization.yaml
```

**注意**: `infrastructure/flux-rbac/` や `infrastructure/cloudflare-gateway/config/` には**触らない**（app ごとの RBAC は `apps/<app-name>/rbac.yaml` に集約されている）。

```bash
git add apps/
git commit -m "feat(apps): add <app-name>"
git push
```

#### Step 7 — Flux で同期して確認する

```bash
task flux:reconcile

# apps Kustomization が Ready になるまで待つ
kubectl -n flux-system get kustomization apps -w

# app の Kustomization も確認
kubectl -n flux-system get kustomization <app-name> -w

# Pod が Running になるまで待つ
kubectl -n <app-name> get pod -w
```

#### Step 8 — アクセス確認

```bash
# LAN（要 WireGuard VPN）
curl -k https://<app-name>.yh.k8s.tsuru.run

# Internet（Cloudflare Tunnel + Access）
# ブラウザで https://<app-name>-yh-k8s.tsuru.run → GitHub OAuth でログイン
```

### トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| `HTTPRoute Accepted=False` | `sample-app` namespace の ReferenceGrant が入っていない | `kubectl -n cloudflare-gateway get referencegrant` で確認。`apps` Kustomization が Ready か確認 |
| `ImagePullBackOff` | ghcr image が private | GitHub UI で package visibility を Public に変更 |
| `Forbidden` でリソース作成失敗 | `flux-<app>-role` の verbs が足りない | `apps/<app>/rbac.yaml` に不足 API group / verbs を追加 |
| cert-manager が証明書を発行しない | DNS A レコードが Cloudflare proxy ON になっている | DNS proxy を **DNS only**（灰色雲）に変更 |
| `context deadline exceeded` | 初回 PVC Binding が遅い | `kubectl -n <app-name> get pvc` で Bound になるまで待つ（Longhorn が初期化中）|
| Tunnel の HTTPRoute が `No endpoints` | `ciliumnetworkpolicy.yaml` で cloudflare-gateway ns からのアクセスが deny | CNP で `io.kubernetes.pod.namespace: cloudflare-gateway` からの ingress を許可しているか確認 |
| Pod が `Init:0/1` のまま進まない（RWO PVC 使用時） | RollingUpdate で新 Pod が先に起動しようとして PVC attachment deadlock | `manifests/deployment.yaml` に `rollingUpdate.maxSurge: 0` を設定しているか確認 |
| `container has runAsNonRoot and image has non-numeric user` | nginx-unprivileged UID が文字列 "nginx" で Kubernetes が検証できない | `securityContext.runAsUser: 101` を nginx container に追加 |
| `touch: /var/lib/sample-app/.mtime: Permission denied` | Longhorn PVC が root 所有で UID 101 が書けない | pod spec の `securityContext.fsGroup: 101` を確認 |
| `can't create /usr/share/nginx/html/index.html: Permission denied` | image 内の `/usr/share/nginx/html` が root 所有 | nginx container に `emptyDir` を `/usr/share/nginx/html` でマウントしているか確認 |

### public 化する場合（Cloudflare Access bypass）

デフォルトでは `*-yh-k8s.tsuru.run` 全体が GitHub OAuth で保護されている（自分のみアクセス可）。特定 app を public にするには:

```bash
# cloudflare-zero-trust/terraform/apps/<app-name>.tf を作成
cat > cloudflare-zero-trust/terraform/apps/<app-name>.tf << 'EOF'
resource "cloudflare_zero_trust_access_application" "<app_name>_public" {
  account_id       = var.account_id
  name             = "<app-name> (public)"
  domain           = "<app-name>-yh-k8s.tsuru.run"
  type             = "self_hosted"
  session_duration = "24h"
}
resource "cloudflare_zero_trust_access_policy" "<app_name>_bypass" {
  account_id     = var.account_id
  application_id = cloudflare_zero_trust_access_application.<app_name>_public.id
  name           = "Bypass everyone"
  decision       = "bypass"
  precedence     = 1
  include        = [{ everyone = {} }]
}
EOF

task cf-access:apply
```

### Next
- [ ] Cloudflare Access の per-app 制御を K8s manifest 化 — 現状 Terraform 専用（`cloudflare-zero-trust/terraform/apps/`）のため、HTTPRoute 周辺で宣言的に書けるよう custom controller / annotation pattern を検討
- [ ] Gateway / HTTPRoute と Cloudflare Access のライフサイクル連動 — 現状 Access app は Gateway/HTTPRoute 削除後も残存（独立リソース）。manifest 削除時に自動 cleanup する仕組みを設計
- [ ] シークレットローテーション（grafana-cloud / cloudflare-api-token / dex-github-client / cloudflare-access-terraform-token の定期更新・自動化）
- [ ] Flux Image Automation Controller — 現状 GHA bot commit で image tag 更新。Flux の ImageRepository + ImagePolicy + ImageUpdateAutomation に移行することで app リポへの GHA bot commit を廃止できる
