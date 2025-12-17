# Side-by-Side Deployment Demo

Kubernetes demo showcasing advanced traffic management with Istio service mesh and Helm. Route traffic to different API versions using custom HTTP headers - perfect for demonstrating canary deployments, A/B testing, and blue-green strategies.

## 🚀 Quick Start

```powershell
.\deploy.ps1
```

This script automatically:
1. Checks/installs dependencies (kind, helm, Istio)
2. Creates local Kubernetes cluster
3. Installs Istio service mesh with ingress gateway
4. Builds .NET 8 API container
5. Deploys 3 versions with Helm
6. Tests all routing scenarios

## 🧪 Test Header-Based Routing

```powershell
# Default (no header) → routes to main (v1.0.0)
Invoke-RestMethod http://localhost/api/info

# Custom header routing
Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch"="feature"}  # v2.0.0-beta
Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch"="dev"}      # v3.0.0-alpha
Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch"="main"}     # v1.0.0
```

## 📊 Visualize Traffic with Kiali

```powershell
kubectl port-forward -n istio-system svc/kiali 20001:20001
# Open http://localhost:20001 (username: admin, no password)
```

View real-time service mesh topology, traffic flow, and metrics.

## ⚙️ Customize Deployment

Edit [charts/sbs-demo/values.yaml](charts/sbs-demo/values.yaml):

```yaml
branches:
  main:
    replicas: 2              # Scale deployments
    version: v1              # Change version labels
    env:
      version: "1.0.0"       # Set environment variables

  feature:
    enabled: true            # Enable/disable branches
    headerValue: feature     # Custom header value
    replicas: 2
```

Add more branches by copying the pattern - no limit on routing rules.

## 📦 Manual Helm Commands

```powershell
# Install/upgrade
helm upgrade --install sbs-demo ./charts/sbs-demo --create-namespace

# View values
helm get values sbs-demo -n sbs-demo

# Uninstall
helm uninstall sbs-demo -n sbs-demo
```

## 🏗️ Architecture

**Stack:**
- **.NET 8** - Minimal API with health checks
- **Docker** - Multi-stage builds for optimized images
- **Kubernetes (kind)** - Local cluster for development
- **Istio 1.20** - Service mesh with automatic sidecar injection
- **Helm 3** - Package management and templating

**Traffic Flow:**

```mermaid
graph LR
    Client[HTTP Client]
    Gateway[Istio Gateway<br/>Port 80]
    VS[VirtualService<br/>Header Routing]

    MainSvc[branch-api-main<br/>Service]
    FeatureSvc[branch-api-feature<br/>Service]
    DevSvc[branch-api-dev<br/>Service]

    MainPod1[Main Pod v1<br/>+ Envoy Sidecar]
    MainPod2[Main Pod v1<br/>+ Envoy Sidecar]
    FeaturePod1[Feature Pod v2<br/>+ Envoy Sidecar]
    FeaturePod2[Feature Pod v2<br/>+ Envoy Sidecar]
    DevPod[Dev Pod v3<br/>+ Envoy Sidecar]

    Client -->|localhost:80| Gateway
    Gateway --> VS

    VS -->|no header or<br/>x-branch:main| MainSvc
    VS -->|x-branch:feature| FeatureSvc
    VS -->|x-branch:dev| DevSvc

    MainSvc --> MainPod1
    MainSvc --> MainPod2
    FeatureSvc --> FeaturePod1
    FeatureSvc --> FeaturePod2
    DevSvc --> DevPod

    style Client fill:#0d47a1,stroke:#1976d2,stroke-width:2px,color:#fff
    style Gateway fill:#e65100,stroke:#ff6f00,stroke-width:2px,color:#fff
    style VS fill:#e65100,stroke:#ff6f00,stroke-width:2px,color:#fff
    style MainSvc fill:#1b5e20,stroke:#43a047,stroke-width:2px,color:#fff
    style FeatureSvc fill:#e65100,stroke:#ff9800,stroke-width:2px,color:#fff
    style DevSvc fill:#880e4f,stroke:#c2185b,stroke-width:2px,color:#fff
    style MainPod1 fill:#2e7d32,stroke:#66bb6a,stroke-width:2px,color:#fff
    style MainPod2 fill:#2e7d32,stroke:#66bb6a,stroke-width:2px,color:#fff
    style FeaturePod1 fill:#ef6c00,stroke:#ffa726,stroke-width:2px,color:#fff
    style FeaturePod2 fill:#ef6c00,stroke:#ffa726,stroke-width:2px,color:#fff
    style DevPod fill:#ad1457,stroke:#ec407a,stroke-width:2px,color:#fff
```

**Istio Resources:**
- **Gateway**: Exposes port 80 on localhost
- **VirtualService**: Matches `x-branch` header values to route traffic
- **DestinationRule**: Defines service subsets (v1, v2, v3) based on pod labels

**Benefits:**
- ✅ Unlimited routing rules (no canary limitations)
- ✅ mTLS encryption between services
- ✅ Traffic visualization with Kiali
- ✅ Circuit breaking and retry logic
- ✅ Request tracing and metrics

## 🧹 Cleanup

```powershell
# Run cleanup script (prompts for confirmation)
.\cleanup.ps1

# Or manually delete cluster
kind delete cluster --name sbs-demo
```

## 📋 Requirements

- **Docker Desktop** (running)
- **kubectl** ([install](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/))
- **PowerShell** 5.1+

*Script auto-installs: kind, helm, Istio*

## 📁 Project Structure

```
├── deploy.ps1                    # One-command automation
├── cleanup.ps1                   # Cleanup and remove cluster
├── src/BranchApi/
│   ├── Program.cs                # .NET 8 Minimal API
│   └── BranchApi.csproj
├── charts/sbs-demo/              # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml               # Configuration
│   └── templates/
│       ├── deployment.yaml       # 3 versioned deployments
│       ├── service.yaml          # ClusterIP services
│       ├── namespace.yaml        # Istio injection enabled
│       ├── gateway.yaml          # Istio ingress
│       ├── virtualservice.yaml   # Header routing rules
│       └── destinationrule.yaml  # Service subsets
└── Dockerfile                    # Multi-stage build
```

## 🎯 Use Cases

- **Canary Deployments**: Route small percentage of traffic to new versions
- **A/B Testing**: Split traffic based on user attributes
- **Feature Flags**: Enable features for specific users via headers
- **Blue-Green**: Switch traffic between versions instantly
- **Developer Routing**: Route dev traffic to personal branches
