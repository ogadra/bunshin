// Package service はブローカーのビジネスロジックを提供する。
package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"strings"

	"github.com/ogadra/bunshin/broker/healthcheck"
	"github.com/ogadra/bunshin/broker/model"
	"github.com/ogadra/bunshin/broker/store"
)

// テストで差し替えるため package 変数で保持する。
var (
	randReader io.Reader = rand.Reader
	logPrintf            = log.Printf
)

type Service interface {
	CloseSession(ctx context.Context, sessionID string) error
	ResolveSession(ctx context.Context, sessionID string) (*ResolveResult, error)
	LookupSession(ctx context.Context, sessionHex string) (*LookupResult, error)
	RegisterRunner(ctx context.Context, runnerID, privateHost string) error
	DeregisterRunner(ctx context.Context, runnerID string) error
	ListBusyRunners(ctx context.Context) ([]model.Runner, error)
}

type ResolveResult struct {
	SessionHex string
	RunnerHost string
	Created    bool
	Reassigned bool
}

type LookupResult struct {
	RunnerHost string
}

type CreateSessionResult struct {
	SessionHex string
	Runner     *model.Runner
}

type BrokerService struct {
	repo        store.Repository
	stackPrefix string
	checker     healthcheck.Checker
	sessionFn   func() (string, error)
}

type Option func(*BrokerService)

func WithSessionFn(fn func() (string, error)) Option {
	return func(s *BrokerService) {
		if fn != nil {
			s.sessionFn = fn
		}
	}
}

func WithChecker(c healthcheck.Checker) Option {
	return func(s *BrokerService) {
		s.checker = c
	}
}

func NewBrokerService(repo store.Repository, stackPrefix string, opts ...Option) *BrokerService {
	if stackPrefix == "" {
		panic("service: stackPrefix must not be empty")
	}
	s := &BrokerService{
		repo:        repo,
		stackPrefix: stackPrefix,
		sessionFn:   defaultSessionFn,
	}
	for _, opt := range opts {
		opt(s)
	}
	if s.checker == nil {
		panic("service: checker must not be nil")
	}
	return s
}

func defaultSessionFn() (string, error) {
	b := make([]byte, 16)
	if _, err := io.ReadFull(randReader, b); err != nil {
		return "", fmt.Errorf("generate session id: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// NamespacedSessionID は stack prefix と session hex から cookie に載せる session ID を組み立てる。
// 分解・組み立ての形式知識をこの関数に集約する。
func NamespacedSessionID(stackPrefix, sessionHex string) string {
	return stackPrefix + "_" + sessionHex
}

func (s *BrokerService) namespacedSessionID(sessionHex string) string {
	return NamespacedSessionID(s.stackPrefix, sessionHex)
}

func (s *BrokerService) createSession(ctx context.Context) (*CreateSessionResult, error) {
	sessionHex, err := s.sessionFn()
	if err != nil {
		return nil, err
	}
	sessionID := s.namespacedSessionID(sessionHex)
	for {
		runner, err := s.repo.AcquireIdle(ctx, sessionID)
		if err != nil {
			return nil, err
		}
		if checkErr := s.checker.Check(ctx, runner.PrivateHost); checkErr == nil {
			return &CreateSessionResult{SessionHex: sessionHex, Runner: runner}, nil
		} else if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		logPrintf("healthcheck failed for runner %s, deleting stale record", runner.RunnerID)
		if err := s.repo.Delete(ctx, runner.RunnerID); err != nil {
			return nil, fmt.Errorf("delete unhealthy runner %s: %w", runner.RunnerID, err)
		}
	}
}

func (s *BrokerService) CloseSession(ctx context.Context, sessionID string) error {
	runner, err := s.repo.FindBySessionID(ctx, sessionID)
	if err != nil {
		return err
	}
	return s.repo.Delete(ctx, runner.RunnerID)
}

func (s *BrokerService) ResolveSession(ctx context.Context, sessionID string) (*ResolveResult, error) {
	reassigned := false
	if sessionID != "" {
		runner, err := s.repo.FindBySessionID(ctx, sessionID)
		if err == nil {
			if checkErr := s.checker.Check(ctx, runner.PrivateHost); checkErr == nil {
				// store 上の session ID は createSession が必ず prefix 付きで発行するため、
				// 見つかったのに分解できない場合はデータ不整合として扱う
				_, sessionHex, ok := strings.Cut(sessionID, "_")
				if !ok {
					return nil, fmt.Errorf("resolve session: stored session id missing stack prefix: %q", sessionID)
				}
				return &ResolveResult{SessionHex: sessionHex, RunnerHost: runner.PrivateHost, Created: false}, nil
			} else if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			logPrintf("healthcheck failed for runner %s, deleting stale record", runner.RunnerID)
			if err := s.repo.Delete(ctx, runner.RunnerID); err != nil {
				return nil, fmt.Errorf("delete unhealthy runner %s: %w", runner.RunnerID, err)
			}
			reassigned = true
		} else if !errors.Is(err, store.ErrNotFound) {
			return nil, err
		}
	}
	result, err := s.createSession(ctx)
	if err != nil {
		return nil, err
	}
	return &ResolveResult{
		SessionHex: result.SessionHex,
		RunnerHost: result.Runner.PrivateHost,
		Created:    true,
		Reassigned: reassigned,
	}, nil
}

func (s *BrokerService) LookupSession(ctx context.Context, sessionHex string) (*LookupResult, error) {
	runner, err := s.repo.FindBySessionID(ctx, s.namespacedSessionID(sessionHex))
	if err != nil {
		return nil, err
	}
	return &LookupResult{RunnerHost: runner.PrivateHost}, nil
}

func (s *BrokerService) RegisterRunner(ctx context.Context, runnerID, privateHost string) error {
	return s.repo.Register(ctx, runnerID, privateHost)
}

func (s *BrokerService) DeregisterRunner(ctx context.Context, runnerID string) error {
	return s.repo.Delete(ctx, runnerID)
}

func (s *BrokerService) ListBusyRunners(ctx context.Context) ([]model.Runner, error) {
	return s.repo.ListBusyRunners(ctx)
}
