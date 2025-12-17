#!/usr/bin/env pwsh
# Side-by-Side Deployment Demo - Complete Setup & Test
# Run this script to deploy everything and test header-based routing

$ErrorActionPreference = "Stop"

Write-Host "=== Side-by-Side Deployment Demo ===" -ForegroundColor Cyan

# Check Docker
Write-Host "`nChecking Docker..." -ForegroundColor Yellow
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker not found. Install Docker Desktop first." -ForegroundColor Red
    exit 1
}

# Install kind if needed
Write-Host "Checking kind..." -ForegroundColor Yellow
if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "Installing kind..." -ForegroundColor Green
    $kindDir = "$env:USERPROFILE\bin"
    if (-not (Test-Path $kindDir)) { New-Item -ItemType Directory -Path $kindDir | Out-Null }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64" -OutFile "$kindDir\kind.exe"
    $env:Path = "$kindDir;$env:Path"
}

# Install kubectl if needed
Write-Host "Checking kubectl..." -ForegroundColor Yellow
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: kubectl not found. Install from: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/" -ForegroundColor Red
    exit 1
}

# Install helm if needed
Write-Host "Checking helm..." -ForegroundColor Yellow
if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "Installing helm..." -ForegroundColor Green
    Invoke-WebRequest -Uri "https://get.helm.sh/helm-v3.13.0-windows-amd64.zip" -OutFile "$env:TEMP\helm.zip"
    Expand-Archive -Path "$env:TEMP\helm.zip" -DestinationPath "$env:TEMP\helm" -Force
    $helmDir = "$env:USERPROFILE\bin"
    if (-not (Test-Path $helmDir)) { New-Item -ItemType Directory -Path $helmDir | Out-Null }
    Copy-Item "$env:TEMP\helm\windows-amd64\helm.exe" -Destination "$helmDir\helm.exe" -Force
    Remove-Item "$env:TEMP\helm.zip" -Force
    Remove-Item "$env:TEMP\helm" -Recurse -Force
    $env:Path = "$helmDir;$env:Path"
}

# Check if cluster exists
$clusterExists = $false
try {
    $clusters = kind get clusters 2>&1
    if ($LASTEXITCODE -eq 0 -and $clusters -contains "sbs-demo") {
        $clusterExists = $true
        Write-Host "Found existing cluster 'sbs-demo'. Deleting..." -ForegroundColor Yellow
        kind delete cluster --name sbs-demo
    }
}
catch {
    # No clusters exist, continue
}

# Create cluster with port mappings
if (-not $clusterExists) {
    Write-Host "`nCreating Kubernetes cluster..." -ForegroundColor Green
}
else {
    Write-Host "`nRecreating Kubernetes cluster..." -ForegroundColor Green
}

$kindConfig = @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
  - containerPort: 443
    hostPort: 443
"@
$kindConfig | kind create cluster --name sbs-demo --config=-

# Build Docker image
Write-Host "`nBuilding API image..." -ForegroundColor Green
docker build -t branch-api:latest . -q

# Load image into kind
Write-Host "Loading image into cluster..." -ForegroundColor Green
kind load docker-image branch-api:latest --name sbs-demo

# Install Istio
Write-Host "`nInstalling Istio..." -ForegroundColor Green
$istioVersion = "1.20.0"
$istioDir = "$env:TEMP\istio-$istioVersion"

if (-not (Test-Path "$istioDir\bin\istioctl.exe")) {
    Write-Host "Downloading Istio $istioVersion..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://github.com/istio/istio/releases/download/$istioVersion/istio-$istioVersion-win.zip" -OutFile "$env:TEMP\istio.zip"
    Expand-Archive -Path "$env:TEMP\istio.zip" -DestinationPath "$env:TEMP" -Force
    Remove-Item "$env:TEMP\istio.zip" -Force
}

$istioctl = "$istioDir\bin\istioctl.exe"

Write-Host "Installing Istio control plane (this takes ~60 seconds)..." -ForegroundColor Yellow
& $istioctl install --set profile=demo --set values.gateways.istio-ingressgateway.type=NodePort -y | Out-Null

Write-Host "Waiting for Istio components..." -ForegroundColor Yellow
kubectl wait --namespace istio-system --for=condition=ready pod --selector=app=istiod --timeout=180s 2>$null | Out-Null
kubectl wait --namespace istio-system --for=condition=ready pod --selector=app=istio-ingressgateway --timeout=180s 2>$null | Out-Null

# Patch ingress gateway to use host ports for kind
Write-Host "Configuring ingress gateway for kind..." -ForegroundColor Yellow
$patchFile = Join-Path $env:TEMP "istio-patch-$(Get-Random).json"
'[{"op":"add","path":"/spec/template/spec/containers/0/ports/-","value":{"containerPort":8080,"hostPort":80,"name":"http-host","protocol":"TCP"}}]' | Out-File -FilePath $patchFile -Encoding utf8 -NoNewline
kubectl patch deployment istio-ingressgateway -n istio-system --type=json --patch-file $patchFile 2>$null | Out-Null
Remove-Item $patchFile -Force -ErrorAction SilentlyContinue
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=120s 2>$null | Out-Null

Start-Sleep -Seconds 10

# Deploy application with Helm
Write-Host "`nDeploying application with Helm..." -ForegroundColor Green
helm upgrade --install sbs-demo ./charts/sbs-demo --create-namespace --wait --timeout=3m | Out-Null

Write-Host "Waiting for pods..." -ForegroundColor Yellow
kubectl wait --namespace sbs-demo --for=condition=ready pod --selector=app=branch-api --timeout=120s | Out-Null

# Test routing
Write-Host "`n=== Testing Header-Based Routing ===" -ForegroundColor Cyan
Start-Sleep -Seconds 5

Write-Host "`n1. Default (no header) -> main branch:" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod http://localhost/api/info
    Write-Host "   Branch: $($result.branch) | Version: $($result.version)" -ForegroundColor Green
}
catch {
    Write-Host "   Failed: $_" -ForegroundColor Red
}

Write-Host "`n2. With x-branch: feature -> feature branch:" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch" = "feature" }
    Write-Host "   Branch: $($result.branch) | Version: $($result.version)" -ForegroundColor Green
}
catch {
    Write-Host "   Failed: $_" -ForegroundColor Red
}

Write-Host "`n3. With x-branch: dev -> dev branch:" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch" = "dev" }
    Write-Host "   Branch: $($result.branch) | Version: $($result.version)" -ForegroundColor Green
}
catch {
    Write-Host "   Failed: $_" -ForegroundColor Red
}

Write-Host "`n4. With x-branch: main -> main branch:" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch" = "main" }
    Write-Host "   Branch: $($result.branch) | Version: $($result.version)" -ForegroundColor Green
}
catch {
    Write-Host "   Failed: $_" -ForegroundColor Red
}

# Show cluster status
Write-Host "`n=== Cluster Status ===" -ForegroundColor Cyan
kubectl get pods -n sbs-demo

Write-Host "`n=== SUCCESS! ===" -ForegroundColor Green
Write-Host "Test the API:  Invoke-RestMethod http://localhost/api/info -Headers @{`"x-branch`"=`"feature`"}" -ForegroundColor Gray
Write-Host "View logs:     kubectl logs -n sbs-demo -l branch=main" -ForegroundColor Gray
Write-Host "Kiali dash:    kubectl port-forward -n istio-system svc/kiali 20001:20001" -ForegroundColor Gray
Write-Host "Cleanup:       .\cleanup.ps1" -ForegroundColor Gray
