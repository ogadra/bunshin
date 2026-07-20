package main

import (
	"context"
	"log"
	"os"
	"os/exec"
	"syscall"
	"time"
)

const (
	perlAppRestartDelay  = 500 * time.Millisecond
	perlAppShutdownGrace = 5 * time.Second
)

func supervise(ctx context.Context, name string, factory func() *exec.Cmd, restartDelay, shutdownGrace time.Duration) {
	for ctx.Err() == nil {
		superviseOnce(ctx, name, factory, shutdownGrace)
		if ctx.Err() != nil {
			return
		}
		log.Printf("supervisor: %s restarting in %s", name, restartDelay)
		if !supervisorSleep(ctx, restartDelay) {
			return
		}
	}
}

func superviseOnce(ctx context.Context, name string, factory func() *exec.Cmd, shutdownGrace time.Duration) {
	cmd := factory()
	if err := cmd.Start(); err != nil {
		log.Printf("supervisor: %s start: %v", name, err)
		return
	}
	log.Printf("supervisor: %s started pid=%d", name, cmd.Process.Pid)

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		log.Printf("supervisor: %s exited: %v", name, err)
	case <-ctx.Done():
		log.Printf("supervisor: %s sending SIGTERM", name)
		_ = cmd.Process.Signal(syscall.SIGTERM)
		select {
		case <-done:
		case <-time.After(shutdownGrace):
			log.Printf("supervisor: %s SIGTERM timed out after %s, sending SIGKILL", name, shutdownGrace)
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

func perlAppFactory() *exec.Cmd {
	c := exec.Command("perl", "/app/server.pl")
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	return c
}

func runAppSupervisor(ctx context.Context) {
	supervise(ctx, "perl-app", perlAppFactory, perlAppRestartDelay, perlAppShutdownGrace)
}

var runAppSupervisorFn = runAppSupervisor
