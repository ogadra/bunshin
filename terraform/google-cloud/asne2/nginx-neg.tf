# GKE NEG controllerがnginx Service annotationから生成するstandalone zonal NEG群をdataで参照し、
# Global External ALBのbackend serviceへの供給元としてoutputsから公開する

# kubernetes_service_v1.nginxへのdepends_onはService作成順しか保証せず、NEG controllerが各zoneで
# NEGを生成し終える前にdataが読まれ初回applyがNot Foundで落ちる。gcloudでNEGの存在確認をポーリング
# してdata読み取りを止め、Podが未スケジュールなzoneでもcontrollerがNEGを空で作るまで待つ
resource "terraform_data" "nginx_neg_ready" {
  for_each = toset(local.nginx_neg_zones)

  triggers_replace = [kubernetes_service_v1.nginx.metadata[0].uid]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      for i in $(seq 1 60); do
        if gcloud compute network-endpoint-groups describe ${local.nginx_neg_name} \
          --zone=${each.value} \
          --project=${data.google_project.current.project_id} \
          >/dev/null 2>&1; then
          exit 0
        fi
        sleep 5
      done
      echo "nginx NEG ${local.nginx_neg_name} in ${each.value} did not appear within 300s" >&2
      exit 1
    EOT
  }
}

data "google_compute_network_endpoint_group" "nginx" {
  for_each = toset(local.nginx_neg_zones)
  name     = local.nginx_neg_name
  zone     = each.value

  depends_on = [terraform_data.nginx_neg_ready]
}
