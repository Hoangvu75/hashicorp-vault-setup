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

# Step 1 is removed as vault-proxy is no longer used

# Step 2: Destroy Terraform resources (removes EC2 containers)
echo ""
echo "[2/4] Destroying Terraform resources..."
if [ -f "terraform/terraform.tfstate" ] && grep -q '"resources"' terraform/terraform.tfstate 2>/dev/null; then
    # Kiểm tra xem LocalStack có đang chạy không, nếu đã chết thì bỏ qua để tránh treo
    LS_STATUS=$($DOCKER_CMD inspect --format='{{.State.Status}}' localstack-main 2>/dev/null || echo "down")
    if [ "$LS_STATUS" != "running" ]; then
        echo "  LocalStack is down ($LS_STATUS), skipping terraform destroy to prevent hang."
    else
        $TF_CMD -chdir=terraform destroy -auto-approve || echo "  Terraform destroy failed or no resources to destroy"
    fi
else
    echo "  No Terraform state found, skipping terraform destroy"
fi

# Step 3: Force remove any remaining localstack-ec2 containers
echo ""
echo "[3/4] Force removing any remaining EC2 containers..."
REMAINING=$($DOCKER_CMD ps -aq --filter "name=localstack-ec2") 
if [ -n "$REMAINING" ]; then
    echo "$REMAINING" | xargs -r $DOCKER_CMD rm -f
    echo "  Removed remaining EC2 containers"
else
    echo "  No EC2 containers found"
fi

# Step 4: Clean Terraform state files and LocalStack volumes
echo ""
echo "[4/4] Cleaning Terraform state files, Docker Compose, and volumes..."
docker compose down -v 2>/dev/null || true

# Tắt ép các tiến trình Terraform bị treo (nếu có) trên Windows/WSL
pkill terraform 2>/dev/null || true
if command -v taskkill.exe &> /dev/null; then
    taskkill.exe /F /IM terraform.exe 2>/dev/null || true
fi

# Dọn dẹp mạnh tay các file cache của Terraform
rm -rf terraform/.terraform terraform/terraform.tfstate* terraform/.terraform.lock.hcl 2>/dev/null || true
# Đổi tên nếu file vẫn bị khóa (bởi IDE hoặc process ẩn)
if [ -d "terraform/.terraform" ]; then
    mv terraform/.terraform "terraform/.terraform.bak_$RANDOM" 2>/dev/null || true
fi
if [ -f "terraform/terraform.tfstate" ]; then
    mv terraform/terraform.tfstate "terraform/terraform.tfstate.bak_$RANDOM" 2>/dev/null || true
fi

rm -f docker-compose.yml.bak
rm -rf volume
echo "  Cleaned"

echo ""
echo "========================================"
echo " CLEANUP DONE"
echo "========================================"
