#!/bin/bash
# scripts/start.sh
# Full deployment: LocalStack (docker compose) -> Terraform (EC2) -> Ansible (Vault HA)
# Usage: bash scripts/start.sh

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

echo ""
echo "###############################################"
echo "#   HashiCorp Vault HA - Full Deployment      #"
echo "###############################################"

# ─── Step 1: Start LocalStack (docker compose) ────────────────────────────────
echo ""
echo "========================================"
echo " STEP 1: Starting LocalStack"
echo "========================================"
$DOCKER_CMD compose up -d localstack
echo "  Waiting 15s for LocalStack to fully start..."
sleep 15

# Wait for LocalStack to be healthy
MAX_WAIT=60
for i in $(seq 1 $MAX_WAIT); do
    STATUS=$($DOCKER_CMD inspect --format='{{.State.Health.Status}}' localstack-main 2>/dev/null || echo "none")
    if [ "$STATUS" == "healthy" ]; then
        echo "  LocalStack is healthy!"
        break
    fi
    if [ "$i" -ge "$MAX_WAIT" ]; then
        echo "  WARNING: LocalStack health check timed out, continuing anyway..."
    fi
    echo "  Waiting... ($i/${MAX_WAIT}) status=$STATUS"
    sleep 3
done

# ─── Step 2: Terraform init & apply (parallelism=1 to avoid port conflicts) ───
echo ""
echo "========================================"
echo " STEP 2: Provisioning EC2 with Terraform"
echo "========================================"

# Init (only if .terraform folder doesn't exist)
if [ ! -d "terraform/.terraform" ]; then
    echo "  Initializing Terraform..."
    $TF_CMD -chdir=terraform init
fi

echo "  Applying Terraform (parallelism=1 to avoid EC2 port conflicts)..."
$TF_CMD -chdir=terraform apply -auto-approve -parallelism=1

echo ""
echo "  Terraform outputs:"
$TF_CMD -chdir=terraform output

# ─── Step 3: Wait for all 3 EC2 containers to be Running ─────────────────────
echo ""
echo "========================================"
echo " STEP 3: Verifying EC2 Containers"
echo "========================================"

MAX_RETRIES=30
RETRY_INTERVAL=5
for i in $(seq 1 $MAX_RETRIES); do
    RUNNING=$($DOCKER_CMD ps --filter "name=localstack-ec2" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')
    PAUSED=$($DOCKER_CMD ps -a --filter "name=localstack-ec2" --filter "status=paused" --format "{{.Names}}")

    if [ -n "$PAUSED" ]; then
        echo "  Found paused containers, unpausing..."
        echo "$PAUSED" | while read cname; do
            [ -n "$cname" ] && $DOCKER_CMD unpause "$cname" && echo "  Unpaused: $cname"
        done
        sleep 2
        continue
    fi

    if [ "$RUNNING" -ge 3 ]; then
        echo "  All 3 EC2 containers are Running!"
        break
    fi

    echo "  Attempt $i/$MAX_RETRIES - Running containers: $RUNNING/3, waiting..."
    sleep $RETRY_INTERVAL

    if [ "$i" -ge "$MAX_RETRIES" ]; then
        echo "ERROR: Could not get all 3 EC2 containers running!"
        $DOCKER_CMD ps -a --filter "name=localstack-ec2"
        exit 1
    fi
done

echo ""
echo "  EC2 container status:"
$DOCKER_CMD ps --filter "name=localstack-ec2" --format "  {{.Names}} | {{.Status}}"

# ─── Step 4: Run Ansible to deploy Vault ──────────────────────────────────────
echo ""
echo "========================================"
echo " STEP 4: Deploying Vault with Ansible"
echo "========================================"
bash scripts/run-ansible.sh

echo ""
echo "###############################################"
echo "#   DEPLOYMENT COMPLETE!"
echo "###############################################"
echo ""
echo "  Vault UI:    http://127.0.0.1:4510/ui"
echo "  Keys file:   ansible/vault-init-keys.json"
echo ""
