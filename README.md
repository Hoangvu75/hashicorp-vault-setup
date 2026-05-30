# HashiCorp Vault HA Cluster - LocalStack EC2 + Terraform + Ansible

Triển khai cụm **HashiCorp Vault High Availability (3 node)** sử dụng **Raft Integrated Storage**, hoàn toàn tự động hóa. Dự án mô phỏng chính xác quy trình triển khai trên AWS Cloud thực tế.

---

## Kiến trúc

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Máy Host (Windows / macOS / Linux)                    │
│                                                                              │
│  Browser / CLI                 Terraform CLI          bash scripts/start.sh  │
│  http://localhost:4510/ui      (IaC provisioning)     (full automation)      │
│         │                            │                        │              │
│         ▼                            ▼                        ▼              │
│ ┌──────────────────────────────────────────────────────────────────────────┐ │
│ │                     Docker Desktop (LocalStack Pro)                      │ │
│ │                                                                          │ │
│ │  ┌─────────────────┐    ┌──────────────────────────────────────────────┐ │ │
│ │  │   vault-proxy   │    │           localstack-net (Bridge Network)    │ │ │
│ │  │  (alpine/socat) │    │                                              │ │ │
│ │  │  Port 4510:8200 │    │  ┌──────────────────────────────────────┐   │ │ │
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

Luồng triển khai (chỉ chạy 1 lần):
  bash scripts/start.sh
       ├── docker compose up (khởi động LocalStack)
       ├── terraform apply -parallelism=1 (tạo VPC + NLB + 3 EC2 tuần tự)
       ├── [kiểm tra & unpause EC2 containers nếu cần]
       └── bash scripts/run-ansible.sh
               ├── generate-inventory.sh (lấy IP thực qua docker inspect)
               ├── docker cp ansible/ + ssh-keys/ → EC2 Node 1
               ├── apt install ansible (trực tiếp trên Node 1)
               ├── ansible-playbook site.yml (từ Node 1 SSH vào Node 2, 3)
               │       ├── ssh-setup: phân phối SSH keys giữa các node
               │       ├── vault-install: cài Vault v1.19.0 trên cả 3 node
               │       ├── vault-configure: cấu hình Raft HA
               │       ├── vault-init: khởi tạo cluster (tạo root token + 5 keys)
               │       └── vault-unseal: unseal toàn bộ cluster
               ├── docker cp vault-init-keys.json → host (ansible/)
               └── docker run vault-proxy (tự cập nhật IP Node 1 Leader)
```

### Tại sao cần `vault-proxy`?

Môi trường LocalStack chạy các EC2 instance bên trong một **isolated Docker bridge network** (`localstack-net`). Máy Host (Windows) **không thể** trực tiếp kết nối vào dải IP nội bộ này (ví dụ: `172.20.0.5`).

`vault-proxy` (dùng `socat`) đóng vai trò **bridge/gateway**:
- Lắng nghe ở `localhost:4510` (có thể truy cập từ Windows Host)
- Forward toàn bộ traffic TCP đến `<Node1_IP>:8200` (Vault Leader) bên trong Docker network

> **Lưu ý**: Script `run-ansible.sh` sẽ **tự động** phát hiện IP của Node 1 sau mỗi lần deploy và khởi động lại `vault-proxy` với IP đúng. Không cần chỉnh tay.

---

## Cấu trúc thư mục

```
learn-vault/
├── .env                          # LocalStack Auth Token
├── docker-compose.yml            # LocalStack + vault-proxy (template)
├── terraform/                    # Provisioning AWS resources (LocalStack)
│   ├── main.tf                   # VPC, Security Group, Key Pair, 3 EC2, NLB
│   └── outputs.tf                # instance_ids, private_ips, lb_dns_name
├── ansible/
│   ├── ansible.cfg               # Cấu hình Ansible (inventory, ssh settings)
│   ├── inventory/
│   │   ├── hosts.yml             # [TỰ SINH] Dynamic inventory từ docker inspect
│   │   └── group_vars/all.yml    # [TỰ SINH] Biến toàn cục (IPs, ports, ...)
│   ├── playbooks/
│   │   └── site.yml              # Main playbook (gọi tất cả roles)
│   ├── roles/
│   │   ├── ssh-setup/            # Phân phối SSH key, cấu hình known_hosts
│   │   ├── vault-install/        # Cài đặt Vault binary từ HashiCorp repo
│   │   ├── vault-configure/      # Sinh vault.hcl, start service, health check
│   │   └── vault-init/           # Init cluster, unseal, join followers vào Raft
│   └── vault-init-keys.json      # [TỰ SINH] Root Token + 5 Unseal Keys
├── scripts/
│   ├── start.sh                  # ⭐ Full deployment từ đầu đến cuối
│   ├── cleanup.sh                # ⭐ Dọn dẹp toàn bộ môi trường
│   ├── run-ansible.sh            # Chạy Ansible (step 4 của start.sh)
│   └── generate-inventory.sh     # Tạo inventory động từ Terraform output
└── ssh-keys/
    ├── id_rsa                    # SSH Private Key (dùng để Ansible SSH vào EC2)
    └── id_rsa.pub                # SSH Public Key (được Terraform upload lên EC2)
