// Package model はドメインモデルを提供する。
package model

type State string

const StateIdle State = "idle"

type Runner struct {
	RunnerID         string `dynamodbav:"runnerId"`
	State            State  `dynamodbav:"state,omitempty"`
	CurrentSessionID string `dynamodbav:"currentSessionId,omitempty"`
	PrivateURL       string `dynamodbav:"privateUrl,omitempty"`
}

func (r *Runner) IsIdle() bool {
	return r.State == StateIdle
}

func (r *Runner) IsBusy() bool {
	return r.CurrentSessionID != ""
}
