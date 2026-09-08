locals {
  required_tags = {
    terraform   = "true"
    environment = var.environment
    project     = "care"
  }

  metabase_etl_commit_sha = var.metabase_etl_repo != null ? jsondecode(data.http.metabase_etl_latest_commit[0].response_body).sha : ""

  common_labels = {
    app         = "care"
    environment = var.environment
    project     = "care"
  }
  tags                 = merge(local.required_tags)
  patient_bucket_name  = data.terraform_remote_state.infra.outputs.patient_bucket_name
  facility_bucket_name = data.terraform_remote_state.infra.outputs.facility_bucket_name
  writer_sa_email      = data.terraform_remote_state.infra.outputs.writer_service_account_email

  namespace_name = coalesce(var.namespace_name, var.environment)
  app_name       = var.app
  environment    = var.environment

  cors_allowed_origins = concat(
    [for d in var.web_domain_name : "https://${d}"],
    var.enable_local_cors ? ["http://localhost:4000"] : []
  )

  chart_hashes = {
    for name in ["gateway", "redis", "metabase", "care_be", "care_fe", "dcm4chee"] :
    name => sha1(join("", [
      for f in sort(fileset("${path.module}/../helm_charts/${name}", "**")) :
      filesha1("${path.module}/../helm_charts/${name}/${f}")
    ]))
  }

  gateway_name                = "care-regional-gateway"
  certmanager_tls_secret_name = "${var.org}-${var.app}-${var.environment}-gateway-tls"
  external_tls_secret_name    = "${var.org}-${var.app}-${var.environment}-external-tls"
  use_external_tls            = var.external_tls_cert != null

  metabase_secret_data = {
    MB_DB_TYPE               = "postgres"
    MB_DB_DBNAME             = data.terraform_remote_state.infra.outputs.metabase_database_name
    MB_DB_PORT               = "5432"
    MB_DB_USER               = data.terraform_remote_state.infra.outputs.metabase_database_user
    MB_DB_PASS               = data.terraform_remote_state.infra.outputs.metabase_database_password
    MB_DB_HOST               = data.terraform_remote_state.infra.outputs.metabase_instance_address
    MB_ENCRYPTION_SECRET_KEY = coalesce(var.metabase_encryption_secret_key_override, data.terraform_remote_state.keys.outputs.metabase_encryption_secret_key)
    MB_SITE_NAME             = "CARE Dashboard"
  }

  config_map_data = merge({
    POSTGRES_PORT                                 = 5432
    DJANGO_SECURE_SSL_REDIRECT                    = "False"
    DJANGO_SETTINGS_MODULE                        = "config.settings.production"
    BUCKET_PROVIDER                               = "gcp"
    BUCKET_REGION                                 = var.region
    CSRF_TRUSTED_ORIGINS                          = jsonencode(concat([for d in var.web_domain_name : "https://${d}"], [for d in var.api_domain_name : "https://${d}"]))
    DJANGO_ALLOWED_HOSTS                          = jsonencode(["*"])
    CORS_ALLOWED_ORIGINS                          = jsonencode(local.cors_allowed_origins)
    RATE_LIMIT                                    = "5/10m"
    AWS_REQUEST_CHECKSUM_CALCULATION              = "when_required"
    SNOWSTORM_DEPLOYMENT_URL                      = var.snowstorm_deployment_url
    MAINTAIN_PATIENT_PHONE_NUMBER_IDENTIFIER      = "True"
    MAX_ACTIVE_ENCOUNTERS_PER_PATIENT_IN_FACILITY = "1"
    ADDITIONAL_PLUGS                              = var.additional_plugs
    AUDIT_LOG_ENABLED                             = "True"
    }, var.enable_scribe ? {
    SCRIBE_GOOGLE_PROJECT_ID     = var.project_id
    SCRIBE_GOOGLE_LOCATION       = var.region
    SCRIBE_CHAT_MODEL_NAME       = "google/gemini-2.5-flash"
    SCRIBE_TRANSCRIBE_MODEL_NAME = "google/gemini-2.5-flash"
    SCRIBE_TRANSCRIBE_LANGUAGE   = "en-US"
    SCRIBE_TNC                   = "1. Data Storage and Privacy: All patient data will be stored on state-owned cloud infrastructure managed by the Health Department.<br/><br/>2. User Responsibility: CARE Scribe is a supportive data entry tool. All transcriptions must be solely reviewed and confirmed by the attending doctor or nurse. eGov will not, and does not undertake any responsibility or liability to review and confirm the transcripts of the audio data entered into the tool, and shall bear no liability for errors arising from unverified AI-generated content.<br/><br/>3. Access Control: Access to CARE Scribe (including for use of the tool and the transcripts) will be limited to authorized users via secure, role-based authentication, which shall be the responsibility of the Health Department. All usage will be subject to periodic audit and monitoring.<br/><br/>4. Legal and Security Compliance: All data processing will be fully compliant with applicable data protection laws.<br/><br/>5. Third-party Service Dependency: CARE Scribe relies on third-party AI APIs for transcription. eGov does not provide any warranties regarding the same, and will not be liable for service disruptions, inaccuracies, or changes originating from these external providers."
    } : {}, var.additional_config_map_data, var.enable_dicom ? {
    CARE_RADIOLOGY_DCM4CHEE_DICOMWEB_BASEURL = "http://dcm4chee-arc.${local.namespace_name}.svc.cluster.local:8080/dcm4chee-arc/aets/DCM4CHEE"
  } : {})

  secret_data = merge({
    DJANGO_SECRET_KEY           = data.terraform_remote_state.keys.outputs.django_secret_key
    POSTGRES_DB                 = data.terraform_remote_state.infra.outputs.database_name
    POSTGRES_USER               = data.terraform_remote_state.infra.outputs.database_user
    POSTGRES_HOST               = data.terraform_remote_state.infra.outputs.instance_address
    POSTGRES_PASSWORD           = data.terraform_remote_state.infra.outputs.database_password
    BUCKET_KEY                  = data.terraform_remote_state.infra.outputs.gcs_access_key
    BUCKET_SECRET               = data.terraform_remote_state.infra.outputs.gcs_secret_key
    CELERY_BROKER_URL           = "redis://redis.${local.namespace_name}.svc.cluster.local:6379/0"
    FILE_UPLOAD_BUCKET          = local.patient_bucket_name
    FACILITY_S3_BUCKET          = local.facility_bucket_name
    REDIS_URL                   = "redis://redis.${local.namespace_name}.svc.cluster.local:6379/0"
    DJANGO_ADMIN_URL            = data.terraform_remote_state.keys.outputs.django_admin_password
    DATABASE_URL                = data.terraform_remote_state.infra.outputs.primary_connection_string
    JWKS_BASE64                 = var.jwks_base64
    FILE_UPLOAD_BUCKET_ENDPOINT = "https://storage.googleapis.com"
    FACILITY_S3_BUCKET_ENDPOINT = "https://storage.googleapis.com"
    }, var.enable_scribe ? {
    SCRIBE_GOOGLE_APPLICATION_CREDENTIALS_B64 = data.terraform_remote_state.infra.outputs.scribe_sa_key_b64
    } : {}, var.additional_secrets, var.enable_dicom ? {
    CARE_RADIOLOGY_WEBHOOK_SECRET = random_password.dicom_webhook_secret[0].result
  } : {})

  common_helm_values = {
    global = {
      cloudProvider = "gcp"
      namespace     = local.namespace_name
      gateway = {
        name             = local.gateway_name
        namespace        = local.namespace_name
        gatewayClassName = "gke-l7-regional-external-managed"
      }
      backendPolicy = {
        enabled        = true
        securityPolicy = data.terraform_remote_state.infra.outputs.security_policy_name
      }
      httpRoute = {
        enabled = true
      }
    }
  }

  # Care backend service port (used by DICOM nginx auth proxy)
  care_backend_port = 9000

  # Legacy ingress support (opt-in via config)
  enable_legacy_ingress  = var.enable_legacy_ingress
  legacy_ingress_ip_name = coalesce(var.legacy_ingress_ip_name, "care-pip")
  legacy_fe_ip_name      = coalesce(var.legacy_fe_ip_name, "care-fe")

  # DICOM secret data (only evaluated when enable_dicom = true)
  dicom_secret_data = var.enable_dicom ? {
    POSTGRES_DB                   = data.terraform_remote_state.infra.outputs.dicom_database_name
    POSTGRES_USER                 = data.terraform_remote_state.infra.outputs.dicom_database_user
    POSTGRES_PASSWORD             = data.terraform_remote_state.infra.outputs.dicom_database_password
    POSTGRES_HOST                 = data.terraform_remote_state.infra.outputs.instance_address
    DATABASE_URL                  = data.terraform_remote_state.infra.outputs.dicom_connection_string
    LDAP_ADMIN_PASSWORD           = random_password.ldap_admin_password.result
    DICOM_BUCKET_NAME             = data.terraform_remote_state.infra.outputs.dicom_bucket_name
    GCS_ACCESS_KEY                = data.terraform_remote_state.infra.outputs.gcs_access_key
    GCS_SECRET_KEY                = data.terraform_remote_state.infra.outputs.gcs_secret_key
    CARE_RADIOLOGY_WEBHOOK_SECRET = random_password.dicom_webhook_secret[0].result
  } : {}
}
