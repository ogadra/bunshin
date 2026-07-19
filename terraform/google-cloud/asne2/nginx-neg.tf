# GKE NEG controller が kubectl 側で apply された nginx Service annotation から生成する
# standalone zonal NEG 群を data で参照し、Global External ALB の backend service への供給元として
# outputs から公開する。

# NEG は kubectl apply 契機で作られるため、cluster / infra だけ先に上げた直後の初回 apply では
# 各 zone に NEG が揃っていない。gcloud で NEG 存在確認をポーリングし、Pod 未スケジュール zone でも
# controller が空 NEG を作るまで待ってから data source を読ませる
resource "terraform_data" "nginx_neg_ready" {
  for_each = toset(local.nginx_neg_zones)

  # Service とその NEG は kubectl 側で管理されるため、Terraform state からは見えない。
  # NEG 名が変わったときだけ再ポーリングし、通常の apply では再走しない
  triggers_replace = [local.nginx_neg_name]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      for i in $(seq 1 60); do
        if gcloud compute network-endpoint-groups describe ${local.nginx_neg_name} \
          --zone=${each.value} \
          --project=${data.google_client_config.default.project} \
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
