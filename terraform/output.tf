output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "The URL of the ECR repository to push Docker images to"
}

# Optional but helpful fallback target
output "aws_region" {
  value = "ap-south-1"
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_execution_role.arn
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.ecs.name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "service_name" {
  value = aws_ecs_service.flask.name
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name

