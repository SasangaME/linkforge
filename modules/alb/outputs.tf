output "dns_name" {
  description = "The load balancer's name. This milestone is proven by curling http://<this>/health from a laptop, not by a clean plan."
  value       = aws_lb.this.dns_name
}

# Not the same thing as a Route 53 hosted zone. It is the zone the load
# balancer's own name lives in, and an alias record at v7-edge needs it beside
# the DNS name above.
output "zone_id" {
  description = "Canonical hosted zone of the load balancer, for the alias record at v7-edge."
  value       = aws_lb.this.zone_id
}

output "arn" {
  description = "The load balancer itself. v5-observable puts alarms on its metrics and v7-edge points CloudFront at it."
  value       = aws_lb.this.arn
}

# The one output whose value is worth reading during this milestone: it is what
# `aws elbv2 describe-target-health --target-group-arn` takes, and that call is
# the only thing that says whether the wiring works.
output "target_group_arn" {
  description = "Target group. Pass it to describe-target-health — a green apply says nothing about whether a target passed a check."
  value       = aws_lb_target_group.this.arn
}

output "security_group_id" {
  description = "The load balancer's group. Anything that later needs a rule naming the load balancer names this."
  value       = aws_security_group.alb.id
}

output "listener_arn" {
  description = "The listener, for the rules that v2-fargate adds beside the default action."
  value       = aws_lb_listener.http.arn
}

