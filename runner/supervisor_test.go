package main

import (
	"bytes"
	"context"
	"log"
	"os/exec"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func captureLog(t *testing.T) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	origOut, origFlags := log.Writer(), log.Flags()
	log.SetOutput(&buf)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(origOut)
		log.SetFlags(origFlags)
	})
	return &buf
}

func TestSuperviseImmediateCancel(t *testing.T) {
	captureLog(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	var attempts int32
	factory := func() *exec.Cmd {
		atomic.AddInt32(&attempts, 1)
		return exec.Command("true")
	}
	supervise(ctx, "test", factory, 1*time.Millisecond, 50*time.Millisecond)
	if got := atomic.LoadInt32(&attempts); got != 0 {
		t.Fatalf("factory calls = %d, want 0", got)
	}
}

func TestSuperviseStartError(t *testing.T) {
	captureLog(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var attempts int32
	factory := func() *exec.Cmd {
		if atomic.AddInt32(&attempts, 1) >= 3 {
			cancel()
		}
		return exec.Command("/nonexistent-supervisor-binary")
	}
	supervise(ctx, "test", factory, 1*time.Millisecond, 50*time.Millisecond)
	if got := atomic.LoadInt32(&attempts); got < 3 {
		t.Fatalf("attempts = %d, want >= 3", got)
	}
}

func TestSuperviseRestartsAfterExit(t *testing.T) {
	captureLog(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var attempts int32
	factory := func() *exec.Cmd {
		if atomic.AddInt32(&attempts, 1) >= 3 {
			cancel()
		}
		return exec.Command("sh", "-c", "exit 0")
	}
	supervise(ctx, "test", factory, 1*time.Millisecond, 50*time.Millisecond)
	if got := atomic.LoadInt32(&attempts); got < 3 {
		t.Fatalf("attempts = %d, want >= 3", got)
	}
}

func TestSuperviseCancelDuringRestartSleep(t *testing.T) {
	captureLog(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var attempts int32
	factory := func() *exec.Cmd {
		if atomic.AddInt32(&attempts, 1) == 1 {
			go func() {
				time.Sleep(20 * time.Millisecond)
				cancel()
			}()
		}
		return exec.Command("sh", "-c", "exit 0")
	}
	supervise(ctx, "test", factory, time.Hour, 50*time.Millisecond)
	if got := atomic.LoadInt32(&attempts); got != 1 {
		t.Fatalf("factory calls = %d, want 1", got)
	}
}

func TestSuperviseOnceStartError(t *testing.T) {
	buf := captureLog(t)
	factory := func() *exec.Cmd { return exec.Command("/nonexistent-superviseonce") }
	superviseOnce(context.Background(), "test", factory, 50*time.Millisecond)
	if !strings.Contains(buf.String(), "start:") {
		t.Fatalf("log = %q, want substring 'start:'", buf.String())
	}
}

func TestSuperviseOnceNormalExit(t *testing.T) {
	buf := captureLog(t)
	factory := func() *exec.Cmd { return exec.Command("sh", "-c", "exit 0") }
	superviseOnce(context.Background(), "test", factory, 50*time.Millisecond)
	logs := buf.String()
	if !strings.Contains(logs, "started") {
		t.Fatalf("log = %q, want substring 'started'", logs)
	}
	if !strings.Contains(logs, "exited") {
		t.Fatalf("log = %q, want substring 'exited'", logs)
	}
}

func TestSuperviseOnceCancelSendsSigterm(t *testing.T) {
	buf := captureLog(t)
	ctx, cancel := context.WithCancel(context.Background())
	factory := func() *exec.Cmd { return exec.Command("sh", "-c", "sleep 30") }

	done := make(chan struct{})
	go func() {
		superviseOnce(ctx, "test", factory, 500*time.Millisecond)
		close(done)
	}()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if strings.Contains(buf.String(), "started") {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !strings.Contains(buf.String(), "started") {
		cancel()
		<-done
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
	buf := captureLog(t)
	var mu sync.Mutex
	logs := func() string {
		mu.Lock()
		defer mu.Unlock()
		return buf.String()
	}

	ctx, cancel := context.WithCancel(context.Background())
	shutdownGrace := 100 * time.Millisecond
	factory := func() *exec.Cmd {
		return exec.Command("bash", "-c", `trap "" TERM; echo READY; sleep 30`)
	}

	origFactory := factory
	readyMu := sync.Mutex{}
	readyOnce := false
	ready := make(chan struct{})
	factory = func() *exec.Cmd {
		c := origFactory()
		stdout, err := c.StdoutPipe()
		if err != nil {
			t.Fatalf("StdoutPipe: %v", err)
		}
		go func() {
			b := make([]byte, 16)
			for {
				n, err := stdout.Read(b)
				if n > 0 && strings.Contains(string(b[:n]), "READY") {
					readyMu.Lock()
					if !readyOnce {
						readyOnce = true
						close(ready)
					}
					readyMu.Unlock()
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
		superviseOnce(ctx, "test", factory, shutdownGrace)
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
	if elapsed < shutdownGrace {
		t.Fatalf("superviseOnce returned %v after cancel, before shutdownGrace %v — SIGKILL fallback was not exercised (logs: %s)", elapsed, shutdownGrace, logs())
	}
	if !strings.Contains(logs(), "SIGKILL") {
		t.Fatalf("SIGKILL log was not emitted — SIGKILL fallback branch not taken (logs: %s)", logs())
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

func TestPerlAppFactory(t *testing.T) {
	cmd := perlAppFactory()
	if len(cmd.Args) != 2 || cmd.Args[0] != "perl" || cmd.Args[1] != "/app/server.pl" {
		t.Errorf("factory args = %v, want [perl /app/server.pl]", cmd.Args)
	}
}

func TestRunAppSupervisorReturnsOnCancel(t *testing.T) {
	captureLog(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	done := make(chan struct{})
	go func() {
		runAppSupervisor(ctx)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("runAppSupervisor did not return within 2s after ctx cancel")
	}
}
