# 会場内NATから同一送信元IPで大量requestが来る前提のため、per-IP rate limitは張らない。
# edge policyはsource IP / geo / header filterの器として残し、必要になったらここへruleを追加する
resource "google_compute_security_policy" "edge" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  # checkov:skip=CKV_GCP_73:Log4j protection is not needed, backend does not use Java
  name        = "bunshin-edge"
  description = "Edge policy container for future source IP / geo / header filters"
  type        = "CLOUD_ARMOR_EDGE"

  rule {
    action      = "allow"
    priority    = 2147483647
    description = "Default rule"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

# backend policy (`CLOUD_ARMOR`)はfull WAFでbody inspectionまで行う。CloudFrontに載せた
# AWSManagedRulesCommonRuleSetと対称のカバレッジを、Google preconfigured OWASP rulesで敷く
resource "google_compute_security_policy" "backend" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  # checkov:skip=CKV_GCP_73:Log4j protection is not needed, backend does not use Java
  name        = "bunshin-backend"
  description = "Backend WAF: OWASP Top 10 preconfigured rules for /api/* backend service"
  type        = "CLOUD_ARMOR"

  rule {
    action      = "deny(403)"
    priority    = 1000
    description = "SQL injection (OWASP A03)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1001
    description = "Cross-site scripting (OWASP A03)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1002
    description = "Local file inclusion (OWASP A05)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1003
    description = "Remote code execution (OWASP A03)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rce-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1004
    description = "Remote file inclusion (OWASP A03)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rfi-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1005
    description = "Protocol attack (OWASP A05)"

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('protocolattack-v33-stable', {'sensitivity': 2})"
      }
    }
  }

  rule {
    action      = "allow"
    priority    = 2147483647
    description = "Default rule"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
