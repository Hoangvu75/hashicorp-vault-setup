#!/bin/bash
# scripts/generate-inventory.sh

set -e

cd "$(dirname "$0")/../terraform" || exit 1

TF_CMD="terraform"
if ! command -v terraform &> /dev/null; then
    TF_CMD="terraform.exe"
fi

INSTANCE_IDS=$($TF_CMD output -json instance_ids)

cd ..

DOCKER_CMD="docker"
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    DOCKER_CMD="docker.exe"
fi

get_docker_ip() {
    local iid=$1
    local ip=$($DOCKER_CMD inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "localstack-ec2.${iid}" 2>/dev/null)
    if [ -z "$ip" ]; then
        ip="127.0.0.1"
    fi
    echo "$ip"
}

# Parse array without jq (using sed/grep)
# $INSTANCE_IDS is like: [ "i-123", "i-456", "i-789" ]
IDS=($(echo "$INSTANCE_IDS" | grep -o '"i-[^"]*"' | tr -d '"'))

ID1=${IDS[0]}
ID2=${IDS[1]}
ID3=${IDS[2]}

IP1=$(get_docker_ip "$ID1")
IP2=$(get_docker_ip "$ID2")
IP3=$(get_docker_ip "$ID3")

mkdir -p ansible/inventory
cat > ansible/inventory/hosts.yml <<EOF
all:
  children:
    vault_servers:
      hosts:
        vault-node-1:
          ansible_host: $IP1
          ansible_connection: local
          private_ip: $IP1
          ec2_id: $ID1
          vault_node_id: vault-node-1
          vault_api_addr: "http://$IP1:8200"
          vault_cluster_addr: "http://$IP1:8201"
        vault-node-2:
          ansible_host: $IP2
          ansible_connection: ssh
          private_ip: $IP2
          ec2_id: $ID2
          vault_node_id: vault-node-2
          vault_api_addr: "http://$IP2:8200"
          vault_cluster_addr: "http://$IP2:8201"
        vault-node-3:
          ansible_host: $IP3
          ansible_connection: ssh
          private_ip: $IP3
          ec2_id: $ID3
          vault_node_id: vault-node-3
          vault_api_addr: "http://$IP3:8200"
          vault_cluster_addr: "http://$IP3:8201"
    vault_init:
      hosts:
        vault-node-1:
    vault_joiners:
      hosts:
        vault-node-2:
        vault-node-3:
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: /root/.ssh/id_rsa
EOF

mkdir -p ansible/inventory/group_vars
cat > ansible/inventory/group_vars/all.yml <<EOF
# Vault configuration
vault_version: "1.19.0"
vault_user: "vault"
vault_group: "vault"
vault_config_dir: "/etc/vault.d"
vault_data_dir: "/opt/vault/data"
vault_log_dir: "/var/log/vault"
vault_bin_path: "/usr/bin/vault"

# Vault network settings
vault_api_port: 8200
vault_cluster_port: 8201
vault_tls_disable: true

# Raft HA settings
vault_raft_nodes:
  - node_id: "vault-node-1"
    address: "$IP1:8201"
  - node_id: "vault-node-2"
    address: "$IP2:8201"
  - node_id: "vault-node-3"
    address: "$IP3:8201"

# SSH configuration
ssh_key_path: "/root/.ssh/id_rsa"
ssh_pub_key_path: "/root/.ssh/id_rsa.pub"
ssh_shared_key_path: "/root/.ssh"

# All node IPs for SSH setup
all_node_ips:
  - name: "vault-node-1"
    ip: "$IP1"
  - name: "vault-node-2"
    ip: "$IP2"
  - name: "vault-node-3"
    ip: "$IP3"
EOF

echo "Ansible inventory generated at ansible/inventory/hosts.yml using SSH connection!"
echo "group_vars/all.yml generated with dynamic IPs!"
