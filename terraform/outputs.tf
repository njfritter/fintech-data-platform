output "msk_bootstrap_brokers" {
  description = "MSK bootstrap brokers string"
  value       = aws_msk_cluster.fincore.bootstrap_brokers_sasl_iam
  sensitive   = true
}

output "aurora_cluster_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.aurora.endpoint
}

output "emr_serverless_application_id" {
  description = "EMR Serverless application ID"
  value       = aws_emrserverless_application.spark.id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.fincore.name
}

output "airflow_admin_password" {
  description = "Airflow admin password"
  value       = random_password.airflow_admin.result
  sensitive   = true
}

output "s3_data_lake_bucket" {
  description = "S3 Data Lake bucket name"
  value       = aws_s3_bucket.data_lake.id
}