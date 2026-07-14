# Kubernetes API 内の認可は IAM ではなく RBAC。Google identity (`user:...` / `serviceAccount:...`) を
# subject にした ClusterRoleBinding を貼り、deploy 主体が cluster-admin として振る舞えるようにする
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
    name      = local.deployer_rbac_user
  }
}
