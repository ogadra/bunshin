//go:build integration

// Package store は DynamoDB Local を使った統合テストを提供する。
package store

import (
	"context"
	"errors"
	"testing"

	"github.com/ogadra/bunshin/broker/model"
)

// TestIntegration_RegisterAndFindByID はレコード登録と ID 検索の統合テスト。
func TestIntegration_RegisterAndFindByID(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	runner, err := repo.FindByID(ctx, "11111111111111111111111111111111")
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if runner.RunnerID != "11111111111111111111111111111111" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "11111111111111111111111111111111")
	}
	if runner.State != model.StateIdle {
		t.Errorf("state = %q, want %q", runner.State, model.StateIdle)
	}
	if runner.PrivateURL != "http://10.0.0.1:8080" {
		t.Errorf("privateURL = %q, want %q", runner.PrivateURL, "http://10.0.0.1:8080")
	}
}

// TestIntegration_RegisterIdempotent は登録の冪等性を検証する統合テスト。
func TestIntegration_RegisterIdempotent(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("first Register: %v", err)
	}
	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("second Register should be idempotent: %v", err)
	}
}

// TestIntegration_RegisterConflict は同一 runnerID で異なる privateURL の登録が ErrConflict を返す統合テスト。
func TestIntegration_RegisterConflict(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("first Register: %v", err)
	}
	err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.2:9090")
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

// TestIntegration_AcquireIdle は idle runner 確保後に busy へ遷移し state 属性が消えることを検証する統合テスト。
func TestIntegration_AcquireIdle(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}

	runner, err := repo.AcquireIdle(ctx, "sess-1")
	if err != nil {
		t.Fatalf("AcquireIdle: %v", err)
	}
	if runner.RunnerID != "11111111111111111111111111111111" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "11111111111111111111111111111111")
	}
	if runner.CurrentSessionID != "sess-1" {
		t.Errorf("currentSessionId = %q, want %q", runner.CurrentSessionID, "sess-1")
	}
	if !runner.IsBusy() {
		t.Errorf("expected runner to be busy, got IsBusy=false state=%q", runner.State)
	}
	if runner.IsIdle() {
		t.Errorf("expected runner not to be idle after acquire")
	}

	persisted, err := repo.FindByID(ctx, "11111111111111111111111111111111")
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if persisted.State != "" {
		t.Errorf("persisted state = %q, want empty (attribute removed on busy transition)", persisted.State)
	}
	if persisted.CurrentSessionID != "sess-1" {
		t.Errorf("persisted currentSessionId = %q, want %q", persisted.CurrentSessionID, "sess-1")
	}
}

// TestIntegration_AcquireIdle_Empty は runner がいない場合に ErrNoIdleRunner を返す統合テスト。
func TestIntegration_AcquireIdle_Empty(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
}

// TestIntegration_AcquireIdle_FindBySessionID はセッション確保後にセッション検索できることを検証する統合テスト。
func TestIntegration_AcquireIdle_FindBySessionID(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}

	if _, err := repo.AcquireIdle(ctx, "sess-1"); err != nil {
		t.Fatalf("AcquireIdle: %v", err)
	}

	runner, err := repo.FindBySessionID(ctx, "sess-1")
	if err != nil {
		t.Fatalf("FindBySessionID: %v", err)
	}
	if runner.RunnerID != "11111111111111111111111111111111" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "11111111111111111111111111111111")
	}
}

// TestIntegration_AcquireIdle_AlreadyBusy は全 runner が busy の場合に ErrNoIdleRunner を返す統合テスト。
func TestIntegration_AcquireIdle_AlreadyBusy(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}
	if _, err := repo.AcquireIdle(ctx, "sess-1"); err != nil {
		t.Fatalf("first AcquireIdle: %v", err)
	}

	_, err := repo.AcquireIdle(ctx, "sess-2")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
}

// TestIntegration_AcquireIdle_WrapFromHead は乱数開始位置より前にしか runner がない場合でも wrap query で取得できることを検証する統合テスト。
func TestIntegration_AcquireIdle_WrapFromHead(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)
	// 開始キーを常に "ffff..." にすることで、r-01 は必ず wrap 経路でのみ取得される。
	repo.randHexFn = func() string { return "ffffffffffffffffffffffffffffffff" }

	ctx := context.Background()
	if err := repo.Register(ctx, "0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}

	runner, err := repo.AcquireIdle(ctx, "sess-wrap")
	if err != nil {
		t.Fatalf("AcquireIdle: %v", err)
	}
	if runner.RunnerID != "0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a")
	}
}

// TestIntegration_Delete は runner 削除の統合テスト。
func TestIntegration_Delete(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}
	if err := repo.Delete(ctx, "11111111111111111111111111111111"); err != nil {
		t.Fatalf("Delete: %v", err)
	}

	_, err := repo.FindByID(ctx, "11111111111111111111111111111111")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound after delete, got: %v", err)
	}
}

// TestIntegration_Delete_Idempotent は存在しない runner の削除が冪等に成功する統合テスト。
func TestIntegration_Delete_Idempotent(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	err := repo.Delete(context.Background(), "r-nonexistent")
	if err != nil {
		t.Fatalf("expected nil for idempotent delete, got: %v", err)
	}
}

// TestIntegration_FindBySessionID_NotFound は存在しないセッションの検索で ErrNotFound を返す統合テスト。
func TestIntegration_FindBySessionID_NotFound(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	_, err := repo.FindBySessionID(context.Background(), "sess-missing")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

// TestIntegration_FindByID_NotFound は存在しない runner の検索で ErrNotFound を返す統合テスト。
func TestIntegration_FindByID_NotFound(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	_, err := repo.FindByID(context.Background(), "r-missing")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}