```

---

## Yêu cầu

| Tool | Mục đích |
|------|----------|
| **Docker Desktop** | Chạy LocalStack và các EC2 container |
| **LocalStack Pro** | Giả lập AWS EC2, VPC, ELBv2. Cần `LOCALSTACK_AUTH_TOKEN` |
| **Terraform CLI** | Provisioning infrastructure |
| **Bash** (WSL hoặc Git Bash) | Chạy scripts |

---

## Hướng dẫn khởi chạy

### Bước 1: Khai báo LocalStack Token

Tạo file `.env` ở thư mục gốc:
```env
LOCALSTACK_AUTH_TOKEN=<localstack-token-của-bạn>
```

### Bước 2: Tạo SSH Key pair (chỉ làm 1 lần)

```bash
mkdir -p ssh-keys
ssh-keygen -t rsa -b 4096 -f ssh-keys/id_rsa -N ""
```

### Bước 3: Chạy toàn bộ (1 lệnh duy nhất)

```bash
bash scripts/start.sh
```

Script này sẽ tự động thực hiện toàn bộ:
1. Khởi động **LocalStack** (`docker compose up`)
2. Chờ LocalStack healthy
3. Chạy **Terraform** tạo VPC + AWS NLB + 3 EC2 (`-parallelism=1` để tránh port conflict)
4. Kiểm tra tất cả 3 EC2 containers đang `Running` (tự `unpause` nếu cần)
5. Chạy **Ansible** từ bên trong Node 1 để cài đặt và khởi tạo Vault HA cluster
6. Lưu credentials về máy host: `ansible/vault-init-keys.json`
7. Tự động cập nhật IP và restart **vault-proxy**

---

## Dọn dẹp (Tear down)

```bash
bash scripts/cleanup.sh
```

Script này sẽ:
1. Xóa container `vault-proxy`
2. Chạy `terraform destroy` (xóa EC2 + NLB + VPC)
3. Force-remove các EC2 container còn sót
4. Xóa Terraform state files

---

## Truy cập Vault sau khi deploy

### Vault UI (Web Browser)

```
http://localhost:4510/ui
```

Chọn **Token** và dán `root_token` từ file `ansible/vault-init-keys.json`.

### Vault CLI

```bash
export VAULT_ADDR=http://localhost:4510
export VAULT_TOKEN=<root_token>

vault status
vault operator raft list-peers
```

---

## Thông tin Credentials

Sau khi deploy, toàn bộ credentials được lưu tại:

```
ansible/vault-init-keys.json
```

Cấu trúc file:
```json
{
  "root_token": "hvs.xxxxxxxxxxxx",
  "unseal_keys_b64": [
    "key-1-base64",
    "key-2-base64",
    "key-3-base64",
    "key-4-base64",
    "key-5-base64"
  ],
  "unseal_shares": 5,
  "unseal_threshold": 3
}
```

> **Shamir Secret Sharing**: Vault tạo ra **5 Unseal Keys**. Cần tối thiểu **3 keys** để unseal (mở khóa) Vault khi khởi động lại. Điều này đảm bảo không ai đơn lẻ có thể truy cập vào Vault.

---

## Giải thích kiến trúc chi tiết

### 1. Tại sao dùng `terraform apply -parallelism=1`?

LocalStack giả lập SSH port cho EC2 bằng cách bind port `22` trên host. Nếu tạo nhiều EC2 song song, các container sẽ **tranh nhau bind port 22**, gây ra một số container bị **pause hoặc fail**. Chạy tuần tự (`parallelism=1`) đảm bảo mỗi EC2 được assign một port riêng biệt.

### 2. Tại sao Ansible chạy từ **bên trong Node 1** thay vì từ máy Host?

Đây là kiến trúc **Ansible Control Node** chuẩn trong môi trường AWS thực tế:

```
[Thực tế AWS]               [Mô phỏng LocalStack]
Bastion Host (EC2)    ==>   EC2 Node 1 (vault-node-1)
    │ SSH                         │ SSH (docker exec)
    ├─> EC2 Node 2          ├─> EC2 Node 2 (172.20.x.x)
    └─> EC2 Node 3          └─> EC2 Node 3 (172.20.x.x)
