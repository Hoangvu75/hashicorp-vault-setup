# HashiCorp Vault HA Cluster (Raft Integrated Storage)

Dự án triển khai tự động Cụm **HashiCorp Vault High Availability (3 nodes)** sử dụng **Raft Integrated Storage**. 
Được thiết kế để chạy mượt mà trên **LocalStack** (giả lập AWS cục bộ) nhằm mục đích phát triển và kiểm thử, đồng thời cung cấp lộ trình rõ ràng để đưa lên **AWS Cloud (Môi trường thật)** và **On-Premise (Bare Metal/VM)**.

---

## Mục lục
- [Kiến trúc & Cơ chế hoạt động](#kiến-trúc--cơ-chế-hoạt-động)
- [Môi trường 1: LocalStack (Dev / Testing)](#môi-trường-1-localstack-dev--testing)
- [Môi trường 2: AWS Cloud (Môi trường thật)](#môi-trường-2-aws-cloud-môi-trường-thật)
- [Môi trường 3: On-Premise (Máy chủ vật lý / VM)](#môi-trường-3-on-premise-máy-chủ-vật-lý--vm)

---

## Kiến trúc & Cơ chế hoạt động

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Máy Host (Windows / macOS / Linux)                    │
│                                                                              │
│  Browser / CLI                 Terraform CLI          bash scripts/start.sh  │
│  http://127.0.0.1:8200/ui      (IaC provisioning)     (full automation)      │
│         │                            │                        │              │
│         ▼                            ▼                        ▼              │
│ ┌──────────────────────────────────────────────────────────────────────────┐ │
│ │                     Docker Desktop (LocalStack Pro)                      │ │
│ │                                                                          │ │
│ │  ┌─────────────────┐    ┌──────────────────────────────────────────────┐ │ │
│ │  │   vault-proxy   │    │      localstack-ec2-link-local (Bridge)      │ │ │
│ │  │ (nginx:alpine)  │    │                                              │ │ │
│ │  │  Port 8200:8200 │    │  ┌──────────────────────────────────────┐   │ │ │
│ │  └────────┬────────┘    │  │         LocalStack Pro               │   │ │ │
│ │           │             │  │   (giả lập AWS: EC2, VPC, ELBv2)     │   │ │ │
│ │           │  forward    │  │                                      │   │ │ │
│ │           └────────────►│  │  ┌─────────────┐                    │   │ │ │
│ │                         │  │  │  AWS NLB    │ (L4 Load Balancer) │   │ │ │
│ │                         │  │  │  :8200      │ Round-Robin TCP    │   │ │ │
│ │                         │  │  └──────┬──────┘                    │   │ │ │
│ │                         │  │         │                            │   │ │ │
│ │                         │  │    ┌────┴──────────────────────┐    │   │ │ │
│ │                         │  │    ▼         ▼                 ▼    │   │ │ │
│ │                         │  │ ┌────────┐┌────────┐┌────────┐     │   │ │ │
│ │                         │  │ │ EC2 #1 ││ EC2 #2 ││ EC2 #3 │     │   │ │ │
│ │                         │  │ │(Leader)││(Follow)││(Follow)│     │   │ │ │
│ │                         │  │ │:8200   ││:8200   ││:8200   │     │   │ │ │
│ │                         │  │ │:8201   ││:8201   ││:8201   │     │   │ │ │
│ │                         │  │ └────────┘└────────┘└────────┘     │   │ │ │
│ │                         │  │     Raft Cluster (port 8201)        │   │ │ │
│ │                         │  └──────────────────────────────────┘   │   │ │ │
│ │                         └──────────────────────────────────────────┘ │ │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Mạng (Network):** Môi trường LocalStack sử dụng mạng `localstack-ec2-link-local` để giả lập VPC. Do giới hạn của Docker Bridge, chúng ta sử dụng `nginx` làm proxy (`vault-proxy`) để mở port `8200` ra localhost của máy thật.
- **Tự động hóa:** Ansible được đưa thẳng vào `EC2 #1` (đóng vai trò như Bastion/Control Node) để kết nối SSH sang 2 Node còn lại, cài đặt và cấu hình cụm Raft.

---

## Môi trường 1: LocalStack (Dev / Testing)

### 1. Yêu cầu hệ thống
- **Docker Desktop**
- **LocalStack Pro** (Cần khai báo token vào file `.env` ở thư mục gốc: `LOCALSTACK_AUTH_TOKEN=<token>`)
- **Terraform CLI**
- **Git Bash / WSL** (Môi trường bash shell)

### 2. Cài đặt & Khởi chạy (Chỉ cần 1 lệnh)

Tạo thư mục lưu SSH keys (chỉ làm 1 lần):
```bash
mkdir -p ssh-keys
ssh-keygen -t rsa -b 4096 -f ssh-keys/id_rsa -N ""
```

Chạy toàn bộ quy trình:
```bash
bash scripts/start.sh
```

**Quá trình này sẽ:**
1. Bật LocalStack (`docker compose up`).
2. Terraform tạo VPC, 3 EC2, và Network Load Balancer.
3. Ansible tự động cài đặt Vault, thiết lập Raft Cluster, khởi tạo Vault (Generate Root token & Unseal keys).
4. Ansible tự động mở khóa (Unseal) cả 3 nodes.
5. `vault-proxy` bằng Nginx được khởi tạo tự động.

### 3. Kết quả & Truy cập
Sau khoảng 2-3 phút, bạn sẽ thấy thông báo hoàn tất. Bạn có thể truy cập ngay:
- **Giao diện UI**: `http://127.0.0.1:8200/ui`
- **Thông tin đăng nhập**: File `ansible/vault-init-keys.json` sẽ chứa **Root Token** và **5 Unseal Keys**.

### 4. Dọn dẹp môi trường
Khi không cần sử dụng nữa:
```bash
bash scripts/cleanup.sh
```

---

## Môi trường 2: AWS Cloud (Môi trường thật)

Khi đẩy hệ thống lên AWS thật, hãy thực hiện các thay đổi sau trên source code:

### 1. Chỉnh sửa Terraform (`terraform/main.tf`)
- **Bỏ LocalStack endpoint**: Xóa cấu hình giả lập local.
  ```hcl
  provider "aws" {
    region = "ap-southeast-1"
    # XÓA toàn bộ block endpoints { ... } dùng cho localstack
  }
  ```
- **Sử dụng AMI thực**: Đổi AMI từ Docker container giả lập sang AMI Ubuntu/Debian x86_64 hoặc ARM64 thật của AWS (VD: `ami-0a59f0e26c55590e9` - Ubuntu 22.04 LTS).
- **IAM Instance Profile (Auto Unseal)**: Thêm Role cho EC2 để các instances có quyền truy cập vào dịch vụ AWS KMS. Vault sẽ dùng KMS Key này để Auto-unseal khi service bị restart (thay vì phải gõ Unseal Keys thủ công).
- **Bỏ -parallelism=1**: Khi chạy Terraform `apply`, không cần ép chạy tuần tự `-parallelism=1` nữa vì AWS thật không bị kẹt port 22 như LocalStack.

### 2. Thay đổi luồng Ansible & Proxy
- **Bỏ `vault-proxy`**: Ở AWS, ta sẽ dùng trực tiếp **DNS của AWS Network Load Balancer (NLB)** hoặc **Application Load Balancer (ALB)**. Bạn không cần chạy Nginx container nữa. Client sẽ truy cập Vault qua `https://vault.domain.com`.
- **Cách chạy Ansible**: Thay vì copy script vào bên trong Docker Container (Node 1), hãy chạy `ansible-playbook` trực tiếp từ máy của bạn qua VPN (kết nối vào Private Subnet), hoặc dùng một **Bastion Host / SSM Session Manager** để kết nối vào các Node.
- **Dynamic Inventory**: Sử dụng plugin `aws_ec2` của Ansible để tự động quét IP của 3 node Vault dựa trên Tag, thay vì dùng script generate tĩnh.

### 3. Cấu hình Vault Configuration (`ansible/roles/vault-configure/templates/vault.hcl.j2`)
Bổ sung Block KMS Auto-unseal:
```hcl
seal "awskms" {
  region     = "{{ aws_region }}"
  kms_key_id = "{{ vault_kms_key_id }}"
}
```
Và bật TLS (`tls_disable = false`) với cert lấy từ Let's Encrypt hoặc AWS ACM.

---

## Môi trường 3: On-Premise (Máy chủ vật lý / VM)

Nếu triển khai trên các Data Center truyền thống (VMware, Proxmox, Bare metal):

### 1. Hạ tầng (Infrastructure)
- **Terraform**: Có thể không cần dùng Terraform nếu bạn cấp phát IP tĩnh thủ công cho 3 VMs. Hoặc nếu dùng ảo hóa, hãy đổi provider sang `vsphere` hoặc `proxmox`.
- **Load Balancer**: Sử dụng **HAProxy**, **F5 BIG-IP**, hoặc **Nginx** để đứng trước 3 Vault nodes (Cấu hình TCP passthrough port 8200).
- **IP tĩnh (Static IP)**: Gắn cứng IP tĩnh vào file `inventory/hosts.yml` (VD: `10.0.0.11`, `10.0.0.12`, `10.0.0.13`), bỏ qua bước chạy script `generate-inventory.sh`.

### 2. Cấu hình Vault
- Trong môi trường không có Cloud KMS, Vault mặc định dùng **Shamir's Secret Sharing**. Khi một node bị reboot, một Admin cần phải đăng nhập và chạy lệnh unseal thủ công (điền 3/5 keys).
- **Transit Auto-unseal (Khuyên dùng)**: Nếu bạn không muốn unseal thủ công, hãy dựng một **Vault cluster nhỏ độc lập khác** chỉ chuyên đóng vai trò làm Transit Engine, cấp phát khóa KMS cho cụm Vault chính.
  ```hcl
  seal "transit" {
    address         = "https://vault-transit-cluster.local:8200"
    token           = "hvs.transit-token"
    disable_renewal = "false"
    key_name        = "primary-vault-unseal-key"
    mount_path      = "transit/"
  }
  ```

### 3. Storage
Raft Integrated Storage hoạt động ghi đĩa (I/O) liên tục. Hãy đảm bảo ổ cứng được cấp phát cho đường dẫn `/opt/vault/data` là ổ **SSD Enterprise** hoặc **NVMe** có IOPS cao. Đặt node trên 3 host vật lý (Hypervisor) khác nhau để đạt chuẩn HA cao nhất.
