output "repository_url" {
  description = "Use this URL to tag and push the LinkForge image."
  value       = module.ecr.repository_url
}