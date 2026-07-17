package main

import (
	"context"
	"log"
	"os"
	"os/exec"
	"syscall"
	"time"
)

// supervisorConfig configures the process supervisor. All fields are required:
// callers assemble the whole struct so a test can never accidentally inherit a
// production timing.
type supervisorConfig struct {
	name          string
	factory       func() *exec.Cmd
	logf          func(format string, args ...any)
	sleep         func(ctx context.Context, d time.Duration) bool
	after         func(d time.Duration) <-chan time.Time
	now           func() time.Time
	initialDelay  time.Duration
	maxDelay      time.Duration
	stableAfter   time.Duration
	shutdownGrace time.Duration
}

// supervise launches cfg.factory() and restarts it with capped exponential
// backoff on any exit. A run that stayed up at least cfg.stableAfter is
// considered stable and resets backoff to cfg.initialDelay. Returns when ctx
// is canceled.
func supervise(ctx context.Context, cfg supervisorConfig) {
	delay := cfg.initialDelay
	for ctx.Err() == nil {
		start := cfg.now()
		superviseOnce(ctx, cfg)
		if ctx.Err() != nil {
			return
		}
		if cfg.now().Sub(start) >= cfg.stableAfter {
			delay = cfg.initialDelay
		}
		cfg.logf("supervisor: %s restarting in %s", cfg.name, delay)
		if !cfg.sleep(ctx, delay) {
			return
		}
		delay *= 2
		if delay > cfg.maxDelay {
			delay = cfg.maxDelay
		}
	}
}

// superviseOnce launches one process and waits for it to exit. On ctx cancel
// it sends SIGTERM, waits cfg.shutdownGrace, then SIGKILLs and reaps.
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
		_ = cmd.Process.Signal(syscall.SIGTERM)
		select {
		case <-done:
		case <-cfg.after(cfg.shutdownGrace):
			_ = cmd.Process.Kill()
			<-done
		}
	}
}

// supervisorSleep blocks up to d. Returns false when ctx is canceled first.
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

// productionAppSupervisorConfig builds the supervisor config that runs
// perl /app/server.pl inside the runner container.
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
		now:           time.Now,
		initialDelay:  1 * time.Second,
		maxDelay:      30 * time.Second,
		stableAfter:   30 * time.Second,
		shutdownGrace: 5 * time.Second,
	}
}

// runAppSupervisor is main's entry point into the perl-app supervisor. Tests
// override runAppSupervisorFn to substitute a no-op that just blocks on ctx.
func runAppSupervisor(ctx context.Context) {
	supervise(ctx, productionAppSupervisorConfig())
}

var runAppSupervisorFn = runAppSupervisor
