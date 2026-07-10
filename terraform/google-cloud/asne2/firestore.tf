resource "google_firestore_database" "runners" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # checkov:skip=CKV2_GCP_20:PITR is not required for ephemeral runner state
  name                              = "bunshin-runners-asne2"
  location_id                       = "asia-northeast2"
  type                              = "FIRESTORE_NATIVE"
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_DISABLED"
  delete_protection_state           = "DELETE_PROTECTION_DISABLED"
}
