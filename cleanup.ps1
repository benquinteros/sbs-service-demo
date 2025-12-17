#!/usr/bin/env pwsh
# Cleanup Script - Remove all deployed resources

$ErrorActionPreference = "Stop"

Write-Host "=== Cleanup Side-by-Side Demo ===" -ForegroundColor Cyan

# Check if cluster exists
$clusters = kind get clusters 2>$null
if ($clusters -notcontains "sbs-demo") {
    Write-Host "`nNo 'sbs-demo' cluster found. Nothing to clean up." -ForegroundColor Yellow
    exit 0
}

# Confirm deletion
Write-Host "`nThis will delete:" -ForegroundColor Yellow
Write-Host "  - kind cluster 'sbs-demo'" -ForegroundColor Gray
Write-Host "  - All deployed applications" -ForegroundColor Gray
Write-Host "  - Istio service mesh" -ForegroundColor Gray

$confirmation = Read-Host "`nContinue? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
    exit 0
}

# Delete cluster
Write-Host "`nDeleting kind cluster..." -ForegroundColor Green
kind delete cluster --name sbs-demo

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Green
Write-Host "To redeploy, run: .\deploy.ps1" -ForegroundColor Gray
