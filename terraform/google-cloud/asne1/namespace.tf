resource "kubernetes_namespace_v1" "bunshin" {
  metadata {
    name   = "bunshin"
    labels = { app = "bunshin" }
  }

  depends_on = [terraform_data.cluster_ready]
}
