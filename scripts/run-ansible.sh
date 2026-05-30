#!/bin/bash
# scripts/run-ansible.sh
# Chạy toàn bộ quá trình: generate inventory -> cài Ansible trên Node 1 -> deploy Vault cluster

set -e
cd "$(dirname "$0")/.." || exit 1

# ─── Detect commands ──────────────────────────────────────────────────────────
DOCKER_CMD="docker"
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    DOCKER_CMD="docker.exe"
fi

TF_CMD="terraform"
if ! command -v terraform &> /dev/null; then
    TF_CMD="terraform.exe"
fi

# ─── Helper: Wait until ALL 3 EC2 containers are Running ─────────────────────
wait_for_ec2_containers() {
    local max_retries=30
    local retry_interval=5
    echo ""
    echo "  Waiting for all 3 EC2 containers to be Running..."

    for i in $(seq 1 $max_retries); do
        TOTAL=$($DOCKER_CMD ps -a --filter "name=localstack-ec2" --format "{{.Names}}" | wc -l | tr -d ' ')
        RUNNING=$($DOCKER_CMD ps --filter "name=localstack-ec2" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')
        PAUSED=$($DOCKER_CMD ps -a --filter "name=localstack-ec2" --filter "status=paused" --format "{{.Names}}")

        echo "  Attempt $i/$max_retries - Total EC2 containers: $TOTAL, Running: $RUNNING"

        # If there are paused containers, unpause them
        if [ -n "$PAUSED" ]; then
            echo "  Found paused containers, unpausing..."
            echo "$PAUSED" | while read cname; do
                [ -n "$cname" ] && $DOCKER_CMD unpause "$cname" && echo "  Unpaused: $cname"
            done
            sleep 2
            continue
        fi

        # Check if all 3 are running
        if [ "$RUNNING" -ge 3 ]; then
            echo "  All $RUNNING EC2 containers are Running!"
            return 0
        fi

        sleep $retry_interval
    done

    echo "ERROR: Could not get all 3 EC2 containers running after $max_retries retries"
    $DOCKER_CMD ps -a --filter "name=localstack-ec2"
    exit 1
}

# ─── Step 1: Generate Inventory ───────────────────────────────────────────────
echo ""
echo "========================================"
echo " STEP 1: Generating Ansible Inventory"
echo "========================================"
bash scripts/generate-inventory.sh

# ─── Step 2: Get Node 1 ID ────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " STEP 2: Finding Node 1 (Control Node)"
echo "========================================"
NODE1_ID=$($TF_CMD -chdir=terraform output -json instance_ids | awk -F'"' '/"i-/ {print $2}' | head -n 1)
if [ -z "$NODE1_ID" ] || [ "$NODE1_ID" == "null" ]; then
    echo "ERROR: Could not find Node 1 ID from Terraform output."
    exit 1
fi
echo "  Node 1 EC2 ID: $NODE1_ID"
echo "  Container name: localstack-ec2.$NODE1_ID"

# ─── Step 3: Wait for all EC2 containers to be Running ───────────────────────
echo ""
echo "========================================"
echo " STEP 3: Verifying EC2 Container Health"
echo "========================================"
wait_for_ec2_containers

# Show final state
echo ""
echo "  Current EC2 containers:"
$DOCKER_CMD ps --filter "name=localstack-ec2" --format "  {{.Names}} | {{.Status}}"

# ─── Step 4: Copy files to Node 1 ────────────────────────────────────────────
echo ""
echo "========================================"
echo " STEP 4: Copying Ansible files to Node 1"
echo "========================================"
$DOCKER_CMD cp ansible "localstack-ec2.$NODE1_ID:/ansible_temp"
$DOCKER_CMD cp ssh-keys/id_rsa "localstack-ec2.$NODE1_ID:/root_ssh_key"
$DOCKER_CMD cp ssh-keys/id_rsa.pub "localstack-ec2.$NODE1_ID:/root_ssh_key_pub"
echo "  Files copied successfully"

# ─── Step 5: Install Ansible on Node 1 ───────────────────────────────────────
echo ""
echo "========================================"
echo " STEP 5: Installing Ansible on Node 1"
echo "========================================"
$DOCKER_CMD exec -u root "localstack-ec2.$NODE1_ID" bash -c "
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get update -qq && apt-get install -y -qq ansible && \
    mkdir -p /opt/ansible && \
    cp -r /ansible_temp/* /opt/ansible/ && \
    rm -rf /ansible_temp && \
    mkdir -p /root/.ssh && \
    mv /root_ssh_key /root/.ssh/id_rsa && \
    mv /root_ssh_key_pub /root/.ssh/id_rsa.pub && \
    chmod 400 /root/.ssh/id_rsa && \
    chmod 644 /root/.ssh/id_rsa.pub && \
    echo 'Ansible version:' && ansible --version | head -1
"

# ─── Step 6: Run Ansible Playbook ────────────────────────────────────────────
echo ""
echo "========================================"
echo " STEP 6: Running Ansible Playbook"
echo "========================================"
$DOCKER_CMD exec -u root "localstack-ec2.$NODE1_ID" \
    bash -c "cd /opt/ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml"

# ─── Step 7: Extract credentials ─────────────────────────────────────────────
echo ""
echo "========================================"
echo " STEP 7: Extracting Vault Credentials"
echo "========================================"
$DOCKER_CMD cp "localstack-ec2.$NODE1_ID:/opt/ansible/vault-init-keys.json" ./ansible/vault-init-keys.json \
    && echo "  Keys saved to: ansible/vault-init-keys.json" \
    || echo "  WARNING: Could not copy keys file"

# ─── Step 8: Update vault-proxy with correct IP ──────────────────────────────
echo ""
echo "========================================"
echo " STEP 8: Updating vault-proxy"
echo "========================================"
NODE1_IP=$($DOCKER_CMD inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "localstack-ec2.$NODE1_ID")
echo "  Node 1 IP: $NODE1_IP"

# Restart vault-proxy
$DOCKER_CMD rm -f vault-proxy 2>/dev/null || true
    # Start Nginx proxy to forward traffic to Vault
    $DOCKER_CMD run -d --name vault-proxy \
        --network localstack-ec2-link-local \
        -p 8200:8200 \
        nginx:alpine \
        sh -c "echo 'events {} http { server { listen 8200; location / { proxy_pass http://${NODE1_IP}:8200; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; } } }' > /etc/nginx/nginx.conf && nginx -g 'daemon off;'"
echo "  vault-proxy started: 127.0.0.1:8200 -> $NODE1_IP:8200"

# ─── Final Summary ────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " VAULT HA CLUSTER IS READY!"
echo "========================================"
echo ""
echo "  Access Vault UI:  http://127.0.0.1:8200/ui"
echo ""

if [ -f ansible/vault-init-keys.json ]; then
    # Try to extract root token (works on Linux/WSL with python3)
    ROOT_TOKEN=$(grep -o '"root_token":"[^"]*"' ansible/vault-init-keys.json | cut -d'"' -f4 2>/dev/null || true)
    if [ -n "$ROOT_TOKEN" ]; then
        echo "  Root Token:       $ROOT_TOKEN"
    fi
fi

echo ""
echo "  Keys file:        ansible/vault-init-keys.json"
echo ""
echo "  EC2 Containers:"
$DOCKER_CMD ps --filter "name=localstack-ec2" --format "    {{.Names}} | {{.Status}}"
echo ""
echo "========================================"
