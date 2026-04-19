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
      kustomization.yaml
    cilium.yaml          # Cilium の Flux Kustomization 定義
infrastructure/
  cilium/                # CNI（ブートストラップは yh-talos 側の inlineManifests）
    controller/          # HelmRepository / HelmRelease
    config/              # CiliumLoadBalancerIPPool / CiliumL2AnnouncementPolicy
```

`clusters/yh-cluster/` が Flux の sync パス。ここに Kustomization を追加すると Flux が自動で適用する。

## 重要な規則

- `clusters/yh-cluster/flux-system/` 以下の `gotk-*.yaml` は **flux が生成するため直接編集しない**
- 新しいインフラを追加するときは `infrastructure/<name>/` にマニフェストを置き、`clusters/yh-cluster/<name>.yaml` に Kustomization を追加する
- `dependsOn` で依存関係を明示する（例: cilium-config は cilium に依存）
- `prune: true` がデフォルト。削除したリソースは自動で Kubernetes からも消える

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
task test:lb                # nginx LB デプロイ → EXTERNAL-IP 取得 → curl → cleanup
```

## インフラ追加の手順

1. `infrastructure/<component>/controller/` に HelmRepository + HelmRelease を作成
2. `infrastructure/<component>/config/` に設定マニフェストを作成（必要な場合）
3. `clusters/yh-cluster/<component>.yaml` に Flux Kustomization を追加
4. `git add && git commit && git push` → Flux が自動で適用
