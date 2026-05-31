# Architecture Infrastructure

Dưới đây là sơ đồ chi tiết biểu diễn toàn bộ các tài nguyên (resources) được Terraform tạo ra trong LocalStack, bao gồm Mạng lưới (VPC/Subnet), Cân bằng tải (NLB) và các máy chủ (EC2).

## Infrastructure Diagram

```mermaid
graph TD
    subgraph AWS_LocalStack [AWS LocalStack - us-east-1]
        KeyPair(AWS Key Pair: vault-key)
        
        subgraph VPC [Default VPC]
            NLB(Network Load Balancer: vault-nlb)
            Listener(Listener: Port 4510)
            TG(Target Group: vault-tg)
            
            subgraph Subnet [Default Subnet: us-east-1a]
                subgraph SG [Security Group: vault_sg]
                    Node1(EC2: vault-node-1)
                    Node2(EC2: vault-node-2)
                    Node3(EC2: vault-node-3)
                end
            end
        end
    end

    Client([Client / K8s]) -->|TCP 4510| NLB
    NLB --> Listener
    Listener -->|Forward| TG
    
    TG -->|TCP 8200| Node1
    TG -->|TCP 8200| Node2
    TG -->|TCP 8200| Node3

    KeyPair -.->|Injects Key| Node1
    KeyPair -.->|Injects Key| Node2
    KeyPair -.->|Injects Key| Node3

    %% Styling
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:white;
    classDef ec2 fill:#F26B38,stroke:#232F3E,stroke-width:2px,color:white;
    classDef network fill:#8C4FFF,stroke:#232F3E,stroke-width:2px,color:white;
    
    class VPC,Subnet network;
    class NLB,Listener,TG network;
    class Node1,Node2,Node3 ec2;
```

## Giải thích chi tiết

- **Mạng lưới cơ bản**: Terraform tạo 1 `aws_default_vpc` và 1 `aws_default_subnet` để gom các tài nguyên lại với nhau.
- **Bảo mật**: `aws_security_group` mở cổng `22` (để Ansible SSH vào cài đặt) và cổng `8200-8201` (cho Vault giao tiếp). `aws_key_pair` được tiêm vào 3 máy EC2 để xác thực SSH.
- **Cân bằng tải (NLB)**: Mọi truy cập từ bên ngoài (như từ Web UI, hay từ K8s Secrets Operator) sẽ gọi vào cổng `4510` của `aws_lb`. Traffic này sẽ đi qua `aws_lb_listener`, được chuyển hướng về `aws_lb_target_group` và cuối cùng được phân phát đều vào cổng `8200` của 3 máy ảo EC2 `aws_instance` thông qua 3 bản ghi `aws_lb_target_group_attachment`.
