# static bucketはdual-regionでregion固有ではないため、backend bucketもrootに置く。
# lb.tfのURL mapがdefault_serviceでこれを指し、`/api/*`のみnginx backend serviceへ振る
resource "google_compute_backend_bucket" "static" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name        = "bunshin-static"
  bucket_name = google_storage_bucket.static.name
  enable_cdn  = true

  # 検証段階のためCloudFrontのManaged-CachingDisabled policy (TTL全0) と対称にする。
  # USE_ORIGIN_HEADERSはGCS object metadataのCache-Controlに従い、未設定ならキャッシュしない
  cdn_policy {
    cache_mode = "USE_ORIGIN_HEADERS"
  }
}
