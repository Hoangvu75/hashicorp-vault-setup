# -------------------------------------------------------------
# Thiết lập Network Load Balancer (NLB)
# -------------------------------------------------------------

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
  count            = var.node_count
  target_group_arn = aws_lb_target_group.vault_tg.arn
  target_id        = aws_instance.vault_node[count.index].id
  port             = 8200
}
