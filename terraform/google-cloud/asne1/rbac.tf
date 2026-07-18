# Kubernetes API内の認可はIAMではなくRBACで解決される。apply主体のGoogle identity emailを
# subjectにしたClusterRoleBindingを貼らないと、Connect Gateway経由のAPI呼び出しが認可されない。
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
    name      = var.deployer_email
  }

  depends_on = [terraform_data.cluster_ready]
}
