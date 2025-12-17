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

# Delete existing cluster if present
$clusters = kind get clusters 2>$null
if ($clusters -contains "sbs-demo") {
    Write-Host "Deleting existing cluster..." -ForegroundColor Yellow
    kind delete cluster --name sbs-demo
}

# Create cluster with port mappings
Write-Host "`nCreating Kubernetes cluster..." -ForegroundColor Green
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

# Install NGINX Ingress
Write-Host "`nInstalling NGINX Ingress..." -ForegroundColor Green
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml | Out-Null

Write-Host "Waiting for ingress controller (this takes ~30 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Wait for deployment to exist first
$retries = 0
while ($retries -lt 12) {
    $deployment = kubectl get deployment -n ingress-nginx ingress-nginx-controller 2>$null
    if ($deployment) { break }
    Start-Sleep -Seconds 5
    $retries++
}

# Now wait for pods to be ready
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s 2>$null | Out-Null

# Wait a bit more for webhook to be fully ready
Start-Sleep -Seconds 10

# Deploy application
Write-Host "`nDeploying application..." -ForegroundColor Green
kubectl apply -f k8s/namespace.yaml | Out-Null
kubectl apply -f k8s/deployment-main.yaml | Out-Null
kubectl apply -f k8s/deployment-feature.yaml | Out-Null
kubectl apply -f k8s/deployment-dev.yaml | Out-Null

Write-Host "Waiting for pods..." -ForegroundColor Yellow
kubectl wait --namespace sbs-demo --for=condition=ready pod --selector=app=branch-api --timeout=120s | Out-Null

# Deploy ingress (retry if webhook not ready)
Write-Host "Deploying ingress..." -ForegroundColor Yellow
$retries = 0
while ($retries -lt 5) {
    $result = kubectl apply -f k8s/ingress.yaml 2>&1
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 5
    $retries++
}

# Test routing
Write-Host "`n=== Testing Header-Based Routing ===" -ForegroundColor Cyan
Start-Sleep -Seconds 3

Write-Host "`n1. Default (no header) -> main branch:" -ForegroundColor Yellow
$result = Invoke-RestMethod http://localhost/api/info
Write-Host "   Branch: $($result.branch) | Version: $($result.version)" -ForegroundColor Green

Write-Host "`n2. With x-branch: feature -> feature branch:" -ForegroundColor Yellow
$result = Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch" = "feature" }
Write-Host "   Branch: $($result.branch) | Version: $($result.version)" -ForegroundColor Green

Write-Host "`n3. With x-branch: main -> main branch:" -ForegroundColor Yellow
$result = Invoke-RestMethod http://localhost/api/info -Headers @{"x-branch" = "main" }
Write-Host "   Branch: $($result.branch) | Version: $($result.version)" -ForegroundColor Green

# Show cluster status
Write-Host "`n=== Cluster Status ===" -ForegroundColor Cyan
kubectl get pods -n sbs-demo

Write-Host "`n=== SUCCESS! ===" -ForegroundColor Green
Write-Host "Test the API:  Invoke-RestMethod http://localhost/api/info -Headers @{`"x-branch`"=`"feature`"}" -ForegroundColor Gray
Write-Host "View logs:     kubectl logs -n sbs-demo -l branch=main" -ForegroundColor Gray
Write-Host "Cleanup:       kind delete cluster --name sbs-demo" -ForegroundColor Gray
