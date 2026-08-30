# --- security groups ----------------------------------------------------

# No inline ingress or egress block, for the same two reasons as the host's
# group: the inline form would remove nothing, and AWS's implicit allow-all
# egress has to go. The rules below are the whole of it.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Application load balancer. HTTP in from allowed_cidrs, out to the targets only."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

# One rule per range rather than one rule with a list, because a security group
# rule holds exactly one source. The AWS API models it that way and the
# aws_vpc_security_group_ingress_rule resource follows the API rather than
# hiding it, which is why the older inline block's cidr_blocks list expanded
# into several rules behind your back.
resource "aws_vpc_security_group_ingress_rule" "listener" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP to the listener from ${each.key}"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = each.key

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-listener" })
}

# The load balancer's only egress. It names a security group and not a range,
# which is possible because both ends are inside this VPC — the same reason the
# host's endpoint rule can, and the same reason its NAT rule cannot.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forwarded requests and health checks to the targets"
  ip_protocol                  = "tcp"
  from_port                    = var.target_port
  to_port                      = var.target_port
  referenced_security_group_id = var.target_security_group_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-targets" })
}

# This rule belongs to a group this module did not create, and that is the
# design rather than a shortcut. The two rules reference each other's groups,
# so whichever module owns only one of them has to consume the other module's
# output — and two modules consuming each other is a cycle Terraform reports at
# the module level, where no single resource is in a loop. One side owns both.
#
# It is also the first inbound rule the host has ever had. Until now nothing in
# the account could open a connection to it at all.
resource "aws_vpc_security_group_ingress_rule" "targets_from_alb" {
  security_group_id            = var.target_security_group_id
  description                  = "Requests and health checks from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = var.target_port
  to_port                      = var.target_port
  referenced_security_group_id = aws_security_group.alb.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-target-from-alb" })
}

# --- the load balancer --------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"

  # Force-new. Building this internal now to keep a stub off the internet would
  # buy one milestone of privacy and cost a replacement at v2-fargate, when the
  # same load balancer starts serving the application. The exposure is decided
  # by allowed_cidrs instead, which is a rule and not a rebuild.
  internal = false

  subnets         = var.public_subnet_ids
  security_groups = [aws_security_group.alb.id]

  # Stated rather than defaulted. Step 9 destroys dev every night with the
  # pipeline role, and true here would fail that apply with an error about the
  # load balancer rather than about the setting that protects it.
  enable_deletion_protection = false

  # Headers that are not valid HTTP are dropped rather than forwarded. The
  # default is false for compatibility with clients this project does not have.
  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

# --- the target group ---------------------------------------------------

# name_prefix and not name, and the six character cap is why it reads as lf-
# rather than as the environment. target_type, port, protocol and vpc_id are
# all force-new, and v2-fargate changes target_type from instance to ip. A
# replacement while the listener still forwards here is refused as
# ResourceInUse, so the new group has to exist before the old one is destroyed,
# and create_before_destroy needs a name AWS generates.
#
# The load balancer above keeps a readable name for the opposite reason: it is
# not going to be replaced, and its name is inside the DNS name people type.
resource "aws_lb_target_group" "this" {
  name_prefix = "lf-"
  vpc_id      = var.vpc_id

  port     = var.target_port
  protocol = "HTTP"

  # Explicit, and it is the argument the step 4 review was about. HTTP1 is the
  # default; writing it records that the responder answers 1.1 because it was
  # made to, not because nothing here cared.
  protocol_version = "HTTP1"

  # An instance for this milestone only. v2-fargate moves to ip, because a
  # Fargate task has an ENI and no instance ID to register.
  target_type = "instance"

  deregistration_delay = var.deregistration_delay

  # timeout must be below interval. Two consecutive failures take a target out
  # and two take it back, so a dead host is out in about a minute — fast enough
  # to notice and slow enough that one dropped check is not an outage.
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg" })

  lifecycle {
    create_before_destroy = true
  }
}

# Zero resources when the list is empty, which is the v2-fargate case: an ECS
# service registers its own tasks and a static attachment beside it would be
# removed and recreated on every deployment.
#
# `length()` and not a null comparison. The instance being registered does not
# exist at plan time, so `target_instance_id == null` was an unknown compared
# to null — unknown — and a count cannot be unknown. The length of a one-element
# list is known even when the element is not. See README.md.
resource "aws_lb_target_group_attachment" "instance" {
  count = length(var.target_instance_ids)

  target_group_arn = aws_lb_target_group.this.arn
  target_id        = var.target_instance_ids[count.index]
  port             = var.target_port
}

# --- the listener -------------------------------------------------------

# Plain HTTP, and deliberately not a redirect to 443. A redirect default action
# would send every request to a listener that does not exist, because there is
# no certificate, because there is no domain name to put on one. ACM, Route 53
# and the redirect arrive together at v7-edge.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-http" })
}

