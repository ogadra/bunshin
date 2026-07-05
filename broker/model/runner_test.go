// Package model はドメインモデルのテストを提供する。
package model

import "testing"

// TestRunner_IsIdle は State == StateIdle のときのみ idle と判定されることを検証する。
func TestRunner_IsIdle(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		runner Runner
		want   bool
	}{
		{
			name:   "idle when state is idle",
			runner: Runner{RunnerID: "r1", State: StateIdle},
			want:   true,
		},
		{
			name:   "idle when state is idle with privateURL",
			runner: Runner{RunnerID: "r1", State: StateIdle, PrivateURL: "http://10.0.0.1:8080"},
			want:   true,
		},
		{
			name:   "not idle when currentSessionId is set",
			runner: Runner{RunnerID: "r1", CurrentSessionID: "sess-1"},
			want:   false,
		},
		{
			name:   "not idle when state is empty",
			runner: Runner{RunnerID: "r1"},
			want:   false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := tt.runner.IsIdle(); got != tt.want {
				t.Errorf("IsIdle() = %v, want %v", got, tt.want)
			}
		})
	}
}

// TestRunner_IsBusy は CurrentSessionID が非空のときのみ busy と判定されることを検証する。
func TestRunner_IsBusy(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		runner Runner
		want   bool
	}{
		{
			name:   "busy when currentSessionId is set",
			runner: Runner{RunnerID: "r1", CurrentSessionID: "sess-1"},
			want:   true,
		},
		{
			name:   "busy when currentSessionId is set with privateURL",
			runner: Runner{RunnerID: "r1", CurrentSessionID: "sess-1", PrivateURL: "http://10.0.0.1:8080"},
			want:   true,
		},
		{
			name:   "not busy when currentSessionId is empty",
			runner: Runner{RunnerID: "r1", State: StateIdle},
			want:   false,
		},
		{
			name:   "not busy when both empty",
			runner: Runner{RunnerID: "r1"},
			want:   false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := tt.runner.IsBusy(); got != tt.want {
				t.Errorf("IsBusy() = %v, want %v", got, tt.want)
			}
		})
	}
}
