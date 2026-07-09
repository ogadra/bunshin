resource "google_logging_project_bucket_config" "bunshin_logs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  project        = data.google_project.current.project_id
  location       = "global"
  bucket_id      = "bunshin-logs"
  retention_days = 365
  locked         = true

  depends_on = [google_project_service.apis["logging.googleapis.com"]]
}

resource "google_logging_project_sink" "default" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name        = "_Default"
  project     = data.google_project.current.project_id
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.bunshin_logs.id}"
}
