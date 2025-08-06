output "endpoint" {
  description = "The endpoint of the Redshift Serverless cluster"
  value       = aws_redshiftserverless_workgroup.production[0].endpoint[0].address
}