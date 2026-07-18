package main

import (
	"context"
	"os/exec"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// testSupervisorConfig returns a supervisor config wired to fake sinks and
// short timings. Tests override name/factory/logf/sleep as needed.
func testSupervisorConfig() supervisorConfig {
	return supervisorConfig{
		name:          "test",
		factory:       func() *exec.Cmd { return exec.Command("true") },
		logf:          func(format string, args ...any) {},
		sleep:         supervisorSleep,
		after:         time.After,
		restartDelay:  1 * time.Millisecond,
		shutdownGrace: 50 * time.Millisecond,
	}
}

func TestSuperviseImmediateCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	var attempts int32
	cfg := testSupervisorConfig()
	cfg.factory = func() *exec.Cmd {
		atomic.AddInt32(&attempts, 1)
		return exec.Command("true")
	}
	supervise(ctx, cfg)
	if got := atomic.LoadInt32(&attempts); got != 0 {
		t.Fatalf("factory calls = %d, want 0", got)
	}
}

func TestSuperviseStartError(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var attempts int32
	cfg := testSupervisorConfig()
	cfg.factory = func() *exec.Cmd {
		if atomic.AddInt32(&attempts, 1) >= 3 {
			cancel()
		}
		return exec.Command("/nonexistent-supervisor-binary")
	}
	supervise(ctx, cfg)
	if got := atomic.LoadInt32(&attempts); got < 3 {
		t.Fatalf("attempts = %d, want >= 3", got)
	}
}

func TestSuperviseRestartUsesRestartDelay(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var mu sync.Mutex
	var delays []time.Duration

	cfg := testSupervisorConfig()
	cfg.restartDelay = 3 * time.Millisecond
	cfg.factory = func() *exec.Cmd { return exec.Command("sh", "-c", "exit 0") }
	cfg.sleep = func(ctx context.Context, d time.Duration) bool {
		mu.Lock()
		delays = append(delays, d)
		stop := len(delays) >= 4
		mu.Unlock()
		if stop {
			cancel()
		}
		return true
	}
	supervise(ctx, cfg)

	mu.Lock()
	got := append([]time.Duration(nil), delays...)
	mu.Unlock()
	if len(got) < 4 {
		t.Fatalf("delays = %v, want at least 4 samples", got)
	}
	for i, d := range got {
		if d != cfg.restartDelay {
			t.Errorf("delays[%d] = %v, want %v (no backoff)", i, d, cfg.restartDelay)
		}
	}
}

func TestSuperviseSleepCanceled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var attempts int32
	cfg := testSupervisorConfig()
	cfg.factory = func() *exec.Cmd {
		atomic.AddInt32(&attempts, 1)
		return exec.Command("true")
	}
	cfg.sleep = func(ctx context.Context, d time.Duration) bool {
		cancel()
		return false
	}
	supervise(ctx, cfg)
	if got := atomic.LoadInt32(&attempts); got != 1 {
		t.Fatalf("factory calls = %d, want 1", got)
	}
}

func TestSuperviseOnceStartError(t *testing.T) {
	var msgs []string
	cfg := testSupervisorConfig()
	cfg.factory = func() *exec.Cmd { return exec.Command("/nonexistent-superviseonce") }
	cfg.logf = func(format string, args ...any) {
		msgs = append(msgs, format)
	}
	superviseOnce(context.Background(), cfg)
	if !containsSubstring(msgs, "start:") {
		t.Fatalf("logf messages = %v, want one containing 'start:'", msgs)
	}
}

func TestSuperviseOnceNormalExit(t *testing.T) {
	var msgs []string
	cfg := testSupervisorConfig()
	cfg.factory = func() *exec.Cmd { return exec.Command("sh", "-c", "exit 0") }
	cfg.logf = func(format string, args ...any) {
		msgs = append(msgs, format)
	}
	superviseOnce(context.Background(), cfg)
	if !containsSubstring(msgs, "started") {
		t.Fatalf("expected 'started' log, got %v", msgs)
	}
	if !containsSubstring(msgs, "exited") {
		t.Fatalf("expected 'exited' log, got %v", msgs)
	}
}

func TestSuperviseOnceCancelSendsSigterm(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cfg := testSupervisorConfig()
	cfg.factory = func() *exec.Cmd { return exec.Command("sh", "-c", "sleep 30") }

	started := make(chan struct{})
	var mu sync.Mutex
	var startedOnce bool
	cfg.logf = func(format string, args ...any) {
		if strings.Contains(format, "started") {
			mu.Lock()
			if !startedOnce {
				startedOnce = true
				close(started)
			}
			mu.Unlock()
		}
	}

	done := make(chan struct{})
	go func() {
		superviseOnce(ctx, cfg)
		close(done)
	}()

	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("child did not start within 2s")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("superviseOnce did not return within 2s")
	}
}

