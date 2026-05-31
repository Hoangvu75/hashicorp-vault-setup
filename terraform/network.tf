# -------------------------------------------------------------
# Hạ tầng mạng lõi: VPC, Subnets và Security Group
# -------------------------------------------------------------

resource "aws_default_vpc" "default" {}

resource "aws_default_subnet" "default_az1" {
  availability_zone = "${var.aws_region}a"
}

resource "aws_security_group" "vault_sg" {
  name        = "vault_sg"
  description = "Cho phep truy cap SSH va Vault Traffic (8200-8201)"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8200
    to_port     = 8201
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
