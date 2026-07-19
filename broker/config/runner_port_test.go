package config

import (
	"testing"
)

func TestNewRunnerPortFromEnv_Missing(t *testing.T) {
	t.Setenv("RUNNER_PORT", "")
	if _, err := NewRunnerPortFromEnv(); err == nil {
		t.Fatal("expected error for missing RUNNER_PORT")
	}
}

func TestNewRunnerPortFromEnv_Invalid(t *testing.T) {
	for _, v := range []string{"abc", "0", "-1", "65536", "0.5", "3000abc"} {
		v := v
		t.Run(v, func(t *testing.T) {
			t.Setenv("RUNNER_PORT", v)
			if _, err := NewRunnerPortFromEnv(); err == nil {
				t.Errorf("expected error for RUNNER_PORT=%q", v)
			}
		})
	}
}

func TestNewRunnerPortFromEnv_Valid(t *testing.T) {
	t.Setenv("RUNNER_PORT", "3000")
	port, err := NewRunnerPortFromEnv()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if port != 3000 {
		t.Errorf("port = %d, want 3000", port)
	}
}

func TestNewRunnerPortFromEnv_Whitespace(t *testing.T) {
	t.Setenv("RUNNER_PORT", "   5000  ")
	port, err := NewRunnerPortFromEnv()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if port != 5000 {
		t.Errorf("port = %d, want 5000", port)
	}
}

func TestNewRunnerPortFromEnv_Boundary(t *testing.T) {
	for _, tc := range []struct {
		v    string
		want int
	}{
		{"1", 1},
		{"65535", 65535},
	} {
		tc := tc
		t.Run(tc.v, func(t *testing.T) {
			t.Setenv("RUNNER_PORT", tc.v)
			port, err := NewRunnerPortFromEnv()
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if port != tc.want {
				t.Errorf("port = %d, want %d", port, tc.want)
			}
		})
	}
}
