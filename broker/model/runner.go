// Package model はドメインモデルを提供する。
package model

// State は runner の状態を表す。DynamoDB の state 属性および state-index GSI の hash key に対応する。
// idle 遷移で属性が入り、busy 遷移で属性が消える sparse 表現。
type State string

// StateIdle はセッション未割当の状態。state 属性が存在するときのみこの値をとる。
const StateIdle State = "idle"

// Runner は broker が管理する runner のドメインモデル。
// runner は使い捨てであり、セッション終了時または異常終了時はレコードごと削除する。
type Runner struct {
	// RunnerID は runner の一意識別子であり DynamoDB の PK。
	RunnerID string `dynamodbav:"runnerId"`
	// State は idle 時のみ StateIdle を持つ sparse 属性。sparse GSI state-index の hash key。
	State State `dynamodbav:"state,omitempty"`
	// CurrentSessionID は busy 時のセッション ID。sparse GSI session-index の key。
	CurrentSessionID string `dynamodbav:"currentSessionId,omitempty"`
	// PrivateURL は runner のプライベート URL。セッション解決時に返却する。
	PrivateURL string `dynamodbav:"privateUrl,omitempty"`
}

// IsIdle は runner が idle 状態かを返す。
func (r *Runner) IsIdle() bool {
	return r.State == StateIdle
}

// IsBusy は runner が busy 状態かを返す。
func (r *Runner) IsBusy() bool {
	return r.CurrentSessionID != ""
}