func TestSuperviseOnceCancelSigkillFallback(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cfg := testSupervisorConfig()
	cfg.factory = func() *exec.Cmd {
		return exec.Command("bash", "-c", `trap "" TERM; echo READY; sleep 30`)
	}
	cfg.shutdownGrace = 100 * time.Millisecond

	ready := make(chan struct{})
	var mu sync.Mutex
	var readyOnce, sawSigkill bool
	logMsgs := []string{}
	cfg.logf = func(format string, args ...any) {
		mu.Lock()
		defer mu.Unlock()
		logMsgs = append(logMsgs, format)
		if strings.Contains(format, "SIGKILL") {
			sawSigkill = true
		}
	}
	origFactory := cfg.factory
	cfg.factory = func() *exec.Cmd {
		c := origFactory()
		stdout, err := c.StdoutPipe()
		if err != nil {
			t.Fatalf("StdoutPipe: %v", err)
		}
		go func() {
			buf := make([]byte, 16)
			for {
				n, err := stdout.Read(buf)
				if n > 0 && strings.Contains(string(buf[:n]), "READY") {
					mu.Lock()
					if !readyOnce {
						readyOnce = true
						close(ready)
					}
					mu.Unlock()
				}
				if err != nil {
					return
				}
			}
		}()
		return c
	}

	done := make(chan struct{})
	go func() {
		superviseOnce(ctx, cfg)
		close(done)
	}()

	select {
	case <-ready:
	case <-time.After(2 * time.Second):
		t.Fatal("child did not print READY within 2s")
	}
	cancelAt := time.Now()
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("superviseOnce did not return within 5s after cancel")
	}
	elapsed := time.Since(cancelAt)
	mu.Lock()
	msgs := append([]string(nil), logMsgs...)
	killed := sawSigkill
	mu.Unlock()
	if elapsed < cfg.shutdownGrace {
		t.Fatalf("superviseOnce returned %v after cancel, before shutdownGrace %v — SIGKILL fallback was not exercised (logs: %v)", elapsed, cfg.shutdownGrace, msgs)
	}
	if !killed {
		t.Fatalf("SIGKILL log was not emitted — SIGKILL fallback branch not taken (logs: %v)", msgs)
	}
}

func TestSupervisorSleepTimerFires(t *testing.T) {
	if !supervisorSleep(context.Background(), 1*time.Millisecond) {
		t.Fatal("supervisorSleep returned false when timer should have fired")
	}
}

func TestSupervisorSleepCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if supervisorSleep(ctx, time.Hour) {
		t.Fatal("supervisorSleep returned true when ctx was canceled")
	}
}

func TestProductionAppSupervisorConfig(t *testing.T) {
	cfg := productionAppSupervisorConfig()
	if cfg.name != "perl-app" {
		t.Errorf("name = %q, want %q", cfg.name, "perl-app")
	}
	if cfg.restartDelay != 500*time.Millisecond {
		t.Errorf("restartDelay = %v, want %v", cfg.restartDelay, 500*time.Millisecond)
	}
	if cfg.shutdownGrace != 5*time.Second {
		t.Errorf("shutdownGrace = %v, want %v", cfg.shutdownGrace, 5*time.Second)
	}
	cmd := cfg.factory()
	if len(cmd.Args) != 2 || cmd.Args[1] != "/app/server.pl" {
		t.Errorf("factory args = %v, want [perl /app/server.pl]", cmd.Args)
	}
	if cfg.logf == nil || cfg.sleep == nil || cfg.after == nil {
		t.Fatal("logf/sleep/after must be non-nil")
	}
	cfg.logf("noop %s", "call")
	select {
	case <-cfg.after(1 * time.Millisecond):
	case <-time.After(1 * time.Second):
		t.Fatal("after channel did not fire")
	}
	sleepCtx, sleepCancel := context.WithCancel(context.Background())
	sleepCancel()
	if cfg.sleep(sleepCtx, time.Hour) {
		t.Fatal("sleep returned true after cancel")
	}
}

func TestRunAppSupervisor(t *testing.T) {
	var gotCtx context.Context
	var gotCfg supervisorConfig
	orig := superviseImpl
	superviseImpl = func(ctx context.Context, cfg supervisorConfig) {
		gotCtx = ctx
		gotCfg = cfg
	}
	defer func() { superviseImpl = orig }()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	runAppSupervisor(ctx)

	if gotCtx != ctx {
		t.Errorf("supervise called with ctx = %v, want %v", gotCtx, ctx)
	}
	want := productionAppSupervisorConfig()
	if gotCfg.name != want.name {
		t.Errorf("name = %q, want %q", gotCfg.name, want.name)
	}
	if gotCfg.restartDelay != want.restartDelay {
		t.Errorf("restartDelay = %v, want %v", gotCfg.restartDelay, want.restartDelay)
	}
	if gotCfg.shutdownGrace != want.shutdownGrace {
		t.Errorf("shutdownGrace = %v, want %v", gotCfg.shutdownGrace, want.shutdownGrace)
	}
	cmd := gotCfg.factory()
	if len(cmd.Args) != 2 || cmd.Args[1] != "/app/server.pl" {
		t.Errorf("factory args = %v, want [perl /app/server.pl]", cmd.Args)
	}
}

func containsSubstring(msgs []string, want string) bool {
	for _, m := range msgs {
		if strings.Contains(m, want) {
			return true
		}
	}
	return false
}
