locals {
  # cross-cloud 到達が未成立 (P5-e #231 未実装) の stack を候補に入れると fallback が失敗するため、
  # ここでは自 cloud の 2 stack のみ持つ。region 名は固定公開値なので variable にしない
  bunshin_stacks = [
    "asia-northeast1",
    "asia-northeast2",
  ]

  # 機密ではない静的な replica 数はtfvarsから注入せず、コード側に固定して意図を残す
  desired_counts = {
    nginx  = 3
    broker = 3
    runner = 300
  }
}
