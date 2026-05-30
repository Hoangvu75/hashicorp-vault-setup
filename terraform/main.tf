terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    elbv2 = "http://localhost:4566"
  }
}

resource "aws_key_pair" "vault_key" {
  key_name   = "vault-key"
  public_key = file("../ssh-keys/id_rsa.pub")
}

# Dummy security group to attach to EC2 instances
resource "aws_security_group" "vault_sg" {
  name        = "vault_sg"
  description = "Allow SSH and Vault traffic"

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

resource "aws_instance" "vault_node" {
  count         = 3
  # ami-df5de72bdb3b is a LocalStack mocked default for Ubuntu, or we can just provide any valid format AMI string
  ami           = "ami-df5de72bdb3b"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.vault_key.key_name

  vpc_security_group_ids = [aws_security_group.vault_sg.id]

  tags = {
    Name = "vault-node-${count.index + 1}"
  }
}

# -------------------------------------------------------------
# Network Load Balancer (NLB) Setup
# -------------------------------------------------------------

resource "aws_default_vpc" "default" {}

resource "aws_default_subnet" "default_az1" {
  availability_zone = "us-east-1a"
}

resource "aws_lb" "vault_nlb" {
  name               = "vault-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_default_subnet.default_az1.id]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "vault_tg" {
  name     = "vault-tg"
  port     = 8200
  protocol = "TCP"
  vpc_id   = aws_default_vpc.default.id

  health_check {
    protocol            = "TCP"
    port                = 8200
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }
}

resource "aws_lb_listener" "vault_listener" {
  load_balancer_arn = aws_lb.vault_nlb.arn
  port              = "4510"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "vault_nodes" {
  count            = 3
  target_group_arn = aws_lb_target_group.vault_tg.arn
  target_id        = aws_instance.vault_node[count.index].id
  port             = 8200
}
