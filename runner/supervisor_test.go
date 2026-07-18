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
		now:           time.Now,
		initialDelay:  1 * time.Millisecond,
		maxDelay:      10 * time.Millisecond,
		stableAfter:   1 * time.Hour,
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

func TestSuperviseBackoffProgression(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var mu sync.Mutex
	var delays []time.Duration

	cfg := testSupervisorConfig()
	cfg.initialDelay = 1 * time.Millisecond
	cfg.maxDelay = 5 * time.Millisecond
	cfg.factory = func() *exec.Cmd { return exec.Command("sh", "-c", "exit 0") }
	cfg.sleep = func(ctx context.Context, d time.Duration) bool {
		mu.Lock()
		delays = append(delays, d)
		stop := len(delays) >= 5
		mu.Unlock()
		if stop {
			cancel()
		}
		return true
	}
	supervise(ctx, cfg)

	want := []time.Duration{
		1 * time.Millisecond,
		2 * time.Millisecond,
		4 * time.Millisecond,
		5 * time.Millisecond,
		5 * time.Millisecond,
	}
	mu.Lock()
	got := append([]time.Duration(nil), delays...)
	mu.Unlock()
	if len(got) < len(want) {
		t.Fatalf("delays = %v, want at least %v", got, want)
	}
	for i, w := range want {
		if got[i] != w {
			t.Errorf("delays[%d] = %v, want %v", i, got[i], w)
		}
	}
}

func TestSuperviseBackoffReset(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var mu sync.Mutex
	var delays []time.Duration

	var nowCalls int32
	base := time.Unix(0, 0)

	cfg := testSupervisorConfig()
	cfg.initialDelay = 1 * time.Millisecond
	cfg.maxDelay = 100 * time.Millisecond
	cfg.stableAfter = 50 * time.Millisecond
	cfg.factory = func() *exec.Cmd { return exec.Command("true") }
	cfg.now = func() time.Time {
		n := atomic.AddInt32(&nowCalls, 1)
		switch n {
		case 1:
			return base
		case 2:
			return base.Add(1 * time.Millisecond)
		case 3:
			return base.Add(100 * time.Millisecond)
		case 4:
			return base.Add(200 * time.Millisecond)
		default:
			return base.Add(300 * time.Millisecond)
		}
	}
	cfg.sleep = func(ctx context.Context, d time.Duration) bool {
		mu.Lock()
		delays = append(delays, d)
		stop := len(delays) >= 3
		mu.Unlock()
		if stop {
			cancel()
		}
		return true
	}
	supervise(ctx, cfg)

	want := []time.Duration{
		1 * time.Millisecond,
		1 * time.Millisecond,
		2 * time.Millisecond,
	}
	mu.Lock()
	got := append([]time.Duration(nil), delays...)
	mu.Unlock()
	if len(got) < len(want) {
		t.Fatalf("delays = %v, want at least %v", got, want)
	}
	for i, w := range want {
		if got[i] != w {
			t.Errorf("delays[%d] = %v, want %v", i, got[i], w)
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
		return exec.Command("sh", "-c", "trap '' TERM; while true; do sleep 1; done")
	}
	cfg.shutdownGrace = 100 * time.Millisecond

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
	start := time.Now()
	go func() {
		superviseOnce(ctx, cfg)
		close(done)
	}()

	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("child did not start within 2s")
	}
	time.Sleep(200 * time.Millisecond)
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("superviseOnce did not return within 5s after cancel")
	}
	if elapsed := time.Since(start); elapsed < cfg.shutdownGrace {
		t.Fatalf("superviseOnce returned in %v before shutdownGrace %v, SIGKILL fallback was not exercised", elapsed, cfg.shutdownGrace)
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
	if cfg.initialDelay != time.Second {
		t.Errorf("initialDelay = %v, want %v", cfg.initialDelay, time.Second)
	}
	if cfg.maxDelay != 30*time.Second {
		t.Errorf("maxDelay = %v, want %v", cfg.maxDelay, 30*time.Second)
	}
	if cfg.stableAfter != 30*time.Second {
		t.Errorf("stableAfter = %v, want %v", cfg.stableAfter, 30*time.Second)
	}
	if cfg.shutdownGrace != 5*time.Second {
		t.Errorf("shutdownGrace = %v, want %v", cfg.shutdownGrace, 5*time.Second)
	}
	cmd := cfg.factory()
	if len(cmd.Args) != 2 || cmd.Args[1] != "/app/server.pl" {
		t.Errorf("factory args = %v, want [perl /app/server.pl]", cmd.Args)
	}
	if cfg.logf == nil || cfg.sleep == nil || cfg.after == nil || cfg.now == nil {
		t.Fatal("logf/sleep/after/now must be non-nil")
	}
	cfg.logf("noop %s", "call")
	_ = cfg.now()
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
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	runAppSupervisor(ctx)
}

func containsSubstring(msgs []string, want string) bool {
	for _, m := range msgs {
		if strings.Contains(m, want) {
			return true
		}
	}
	return false
}
