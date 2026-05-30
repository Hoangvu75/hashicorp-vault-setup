#!/bin/bash
# test/run-k8s-test.sh

set -e
cd "$(dirname "$0")/.." || exit 1

echo "========================================"
echo " Kubernetes <-> Vault (VSO Operator)"
echo "========================================"

# 1. Lấy Root Token từ file (nếu có)
TOKEN="hvs.mDpsuweQF5kTqOGR3CjHk2Bz"
if [ -z "$TOKEN" ]; then
    read -p "Không tìm thấy file keys tự động. Vui lòng nhập Vault Root Token: " TOKEN
fi

# 2. Đẩy Data lên Vault và cấu hình AppRole
echo ""
echo "[1/4] Tạo Secret mẫu và cấu hình AppRole trên Vault..."

# Tạo dữ liệu Secret mẫu
curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" -d '{"type":"kv", "options":{"version":"2"}}' http://127.0.0.1:4510/v1/sys/mounts/secret || true
curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" -d '{
  "data": {
    "DB_HOST": "postgres.local",
    "DB_USER": "admin",
    "DB_PASS": "s3cr3t_p@ssw0rd",
    "API_KEY": "sk_live_123456789"
  }
}' http://127.0.0.1:4510/v1/secret/data/myapp && echo "  => Đã bơm Secret mẫu (secret/data/myapp)"

# Cấu hình AppRole (Vì Operator VSO không hỗ trợ Static Token auth)
curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" -d '{"type":"approle"}' http://127.0.0.1:4510/v1/sys/auth/approle || true
curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" -d '{"policy":"path \"secret/data/myapp\" { capabilities = [\"read\"] }"}' http://127.0.0.1:4510/v1/sys/policies/acl/myapp-policy
curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" -d '{"token_policies": ["myapp-policy"], "token_ttl": "1h", "token_max_ttl": "4h"}' http://127.0.0.1:4510/v1/auth/approle/role/myapp-role
curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" -d '{"role_id": "test-role-id"}' http://127.0.0.1:4510/v1/auth/approle/role/myapp-role/role-id
curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" -d '{"secret_id": "test-secret-id"}' http://127.0.0.1:4510/v1/auth/approle/role/myapp-role/custom-secret-id
echo "  => Đã cấu hình xác thực AppRole (RoleID: test-role-id)"

# 3. Cài đặt VSO qua YAML
echo ""
echo "[2/4] Cài đặt HashiCorp Vault Secrets Operator (VSO)..."
kubectl apply -f test/vso-install.yaml
echo "Đợi 3 giây để Kubernetes đăng ký các CRDs..."
sleep 3

# 4. Cấp phát AppRole credentials cho Operator và áp dụng cấu hình
echo ""
echo "[3/4] Đồng bộ Vault Secret sang Kubernetes Secret..."
# K8s Secret chứa SecretID của AppRole đã được định nghĩa trực tiếp bằng base64 trong file vault-sync.yaml
kubectl apply -f test/vault-sync.yaml

echo "Đợi 15 giây cho quá trình đồng bộ hoàn tất (VSO cần thời gian để gọi API Vault)..."
sleep 15
echo "K8s Native Secret đã được VSO tự động sinh ra:"
kubectl get secret myapp-k8s-secret || echo "Vẫn đang tạo..."

# 5. Deploy App
echo ""
echo "[4/4] Deploy ứng dụng test..."
kubectl apply -f test/connect-vault-deploy.yaml

echo ""
echo "Xem Logs của Pod (Chờ Pod khởi động)..."
sleep 5
kubectl logs -f -l app=vault-test-app --tail=20
