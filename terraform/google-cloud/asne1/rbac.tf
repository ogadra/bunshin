# Kubernetes API 内の認可は IAM ではなく RBAC。Google identity (`user:...` / `serviceAccount:...`) を
# subject にした ClusterRoleBinding を貼り、deploy 主体が cluster-admin として振る舞えるようにする。
# Google identity は Connect Gateway 経由で email として RBAC に届くため、IAM member の prefix
# (`user:` / `serviceAccount:` / `group:`) を除いた部分が RBAC subject 名になる
resource "kubernetes_cluster_role_binding_v1" "deployer_admin" {
  metadata {
    name = "bunshin-deployer-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = split(":", var.deployer_iam_member)[1]
  }
}
