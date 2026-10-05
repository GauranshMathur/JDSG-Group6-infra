# Two load balancers in series, as docs/architecture.md draws them. The NLB is
# the L4 front door: it takes CloudFront's connections on 443 and hands them
# on uninspected. The ALB behind it does the L7 work — TLS with the certificate
# from certificate.tf, then HTTP to the app's pods in the application VPC,
# across the transit gateway.
#
# Terraform owns the ALB, its listener and the pods' target group. The cluster's
# AWS Load Balancer Controller does not create a load balancer; it registers pod
# addresses into the target group below through a TargetGroupBinding. Decided
# 2026-10-01, docs/decisions.md.
#
# Inert: floci records both load balancers and forwards nothing. The ALB takes
# about a minute to create there — the provider waits out a state change the
# emulator never makes (docs/floci.md).

# The design's front door, and the security scan's second exception. Traffic
# crosses the internet gateway to this NLB, so it must be internet-facing;
# Trivy flags any load balancer that is. What reaches it is narrowed instead,
# by its security group in 10-network: HTTPS from CloudFront's origin-facing
# addresses and nothing else. Decided 2026-10-05, docs/decisions.md.
#trivy:ignore:aws-elb-alb-not-public
resource "aws_lb" "nlb" {
  name               = "${local.name_prefix}-nlb"
  load_balancer_type = "network"
  internal           = false
  subnets            = data.aws_subnets.perimeter_public.ids
  security_groups    = [data.aws_security_group.edge["nlb"].id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-nlb"
  })
}

# Internal: only the NLB reaches it, so it needs no public address. It sits in
# the perimeter's public subnets because an NLB can target an ALB only in its
# own VPC, and those are the perimeter's subnets in two zones.
resource "aws_lb" "alb" {
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = true
  subnets            = data.aws_subnets.perimeter_public.ids
  security_groups    = [data.aws_security_group.edge["alb"].id]

  # Reject requests whose headers do not parse, rather than pass them on.
  drop_invalid_header_fields = true

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-alb"
  })
}

# The app's pods, by address. They live in the application VPC, across the
# transit gateway, so their targets register with availability zone "all" —
# what AWS requires for an address outside the target group's VPC.
resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app"
  target_type = "ip"
  protocol    = "HTTP"
  port        = 80
  vpc_id      = data.aws_vpc.perimeter.id

  # Rails' own health endpoint, the one the app's Dockerfile checks.
  health_check {
    path    = "/up"
    matcher = "200"
  }

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-app"
  })
}

resource "aws_lb_listener" "alb_https" {
  load_balancer_arn = aws_lb.alb.arn
  protocol          = "HTTPS"
  port              = 443
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  # TLS 1.3 and 1.2 only.
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = local.inert
}

# The NLB's one target is the ALB itself.
resource "aws_lb_target_group" "alb" {
  name        = "${local.name_prefix}-alb"
  target_type = "alb"
  protocol    = "TCP"
  port        = 443
  vpc_id      = data.aws_vpc.perimeter.id

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-alb"
  })
}

# AWS refuses to register an ALB as a target before it has a listener on the
# target group's port.
resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = aws_lb.alb.arn
  port             = 443

  depends_on = [aws_lb_listener.alb_https]
}

resource "aws_lb_listener" "nlb_tcp" {
  load_balancer_arn = aws_lb.nlb.arn
  protocol          = "TCP"
  port              = 443

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = local.inert
}
