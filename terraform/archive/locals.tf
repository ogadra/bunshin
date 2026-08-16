locals {
  logs_bucket_name        = format("bunshin-logs-%s-%s", data.aws_caller_identity.current.account_id, data.aws_region.current.region)
  logs_export_bucket_name = format("bunshin-logs-export-%s", data.google_project.current.project_id)

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }

  common_labels = {
    project    = "bunshin"
    managed_by = "terraform"
  }
}
