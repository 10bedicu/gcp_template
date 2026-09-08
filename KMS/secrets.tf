resource "random_password" "django_secret_key" {
  length  = 32
  special = true
}

resource "random_password" "django_admin_password" {
  length  = 16
  special = false
}

resource "random_password" "metabase_encryption_secret_key" {
  length  = 32
  special = false
}

resource "random_password" "warehouse_etl_password" {
  length  = 32
  special = false
}

resource "random_password" "warehouse_fdw_reader_password" {
  length  = 32
  special = false
}

resource "random_password" "metabase_reader_password" {
  length  = 32
  special = false
}
