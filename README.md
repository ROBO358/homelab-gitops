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
    <component>.yaml        # Flux Kustomization per infrastructure component
infrastructure/
  <component>/
    controller/             # HelmRepository, HelmRelease, namespace
    config/                 # Component-specific CRs (IP pools, policies)
```

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

### Next
- [ ] Cloudflare Access の per-app 制御を K8s manifest 化 — 現状 Terraform 専用（`cloudflare-zero-trust/terraform/apps/`）のため、HTTPRoute 周辺で宣言的に書けるよう custom controller / annotation pattern を検討
- [ ] Gateway / HTTPRoute と Cloudflare Access のライフサイクル連動 — 現状 Access app は Gateway/HTTPRoute 削除後も残存（独立リソース）。manifest 削除時に自動 cleanup する仕組みを設計
- [ ] シークレットローテーション（grafana-cloud / cloudflare-api-token / dex-github-client / cloudflare-access-terraform-token の定期更新・自動化）
- [ ] アプリケーションワークロードの追加
