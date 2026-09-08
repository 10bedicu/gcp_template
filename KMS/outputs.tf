output "django_secret_key" {
  description = "Django secret key for the application"
  value       = random_password.django_secret_key.result
  sensitive   = true
}

output "django_admin_password" {
  description = "Django admin password"
  value       = random_password.django_admin_password.result
  sensitive   = true
}

output "metabase_encryption_secret_key" {
  description = "Metabase encryption secret key"
  value       = random_password.metabase_encryption_secret_key.result
  sensitive   = true
}

output "warehouse_etl_password" {
  description = "Password for the warehouse_etl Postgres role"
  value       = random_password.warehouse_etl_password.result
  sensitive   = true
}

output "warehouse_fdw_reader_password" {
  description = "Password for the warehouse_fdw_reader Postgres role on the source DB"
  value       = random_password.warehouse_fdw_reader_password.result
  sensitive   = true
}

output "metabase_reader_password" {
  description = "Password for the metabase_reader Postgres role on the warehouse"
  value       = random_password.metabase_reader_password.result
  sensitive   = true
}
