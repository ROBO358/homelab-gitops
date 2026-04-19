# homelab-gitops

Flux v2 GitOps repository for `yh-cluster` (Talos Linux cluster).

This repository manages:

- Flux v2 configuration and sync
- **Cilium runtime management** — HelmRelease + `CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy`
- Infrastructure components (LoadBalancer, Ingress, Storage, Secrets — see Roadmap)
- Application workloads

Talos machine configuration, cluster lifecycle, and **CNI (Cilium) bootstrap manifest** are managed in [yh-talos](https://github.com/ROBO358/yh-talos).

See [CLAUDE.md](./CLAUDE.md) for details on repository structure, the division of responsibilities between `yh-talos` and this repo, and the Cilium bootstrap / Flux handoff pattern.

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
- [x] MetalLB (to be replaced by Cilium L2 Announcements)

### In Progress
- [ ] **Cilium runtime** — HelmRelease + `CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy`
- [ ] Remove MetalLB after Cilium L2 Announcements is verified

### Next
- [ ] Ingress Controller (ingress-nginx) — HTTP/HTTPS routing
- [ ] Longhorn — persistent storage using node disks
- [ ] RBAC — cluster access control
- [ ] External Secrets Operator + 1Password — 1Password-backed Kubernetes Secrets (including Flux's own credentials)
