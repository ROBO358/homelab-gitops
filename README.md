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

### Next
- [ ] Longhorn — persistent storage using node disks
- [ ] RBAC — cluster access control
- [ ] External Secrets Operator + 1Password — 1Password-backed Kubernetes Secrets (including Flux's own credentials)
