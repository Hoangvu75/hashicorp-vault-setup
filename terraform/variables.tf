variable "aws_region" {
  description = "Vùng AWS để triển khai tài nguyên"
  type        = string
  default     = "us-east-1"
}

variable "node_count" {
  description = "Số lượng máy chủ EC2 chạy Vault (dành cho High Availability)"
  type        = number
  default     = 3
}

variable "ami_id" {
  description = "ID của AMI dùng để khởi tạo EC2 (Mặc định cho LocalStack)"
  type        = string
  default     = "ami-df5de72bdb3b"
}

variable "instance_type" {
  description = "Loại máy ảo EC2"
  type        = string
  default     = "t2.micro"
}
