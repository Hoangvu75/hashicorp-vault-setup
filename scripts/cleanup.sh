#!/bin/bash
# scripts/cleanup.sh
# Dọn dẹp toàn bộ môi trường: EC2, Terraform state, LocalStack

set -e
cd "$(dirname "$0")/.." || exit 1

DOCKER_CMD="docker"
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    DOCKER_CMD="docker.exe"
fi

TF_CMD="terraform"
if ! command -v terraform &> /dev/null; then
    TF_CMD="terraform.exe"
fi

echo "========================================"
echo " CLEANUP: Destroying all environments"
echo "========================================"

# Step 1: Stop & remove vault-proxy
echo ""
echo "[1/4] Removing vault-proxy..."
$DOCKER_CMD rm -f vault-proxy 2>/dev/null && echo "  vault-proxy removed" || echo "  vault-proxy not found, skipping"

# Step 2: Destroy Terraform resources (removes EC2 containers)
echo ""
echo "[2/4] Destroying Terraform resources..."
if [ -f "terraform/terraform.tfstate" ] && [ "$(cat terraform/terraform.tfstate | grep '"resources"' | head -1)" != "" ]; then
    $TF_CMD -chdir=terraform destroy -auto-approve || echo "  Terraform destroy failed or no resources to destroy"
else
    echo "  No Terraform state found, skipping terraform destroy"
fi

# Step 3: Force remove any remaining localstack-ec2 containers
echo ""
echo "[3/4] Force removing any remaining EC2 containers..."
REMAINING=$($DOCKER_CMD ps -aq --filter "name=localstack-ec2") 
if [ -n "$REMAINING" ]; then
    echo "$REMAINING" | xargs $DOCKER_CMD rm -f
    echo "  Removed remaining EC2 containers"
else
    echo "  No EC2 containers found"
fi

# Step 4: Clean Terraform state files and LocalStack volumes
echo ""
echo "[4/4] Cleaning Terraform state files and volumes..."
rm -f terraform/terraform.tfstate
rm -f terraform/terraform.tfstate.backup
rm -f docker-compose.yml.bak
rm -rf volume
echo "  Cleaned"

echo ""
echo "========================================"
echo " CLEANUP DONE"
echo "========================================"
