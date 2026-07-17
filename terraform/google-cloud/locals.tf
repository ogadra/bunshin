locals {
  # cross-cloud到達がまだ成立していないため、自cloudの2 stackのみ持つ。region名は固定公開値なので
  # variableにしない
  bunshin_stacks = [
    "asia-northeast1",
    "asia-northeast2",
  ]

  # 機密ではない静的なreplica数はtfvarsから注入せず、コード側に固定して意図を残す
  desired_counts = {
    nginx  = 3
    broker = 3
    runner = 300
  }

  common_labels = {
    project    = "bunshin"
    managed_by = "terraform"
  }
}