```

Các EC2 trong VPC nội bộ của LocalStack không thể SSH từ Windows Host trực tiếp (do isolated network). Node 1 được đưa vào vai trò **Control Node**: có thể SSH vào Node 2 và 3 qua mạng nội bộ VPC.

### 3. `vault-proxy` — Bridge từ Windows vào VPC

```
Windows Host             Docker Network (localstack-net)
localhost:4510  ──────►  vault-proxy  ──────►  172.20.0.x:8200 (Vault Leader)
                         (alpine/socat)
```

- `socat` là một công cụ relay TCP đơn giản, nhẹ (~5MB image)
- Mỗi lần deploy, Node 1 có thể được assign IP khác, nên `run-ansible.sh` tự động `docker inspect` lấy IP mới và restart proxy

### 4. AWS NLB (Network Load Balancer)

NLB được tạo bởi Terraform để phân phối traffic Layer 4 (TCP) đến cả 3 Vault nodes. Trong môi trường thực tế trên AWS, client sẽ trỏ đến DNS của NLB thay vì IP trực tiếp của node.

Trong LocalStack, NLB DNS là: `vault-nlb.elb.localhost.localstack.cloud`

---

## Lưu ý và Gotchas

| Vấn đề | Nguyên nhân | Giải pháp đã cài sẵn |
|--------|------------|----------------------|
| EC2 container bị **pause** | LocalStack port 22 conflict khi tạo song song | `terraform apply -parallelism=1` |
| `vault-proxy` không kết nối được | IP của Node 1 thay đổi sau mỗi deploy | Script tự `docker inspect` & restart proxy |
| NLB DNS không resolve từ proxy | LocalStack NLB DNS resolve thành IPv6 `::1` | Proxy dùng IP thực từ `docker inspect` |
| Ansible không SSH được vào Node 2, 3 | SSH key chưa được phân phối | Role `ssh-setup` xử lý tự động |

---

## So sánh & Hướng dẫn triển khai trên AWS Thực tế (Production)

Khi chuyển từ môi trường giả lập **LocalStack** sang **AWS Cloud thực tế**, kiến trúc cốt lõi vẫn giữ nguyên (3 EC2 nodes, Raft storage, NLB). Tuy nhiên, bạn cần thực hiện một số chỉnh sửa và áp dụng các best practices dưới đây:

### 1. Bảng so sánh giữa LocalStack và AWS Thực tế

| Thành phần | Môi trường LocalStack (Mô phỏng) | Môi trường AWS Thực tế (Production) |
| :--- | :--- | :--- |
| **Docker Compose** | Bắt buộc (để chạy container LocalStack & `vault-proxy`) | **Không dùng** (Xóa hoàn toàn `docker-compose.yml`) |
| **Cấu hình AWS Provider** | Trỏ endpoint về `http://localhost:4566` | Trỏ trực tiếp tới AWS API thực tế (mặc định của Terraform) |
| **Quá trình Provisioning** | Dùng `-parallelism=1` để tránh conflict port SSH trên host | Chạy song song bình thường (không bị giới hạn parallelism) |
| **Truy cập Vault** | Qua `vault-proxy` (socat port 4510) trên host | Trực tiếp qua **AWS NLB DNS** hoặc VPN/Bastion Host |
| **SSH Keys** | Phân phối thủ công qua `docker cp` lên Node 1 | Sử dụng **AWS Key Pair** và **Bastion Host** (hoặc AWS SSM Session Manager) |
| **Mạng (Networking)** | Network bridge Docker nội bộ (`localstack-net`) | VPC Private Subnets, Security Groups nghiêm ngặt |
| **Giao thức kết nối** | HTTP (`http://`) để test nhanh | Bắt buộc HTTPS (`https://`) với TLS Certificate thực tế |
| **Mở khóa Vault (Unseal)** | Thủ công bằng 3 trong 5 keys (Shamir's Secret Sharing) | Tự động mở khóa sử dụng **AWS KMS Auto-unseal** (Khuyên dùng) |

---

### 2. Các bước chỉnh sửa mã nguồn khi chuyển sang AWS thật

#### A. Cấu hình Terraform (`terraform/main.tf`)
1. **Loại bỏ LocalStack Endpoint**:
   Xóa hoặc comment block `endpoints` trong cấu hình provider:
   ```hcl
   provider "aws" {
     region = "ap-southeast-1" # Region thật trên AWS
     # XÓA HOÀN TOÀN block cấu hình localstack ở đây
   }
   ```
2. **Sử dụng AMI thực tế**:
   Thay đổi AMI từ image giả lập của LocalStack sang AMI Ubuntu/Debian chính thức của region (ví dụ: Ubuntu Server 22.04 LTS).
3. **IAM Role cho Auto-Unseal**:
   Thêm IAM policy và IAM instance profile gắn vào các EC2 nodes để cấp quyền gọi tới AWS KMS:
   ```hcl
   resource "aws_iam_role" "vault_unseal" {
     name = "vault-unseal-role"
     # Trust policy cho ec2.amazonaws.com
   }
   # Gắn policy cấp quyền kms:Encrypt, kms:Decrypt, kms:DescribeKey cho AWS KMS Key
   ```

#### B. Cấu hình Vault (`ansible/roles/vault-configure/templates/vault.hcl.j2`)
Để sử dụng tính năng tự động mở khóa (**AWS KMS Auto-unseal**), cấu hình Vault cần khai báo thêm block `seal`:
```hcl
seal "awskms" {
  region     = "{{ aws_region }}"
  kms_key_id = "{{ vault_kms_key_id }}"
}
```
*Lưu ý: Khi cấu hình KMS Auto-unseal, Vault sẽ tự động mở khóa khi service khởi động lại mà không cần chạy playbook/script unseal thủ công.*

#### C. Thay đổi luồng Ansible & SSH
Trên AWS thật, bạn không thể sử dụng `docker cp` để copy code Ansible vào EC2 hay chạy lệnh trực tiếp bằng `docker exec`. Thay vào đó:
1. **Chạy Ansible từ CI/CD hoặc Bastion**:
   Chạy Ansible trực tiếp từ máy của bạn (qua VPN nối vào VPC) hoặc từ một **Bastion Host / Jump Box** đặt tại Public Subnet.
2. **Thay đổi cách generate inventory (`generate-inventory.sh`)**:
   Sử dụng dynamic inventory của Ansible (`aws_ec2` plugin) hoặc viết script để parse IP từ file `terraform.tfstate` thực tế thay vì dùng `docker inspect`:
   ```bash
   # Lấy danh sách IP thực của EC2 từ Terraform Output
   terraform output -json instance_private_ips
   ```
3. **Cấu hình SSH**:
   Sử dụng file private key `.pem` tải xuống từ AWS Key Pair để kết nối SSH trực tiếp:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --private-key=~/.ssh/aws-key.pem -u ubuntu
   ```

---

### 3. Khuyến nghị Bảo mật cho Production
* **Bật TLS (HTTPS)**: Cấu hình `listener "tcp"` trong `vault.hcl` sử dụng đường dẫn chứng chỉ TLS (`tls_cert_file` và `tls_key_file`).
* **Private Subnets**: Đặt toàn bộ 3 Vault nodes vào dải Private Subnets. Chỉ NLB (hoặc ALB) và Bastion Host được đặt ở Public Subnets.
* **Không lưu Root Token**: Sau khi khởi tạo Vault lần đầu, root token và recovery keys chỉ nên hiển thị một lần duy nhất và cất giữ ở nơi cực kỳ an toàn (như 1 Vault khác hoặc công cụ quản lý mật khẩu của doanh nghiệp). Xóa bỏ file JSON lưu trữ credentials trên ổ đĩa của server.
