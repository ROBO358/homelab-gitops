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

### Next
- [ ] アプリケーションワークロードの追加
