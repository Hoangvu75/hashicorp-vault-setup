# -------------------------------------------------------------
# Cấu hình máy ảo EC2 và SSH Key Pair
# -------------------------------------------------------------

resource "aws_key_pair" "vault_key" {
  key_name   = "vault-key"
  public_key = file("../ssh-keys/id_rsa.pub")
}

resource "aws_instance" "vault_node" {
  count         = var.node_count
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.vault_key.key_name

  vpc_security_group_ids = [aws_security_group.vault_sg.id]

  tags = {
    Name = "vault-node-${count.index + 1}"
  }
}
