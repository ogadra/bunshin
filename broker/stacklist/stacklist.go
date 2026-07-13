// Package stacklist は BUNSHIN_STACKS / X-Fallback-Remaining のカンマ区切り stack 値を
// パースする下位ユーティリティを提供する。
// handler (HTTP 層) と config (composition-root) の双方から下位方向として import できるよう、
// どちらのパッケージにも属さない独立パッケージにしている。
package stacklist

import "strings"

// Split はカンマ区切り値を stack 名の並びに分割する。前後空白は削り、空要素は捨てる。
func Split(raw string) []string {
	var stacks []string
	for _, s := range strings.Split(raw, ",") {
		if s = strings.TrimSpace(s); s != "" {
			stacks = append(stacks, s)
		}
	}
	return stacks
}

// Parse は raw を 1 パスで走査し、self を除いた fallback 一覧と self が列挙に含まれていたかを返す。
// self 判定と fallback 抽出を別実装にすると format 変更時に片方だけ更新される
// リスクがあるため、両操作を単一関数に集約している。
func Parse(raw, self string) (fallbacks []string, containsSelf bool) {
	fallbacks = []string{}
	for _, s := range Split(raw) {
		if s == self {
			containsSelf = true
			continue
		}
		fallbacks = append(fallbacks, s)
	}
	return
}
