#!/bin/bash
# scripts/generate-inventory.sh

cd terraform || exit 1

TF_CMD="terraform"
if ! command -v terraform &> /dev/null; then
    TF_CMD="terraform.exe"
fi

INSTANCE_IDS=$($TF_CMD output -json instance_ids)
PRIVATE_IPS=$($TF_CMD output -json private_ips)
PUBLIC_IPS=$($TF_CMD output -json public_ips)

cd ..

python3 -c "
import sys, json, os, subprocess

instance_ids = json.loads('''$INSTANCE_IDS''')
private_ips = json.loads('''$PRIVATE_IPS''')

docker_cmd = 'docker'
try:
    with open('/proc/version', 'r') as f:
        content = f.read()
        if 'Microsoft' in content or 'WSL' in content:
            docker_cmd = 'docker.exe'
except Exception:
    pass

def get_docker_ip(instance_id):
    try:
        out = subprocess.check_output([docker_cmd, 'inspect', '-f', '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}', f'localstack-ec2.{instance_id}'])
        return out.decode('utf-8').strip()
    except Exception as e:
        print(f'Error getting IP for {instance_id}: {e}')
        return '127.0.0.1'

public_ips = [get_docker_ip(iid) for iid in instance_ids]

inventory = '''all:
  children:
    vault_servers:
      hosts:'''

for i in range(3):
    node_num = i + 1
    connection_type = 'local' if node_num == 1 else 'ssh'
    inventory += f'''
        vault-node-{node_num}:
          ansible_host: {public_ips[i]}
          ansible_connection: {connection_type}
          private_ip: {public_ips[i]}
          ec2_id: {instance_ids[i]}
          vault_node_id: vault-node-{node_num}
          vault_api_addr: "http://{public_ips[i]}:8200"
          vault_cluster_addr: "http://{public_ips[i]}:8201"'''

inventory += '''
    vault_init:
      hosts:
        vault-node-1:
    vault_joiners:
      hosts:
        vault-node-2:
        vault-node-3:
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: /root/.ssh/id_rsa'''

os.makedirs('ansible/inventory', exist_ok=True)
with open('ansible/inventory/hosts.yml', 'w') as f:
    f.write(inventory)

# Update group_vars/all.yml
all_yml = f'''# Vault configuration
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
    address: "{public_ips[0]}:8201"
  - node_id: "vault-node-2"
    address: "{public_ips[1]}:8201"
  - node_id: "vault-node-3"
    address: "{public_ips[2]}:8201"

# SSH configuration
ssh_key_path: "/root/.ssh/id_rsa"
ssh_pub_key_path: "/root/.ssh/id_rsa.pub"
ssh_shared_key_path: "/root/.ssh"

# All node IPs for SSH setup
all_node_ips:
  - name: "vault-node-1"
    ip: "{public_ips[0]}"
  - name: "vault-node-2"
    ip: "{public_ips[1]}"
  - name: "vault-node-3"
    ip: "{public_ips[2]}"
'''

os.makedirs('ansible/inventory/group_vars', exist_ok=True)
with open('ansible/inventory/group_vars/all.yml', 'w') as f:
    f.write(all_yml)

print('Ansible inventory generated at ansible/inventory/hosts.yml using SSH connection!')
print('group_vars/all.yml generated with dynamic IPs!')
"
