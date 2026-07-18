package main

import (
	"context"
	"log"
	"os"
	"os/exec"
	"syscall"
	"time"
)

// All fields are required: callers assemble the whole struct so a test can
// never accidentally inherit a production timing.
type supervisorConfig struct {
	name          string
	factory       func() *exec.Cmd
	logf          func(format string, args ...any)
	sleep         func(ctx context.Context, d time.Duration) bool
	after         func(d time.Duration) <-chan time.Time
	restartDelay  time.Duration
	shutdownGrace time.Duration
}

func supervise(ctx context.Context, cfg supervisorConfig) {
	for ctx.Err() == nil {
		superviseOnce(ctx, cfg)
		if ctx.Err() != nil {
			return
		}
		cfg.logf("supervisor: %s restarting in %s", cfg.name, cfg.restartDelay)
		if !cfg.sleep(ctx, cfg.restartDelay) {
			return
		}
	}
}

func superviseOnce(ctx context.Context, cfg supervisorConfig) {
	cmd := cfg.factory()
	if err := cmd.Start(); err != nil {
		cfg.logf("supervisor: %s start: %v", cfg.name, err)
		return
	}
	cfg.logf("supervisor: %s started pid=%d", cfg.name, cmd.Process.Pid)

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		cfg.logf("supervisor: %s exited: %v", cfg.name, err)
	case <-ctx.Done():
		cfg.logf("supervisor: %s sending SIGTERM", cfg.name)
		_ = cmd.Process.Signal(syscall.SIGTERM)
		select {
		case <-done:
		case <-cfg.after(cfg.shutdownGrace):
			cfg.logf("supervisor: %s SIGTERM timed out after %s, sending SIGKILL", cfg.name, cfg.shutdownGrace)
			_ = cmd.Process.Kill()
			<-done
		}
	}
}

func supervisorSleep(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}

func productionAppSupervisorConfig() supervisorConfig {
	return supervisorConfig{
		name: "perl-app",
		factory: func() *exec.Cmd {
			c := exec.Command("perl", "/app/server.pl")
			c.Stdout = os.Stdout
			c.Stderr = os.Stderr
			return c
		},
		logf:          log.Printf,
		sleep:         supervisorSleep,
		after:         time.After,
		restartDelay:  500 * time.Millisecond,
		shutdownGrace: 5 * time.Second,
	}
}

// superviseImpl is an indirection so tests can spy on the config that
// runAppSupervisor passes to supervise without spawning a real child.
var superviseImpl = supervise

func runAppSupervisor(ctx context.Context) {
	superviseImpl(ctx, productionAppSupervisorConfig())
}

var runAppSupervisorFn = runAppSupervisor
