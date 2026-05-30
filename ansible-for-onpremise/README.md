# HashiCorp Vault HA (Raft) - On-Premise Ansible Setup

Thư mục này chứa bộ công cụ Ansible chuyên dụng để cài đặt và cấu hình HashiCorp Vault HA theo mô hình Raft cho các máy chủ vật lý (Bare Metal) hoặc máy ảo (VM) môi trường On-Premise.

Khác với thư mục `ansible` gốc (được tinh chỉnh tự động hóa cao cho LocalStack/Docker), bộ công cụ này hoàn toàn tiêu chuẩn, không phụ thuộc vào script Bash sinh inventory tự động.

## Yêu cầu chuẩn bị (Prerequisites)
1. **3 máy chủ (Servers)** chạy Linux (Ubuntu/Debian hoặc RHEL/CentOS) đã được cấp IP.
2. Máy chủ chạy Ansible (Control Node) phải có quyền **SSH (bằng SSH Key)** hoặc **Password** vào cả 3 máy chủ trên.
3. Cả 3 máy chủ có thể giao tiếp mạng thông suốt với nhau qua port `8200` (API) và `8201` (Raft Cluster).

## Hướng dẫn cài đặt (Step-by-step)

### Bước 1: Khai báo IP các máy chủ (Inventory)
Mở file `inventory/hosts.yml` và thay đổi địa chỉ IP của 3 node Vault thành IP thật của bạn:
```yaml
        vault-node-1:
          ansible_host: "10.0.0.11" # Sửa thành IP thật
          private_ip: "10.0.0.11"
...
```

Đảm bảo cấu hình đúng tài khoản SSH ở phần `vars` bên dưới file `hosts.yml`:
```yaml
  vars:
    ansible_user: "ubuntu"          # User SSH
    ansible_ssh_private_key_file: "~/.ssh/id_rsa"  # Đường dẫn tới Private Key
```

### Bước 2: Tùy chỉnh tham số (Tùy chọn)
Nếu bạn muốn đổi thư mục cài đặt, port hoặc phiên bản Vault, hãy sửa file `inventory/group_vars/all.yml`. Mặc định đã được cấu hình tối ưu.

### Bước 3: Chạy Ansible Playbook
Từ máy Control Node (máy cá nhân của bạn hoặc Bastion Host), chạy lệnh sau:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### Bước 4: Hoàn thành & Lưu trữ Khóa
Sau khi Playbook chạy xong, Vault sẽ tự động được khởi tạo (Initialize) trên Node 1 và kết nối (Join) Node 2 & 3 vào cụm Cluster, sau đó tự động Unseal toàn bộ các Node.

> [!IMPORTANT]
> Hãy tìm file `vault-init-keys.json` được sinh ra tự động ngay trong thư mục này. Nó chứa **Root Token** và **Unseal Keys** của cụm Vault. Bạn phải bảo mật file này cực kỳ cẩn thận.

Bạn có thể truy cập thẳng vào giao diện UI của Vault thông qua bất kỳ IP nào của 3 Node: `http://<IP_NODE>:8200`.
