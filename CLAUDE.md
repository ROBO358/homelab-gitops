# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

[Flux v2](https://fluxcd.io/) を使った Kubernetes クラスタの GitOps リポジトリ。
Talos Linux クラスタ（yh-cluster）の **ランタイム**（インフラ・ワークロード）を宣言的に管理する。

- クラスタ: `yh-cluster`（Talos v1.12.6 / Kubernetes v1.35.2）
- CNI: Cilium（kube-proxy 置き換え + L2 Announcements）
- Flux バージョン: v2.8.5
- GitHub リポジトリ: `ROBO358/homelab-gitops`
- 同期ブランチ: `main`（Flux が 1 分ごとにポーリング）

**Talos machine config、クラスタライフサイクル、および CNI (Cilium) のブートストラップ manifest** は別リポジトリ [`yh-talos`](https://github.com/ROBO358/yh-talos)（ローカル: `~/k8s/talhelper/`）で管理する。

## リポジトリ分担

| 責務 | [yh-talos](https://github.com/ROBO358/yh-talos) | homelab-gitops（ここ） |
|---|---|---|
| Talos machine config | ✓ | |
| クラスタ証明書・シークレット | ✓ | |
| クラスタライフサイクル (bootstrap/upgrade/rebuild) | ✓ | |
| **CNI (Cilium) のブートストラップ manifest** | ✓ | |
| Flux v2 本体・Kustomization | | ✓ |
| **CNI (Cilium) の日常運用** (HelmRelease / CRD) | | ✓ |
| その他インフラ (Ingress, Storage, Secrets 等) | | ✓ |
| アプリケーションワークロード | | ✓ |

### Cilium の管理原則

Cilium は **yh-talos 側で Talos の `inlineManifests` によりブートストラップ**され、クラスタ起動後はこのリポジトリの `HelmRelease` が管理を引き継ぐ。

- **日常の設定変更・バージョン更新はこのリポジトリで行う**（Flux が自動で反映）
- **ただしバージョンは yh-talos の `Taskfile.yml`（`CILIUM_VERSION` 変数）と必ず同期させる**。片方のみ更新すると次回リビルド時に想定外のバージョン変動が発生するため、**両リポジトリを同じ変更単位で更新**する
- Talos の `inlineManifests` は「存在しないリソースのみ作成」する仕様のため、Flux の HelmRelease と管理権競合しない

## ディレクトリ構成

```
clusters/
  yh-cluster/
    flux-system/         # Flux 本体のマニフェスト（flux bootstrap が生成）
      gotk-components.yaml   # Flux コンポーネント一式（直接編集しない）
      gotk-sync.yaml         # GitRepository + flux-system Kustomization（直接編集しない）
      kustomization.yaml     # resources + patches 追記は OK（gotk-*.yaml は編集しない）
      flux-system-root.yaml  # flux-system-root SA + binding（bootstrap、flux-system root が管理）
    cilium.yaml          # Cilium の Flux Kustomization 定義
    gateway-api-crds.yaml  # Gateway API CRDs の Flux Kustomization 定義
    external-secrets.yaml  # ESO の Flux Kustomization 定義
    flux-rbac.yaml         # Flux per-K SA + impersonator RBAC の Kustomization
infrastructure/
  cilium/                # CNI（ブートストラップは yh-talos 側の inlineManifests）
    controller/          # HelmRepository / HelmRelease
    config/              # CiliumLoadBalancerIPPool / CiliumL2AnnouncementPolicy
  gateway-api-crds/      # Gateway API v1.4.1 標準 CRDs
  external-secrets/      # External Secrets Operator
    controller/          # Namespace / HelmRepository / HelmRelease
    config/              # ClusterSecretStore（1Password SDK）
  longhorn/              # Longhorn 永続ストレージ
    controller/          # Namespace (pod-security: privileged) / HelmRepository / HelmRelease
  cert-manager/          # TLS 証明書自動発行（Let's Encrypt DNS-01 / Cloudflare）
    controller/          # Namespace / HelmRepository / HelmRelease
    config/              # ExternalSecret（Cloudflare Token）/ ClusterIssuer x2
  dex/                   # OIDC IdP bridge（GitHub connector、dex.yh.k8s.tsuru.run）
    controller/          # Namespace / HelmRepository / HelmRelease
    config/              # ExternalSecret（GitHub OAuth client）/ Certificate / Gateway / HTTPRoute
  rbac-humans/           # 人間ユーザー向け RBAC（OIDC subject → ClusterRole binding）
                         # ClusterRoleBinding: ROBO358(preferred_username) → view
  flux-rbac/             # Flux RBAC Phase B（per-Kustomization SA + impersonator）
                         # ClusterRole flux-impersonator / flux-<name> SA x11 / cluster-admin binding
```

`clusters/yh-cluster/` が Flux の sync パス。ここに Kustomization を追加すると Flux が自動で適用する。

## 重要な規則

- `clusters/yh-cluster/flux-system/` 以下の `gotk-*.yaml` は **flux が生成するため直接編集しない**
  - ただし `kustomization.yaml` の `resources` / `patches` セクションは編集 OK（Deployment args 追加、Kustomization SA パッチ等）
- 新しいインフラを追加するときは `infrastructure/<name>/` にマニフェストを置き、`clusters/yh-cluster/<name>.yaml` に Kustomization を追加する
- `dependsOn` で依存関係を明示する（例: cilium-config は cilium に依存）
- `prune: true` がデフォルト。削除したリソースは自動で Kubernetes からも消える

### 新しい Flux Kustomization を追加するときの手順（Phase B 以降）

RBAC Phase B 導入後、新しい Kustomization を追加する際は以下の手順が必要:

1. `infrastructure/flux-rbac/applier-serviceaccounts.yaml` に SA を追加:
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: flux-<component-name>
     namespace: flux-system
     labels:
       app.kubernetes.io/part-of: flux-rbac
   ```

2. `infrastructure/flux-rbac/applier-clusterrolebindings.yaml` に ClusterRoleBinding を追加:
   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: flux-<component-name>-applier
     labels:
       app.kubernetes.io/part-of: flux-rbac
   subjects:
     - kind: ServiceAccount
       name: flux-<component-name>
       namespace: flux-system
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: cluster-admin
   ```

3. `clusters/yh-cluster/<component>.yaml` の Kustomization に設定を追加:
   ```yaml
   spec:
     serviceAccountName: flux-<component-name>
     dependsOn:
       - name: flux-rbac
       # ... 他の依存関係
   ```

4. `flux-system-root.yaml` は flux-system root Kustomization が直接管理する bootstrap SA。flux-rbac 自体と root Kustomization が使用する。新しいコンポーネントはこれを使わず、専用 SA を作成する。

### Cilium HelmRelease 変更後の手動再起動

Cilium 1.19 の Helm チャートは DaemonSet・Operator Deployment いずれにも **checksum アノテーションがない**。
そのため `values` を変更した HelmRelease を push しても Pod は自動再起動されず、古い設定のまま動き続ける。

**HelmRelease を変更したら必ず以下を実行すること:**

| 変更内容 | 実行コマンド |
|---|---|
| agent のみ影響する設定（WireGuard 等） | `task cilium:restart` |
| operator も影響する設定（L2 Announcements 等） | `task cilium:restart-all` |

変更が反映されているかは agent ログで確認する（ConfigMap の値は desired state であり actual state ではない）:
```bash
kubectl -n kube-system logs -l k8s-app=cilium --since=1m | grep 'enable-l2-announcements\|enable-wireguard'
kubectl -n kube-system logs -l name=cilium-operator --since=1m | grep 'enable-l2-announcements'
```

### ESO onepasswordSDK provider の ExternalSecret 形式

`onepasswordSDK` provider は **2種類** の形式をサポートする。

**① `dataFrom.extract` — アイテムの全フィールドを一括取得（推奨）**

```yaml
spec:
  dataFrom:
    - extract:
        key: <item-name>      # vault: yh-cluster 内のアイテム名
```

同期後の Secret キーは 1Password のフィールドラベルと一致する（Password アイテムなら `password`）。

**② `data[].remoteRef` — 特定フィールドのみ取得**

`key` は `<item>/<field>` 形式（スラッシュ区切り）。`property` フィールドは**使わない**。

```yaml
spec:
  data:
    - secretKey: my-password
      remoteRef:
        key: <item-name>/password   # "item/field" 形式
```

**よくある誤り:** `key: <item-name>` + `property: <field>` の組み合わせはエラーになる（provider が op:// URI を要求するエラーを返す）。

### Helm chart の Capabilities 制約

Flux の helm-controller は HelmRelease upgrade 時に **新規インストールした CRD を `.Capabilities.APIVersions` で検出できない**場合がある。
Cilium の `gatewayAPI.gatewayClass.create` はデフォルト `"auto"`（CRD 存在時のみ作成）のため、GatewayClass が生成されないことがある。

**対処:** `gatewayAPI.gatewayClass.create: "true"` を明示して常に作成させる（現在の設定済み）。
新しい CRD に依存する Helm chart 設定を追加する際は同様に `auto` を避けること。

## ネットワーク情報

| 用途 | 値 |
|---|---|
| クラスタ API VIP | 192.168.1.200:6443 |
| LoadBalancer IP プール | 192.168.1.100 - 192.168.1.199 |
| L2 広告インターフェース | `enp1s0` |

## よく使うコマンド

すべての操作は `task` (Taskfile) 経由で行う。

```bash
task                        # タスク一覧
task flux:bootstrap         # Flux を GitHub bootstrap（rebuild 後の初回のみ）
task flux:status            # GitRepository / Kustomization / HelmRelease の状態確認
task flux:reconcile         # push 直後に手動で sync を強制
task flux:logs              # Flux エラーログを tail
task flux:uninstall         # Flux を削除（緊急時のみ）
task cilium:restart         # Cilium DaemonSet のみ rolling restart（ConfigMap 変更後）
task cilium:restart-all     # Cilium DaemonSet + Operator を rolling restart（L2 等全機能変更後）
task verify:cluster         # nodes + cilium / coredns pods
task verify:cilium          # Cilium adoption annotation / status / feature flags
task verify:encryption      # WireGuard 暗号化ステータス
task verify:hubble          # Hubble Relay / UI pods
task verify:l2              # CiliumLoadBalancerIPPool / CiliumL2AnnouncementPolicy
task verify:gateway         # Gateway API CRDs / GatewayClass / cilium-envoy DS
task verify:eso             # ESO pods + ClusterSecretStore Ready status
task verify:cert-manager    # cert-manager pods + ClusterIssuers Ready status
task test:cert-manager      # LE staging DNS-01 smoke test（1-3 分、最大 6 分）
task verify:dex             # Dex pods / Certificate / Gateway / HTTPRoute 状態
task test:dex               # OIDC discovery endpoint + TLS cert issuer 確認
task oidc:setup             # kubeconfig に oidc user / oidc@yh-cluster context を追加（krew oidc-login 要）
task verify:oidc            # OIDC ClusterRoleBinding + kube-apiserver OIDC フラグ確認
task test:oidc              # E2E: oidc@yh-cluster で pod 取得 OK / secret・create は Forbidden
task longhorn:ui            # Longhorn UI を http://localhost:8080 に port-forward（Ctrl-C で停止）
task verify:longhorn        # Longhorn pods / StorageClass / nodes 状態確認
task test:longhorn          # PVC → Pod → 書き込み → 読み出しの E2E 確認
task test:lb                # nginx LB デプロイ → EXTERNAL-IP 取得 → curl → cleanup
task test:gateway           # nginx + Gateway + HTTPRoute → EXTERNAL-IP 取得 → curl → cleanup
task test:eso               # ExternalSecret -> Secret 同期確認（1Password yh-cluster vault）
task eso:bootstrap-secret   # onepassword-token Secret を 1Password から作成（rebuild 後の初回のみ）
```

### Longhorn 前提条件（yh-talos 側）

Longhorn は以下の yh-talos 側設定が前提。**クラスタ再構築時は homelab-gitops より先に yh-talos 側を適用すること。**

| 必要事項 | yh-talos の対応箇所 |
|---|---|
| `siderolabs/iscsi-tools` system extension | `talconfig.yaml` worker `schematic.customization.systemExtensions` |
| `siderolabs/util-linux-tools` system extension | 同上 |
| `/var/mnt/longhorn` bind mount | `talconfig.yaml` worker `machine.kubelet.extraMounts` |

再構築後の確認:
```bash
# TALOSCONFIG=~/k8s/talhelper/clusterconfig/talosconfig
talosctl -n 192.168.1.211 -e 192.168.1.211 services | grep ext-iscsid  # Running であること
```

### クラスタ再構築後のチェックリスト

クラスタを再構築（または `flux:uninstall` → `flux:bootstrap`）した後に必要な手動手順:

```bash
# 1. Flux bootstrap（最初の一回のみ）
task flux:bootstrap

# 2. ESO 用 Secret を 1Password から投入（Flux 管理外の唯一の手動手順）
#    前提: op CLI がインストール済み・サインイン済み（op signin）
task eso:bootstrap-secret

# 3. Flux が全コンポーネントを同期するまで待つ
task flux:status

# 4. 動作確認
task verify:cilium
task verify:gateway
task verify:eso
```

`task eso:bootstrap-secret` を忘れると `ClusterSecretStore onepassword` が永続的に Not Ready になる（Flux はエラーを出さないが `task verify:eso` で検知できる）。

### 新サービスに TLS を付ける手順

cert-manager（`letsencrypt-prod`）でサービスに TLS 証明書を発行するテンプレート。

1. **Cloudflare に A レコードを追加**（手動）
   - `<svc>.yh.k8s.tsuru.run` → `192.168.1.100`（Gateway LB IP）
   - **proxy は OFF（灰色雲）**。オレンジ雲にすると Cloudflare edge に吸われ LAN に届かない

2. **Certificate リソースを作成**（各サービスの namespace に配置）
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: <svc>-tls
     namespace: <svc-namespace>
   spec:
     secretName: <svc>-tls
     commonName: <svc>.yh.k8s.tsuru.run
     dnsNames: [<svc>.yh.k8s.tsuru.run]
     issuerRef:
       kind: ClusterIssuer
       name: letsencrypt-prod
   ```

3. **Gateway の listener に TLS 設定を追加**
   ```yaml
   listeners:
     - name: https
       port: 443
       protocol: HTTPS
       tls:
         mode: Terminate
         certificateRefs:
           - name: <svc>-tls
   ```

4. **初回は letsencrypt-staging で動作確認してから prod に切り替え**（rate limit 対策）

### OIDC でログインする手順（ローカル一回限りのセットアップ）

前提: krew がインストール済みであること。

```bash
# 1. kubelogin plugin をインストール
kubectl krew install oidc-login

# 2. kubeconfig に oidc user / context を追加
task oidc:setup

# 3. OIDC context でアクセス（ブラウザが起動して GitHub 認証）
kubectl --context oidc@yh-cluster get pod -A

# 4. E2E 検証（read 許可 / write・Secret 拒否）
task test:oidc

# 5. 作業後は admin context に戻す
kubectl config use-context admin@yh-cluster
```

OIDC 認証のフロー: `kubectl oidc-login get-token` → ブラウザ → GitHub OAuth → Dex → ID Token (JWT)
  → kube-apiserver が JWKS 検証 → RBAC（`ClusterRoleBinding: oidc-user-robo358-view`）

### yh-talos 側との連携事項

kube-apiserver の OIDC 設定は `~/k8s/talhelper/talconfig.yaml` の `cluster.apiServer.extraArgs` で管理している。
homelab-gitops の Dex と連動しており、現在以下のフラグが設定済み:

| フラグ | 値 |
|---|---|
| `oidc-issuer-url` | `https://dex.yh.k8s.tsuru.run` |
| `oidc-client-id` | `kubelogin` |
| `oidc-username-claim` | `preferred_username` |
| `oidc-groups-claim` | `groups` |

Dex の issuer URL や static client ID を変更する場合は yh-talos 側の同フラグも合わせて更新し、`talhelper genconfig` + `talosctl apply-config` を実行すること。

## インフラ追加の手順

1. `infrastructure/<component>/controller/` に HelmRepository + HelmRelease を作成
2. `infrastructure/<component>/config/` に設定マニフェストを作成（必要な場合）
3. `clusters/yh-cluster/<component>.yaml` に Flux Kustomization を追加
4. `infrastructure/flux-rbac/` に SA + ClusterRoleBinding を追加（上記「新しい Flux Kustomization を追加するときの手順」参照）
5. `git add && git commit && git push` → Flux が自動で適用
