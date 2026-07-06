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
	RegisterRunner(ctx context.Context, runnerID, privateURL string) error
	DeregisterRunner(ctx context.Context, runnerID string) error
}

type ResolveResult struct {
	SessionID  string
	RunnerURL  string
	Created    bool
	Reassigned bool
}

type CreateSessionResult struct {
	SessionID string
	Runner    *model.Runner
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
	return s
}

func defaultSessionFn() (string, error) {
	b := make([]byte, 16)
	if _, err := io.ReadFull(randReader, b); err != nil {
		return "", fmt.Errorf("generate session id: %w", err)
	}
	return hex.EncodeToString(b), nil
}

func (s *BrokerService) createSession(ctx context.Context) (*CreateSessionResult, error) {
	sessionID, err := s.sessionFn()
	if err != nil {
		return nil, err
	}
	sessionID = s.stackPrefix + "_" + sessionID
	check := s.checker != nil
	for {
		runner, err := s.repo.AcquireIdle(ctx, sessionID)
		if err != nil {
			return nil, err
		}
		if !check {
			return &CreateSessionResult{SessionID: sessionID, Runner: runner}, nil
		}
		if checkErr := s.checker.Check(ctx, runner.PrivateURL); checkErr == nil {
			return &CreateSessionResult{SessionID: sessionID, Runner: runner}, nil
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
			if s.checker == nil {
				return &ResolveResult{SessionID: sessionID, RunnerURL: runner.PrivateURL, Created: false}, nil
			}
			if checkErr := s.checker.Check(ctx, runner.PrivateURL); checkErr == nil {
				return &ResolveResult{SessionID: sessionID, RunnerURL: runner.PrivateURL, Created: false}, nil
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
		SessionID:  result.SessionID,
		RunnerURL:  result.Runner.PrivateURL,
		Created:    true,
		Reassigned: reassigned,
	}, nil
}

func (s *BrokerService) RegisterRunner(ctx context.Context, runnerID, privateURL string) error {
	return s.repo.Register(ctx, runnerID, privateURL)
}

func (s *BrokerService) DeregisterRunner(ctx context.Context, runnerID string) error {
	return s.repo.Delete(ctx, runnerID)
}
