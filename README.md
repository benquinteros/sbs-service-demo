# Side-by-Side Deployment Demo

Kubernetes demo showing header-based routing with NGINX Ingress. Route traffic to different API versions using the `x-branch` HTTP header.

## Quick Start

```powershell
.\deploy.ps1
```

This script will:
1. Check dependencies (Docker, kubectl, kind)
2. Create Kubernetes cluster
3. Build and deploy the API
4. Test header-based routing

## Test It

```powershell
# Default (routes to main)
Invoke-RestMethod http://localhost/api/info

# Route to feature branch
Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch"="feature"}

# Route to main branch
Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch"="main"}
```

## Cleanup

```powershell
kind delete cluster --name sbs-demo
```

## How It Works

- **3 Deployments**: main (prod), feature (beta), dev (alpha)
- **NGINX Ingress**: Routes based on `x-branch` header value
- **Canary Pattern**: Uses NGINX canary annotations

## Requirements

- Docker Desktop
- kubectl ([install](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/))
- PowerShell

## Files

```
├── deploy.ps1              # One-command setup & test
├── src/BranchApi/          # .NET 8 API
├── k8s/                    # Kubernetes manifests
│   ├── namespace.yaml
│   ├── deployment-*.yaml   # 3 branch deployments
│   └── ingress.yaml        # Header routing
└── Dockerfile              # Multi-stage build
```
