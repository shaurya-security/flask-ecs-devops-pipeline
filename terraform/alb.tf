resource "aws_lb" "main" {

  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  security_groups = [
    aws_security_group.alb_sg.id
  ]

  subnets = aws_subnet.public[*].id
}


resource "aws_lb_target_group" "flask" {

  name = "${local.owner}-tg"

  port     = local.container_port
  protocol = "HTTP"

  vpc_id = aws_vpc.main.id

  target_type = "ip"

  health_check {

    path = "/health"

    matcher = "200"

    interval = 30

    healthy_threshold = 2

    unhealthy_threshold = 2

  }

}


resource "aws_lb_listener" "http" {

  load_balancer_arn = aws_lb.main.arn

  port = 80

  protocol = "HTTP"

  default_action {

    type = "forward"

    target_group_arn = aws_lb_target_group.flask.arn

  }

}

