# static bucketはdual-regionでregion固有ではないため、backend bucketもrootに置く。
# lb.tfのURL mapがdefault_serviceでこれを指し、`/api/*`のみnginx backend serviceへ振る
resource "google_compute_backend_bucket" "static" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name        = "bunshin-static"
  bucket_name = google_storage_bucket.static.name
  enable_cdn  = true

  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    client_ttl                   = 3600
    default_ttl                  = 3600
    max_ttl                      = 86400
    negative_caching             = true
    serve_while_stale            = 86400
    signed_url_cache_max_age_sec = 7200
  }
}
