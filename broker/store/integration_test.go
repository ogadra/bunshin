//go:build integration

// Package store は DynamoDB Local を使った統合テストを提供する。
package store

import (
	"context"
	"errors"
	"fmt"
	"sort"
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

// TestIntegration_RegisterConflict_SamePrivateURL は既存 runnerId への同一 privateURL 再登録が ErrConflict を返す統合テスト。
func TestIntegration_RegisterConflict_SamePrivateURL(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("first Register: %v", err)
	}
	err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080")
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

// TestIntegration_RegisterConflict_DifferentPrivateURL は既存 runnerId への異なる privateURL 再登録が ErrConflict を返す統合テスト。
func TestIntegration_RegisterConflict_DifferentPrivateURL(t *testing.T) {
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

// TestIntegration_AcquireIdle は idle runner 確保後に state = busy になり GSI item が残ることを検証する統合テスト。
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
	if runner.State != model.StateBusy {
		t.Errorf("state = %q, want %q", runner.State, model.StateBusy)
	}
	if runner.PrivateURL != "http://10.0.0.1:8080" {
		t.Errorf("privateURL = %q, want %q (state-index projection must include privateUrl)", runner.PrivateURL, "http://10.0.0.1:8080")
	}

	persisted, err := repo.FindByID(ctx, "11111111111111111111111111111111")
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if persisted.State != model.StateBusy {
		t.Errorf("persisted state = %q, want %q", persisted.State, model.StateBusy)
	}
	if persisted.PrivateURL != "http://10.0.0.1:8080" {
		t.Errorf("persisted privateURL = %q, want %q", persisted.PrivateURL, "http://10.0.0.1:8080")
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

// TestIntegration_ListBusyRunners_All は busy にした全 runner を 1 度の呼び出しで受け取れることを検証する統合テスト。
func TestIntegration_ListBusyRunners_All(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	const total = 5
	want := make([]string, 0, total)
	for i := range total {
		id := fmt.Sprintf("%02d%030d", i, 0)
		want = append(want, id)
		if err := repo.Register(ctx, id, fmt.Sprintf("http://10.0.0.%d:8080", i+1)); err != nil {
			t.Fatalf("Register %s: %v", id, err)
		}
		if _, err := repo.AcquireIdle(ctx, fmt.Sprintf("sess-%02d", i)); err != nil {
			t.Fatalf("AcquireIdle: %v", err)
		}
	}

	runners, err := repo.ListBusyRunners(ctx)
	if err != nil {
		t.Fatalf("ListBusyRunners: %v", err)
	}
	got := make([]string, 0, len(runners))
	for _, r := range runners {
		if r.State != model.StateBusy {
			t.Errorf("state = %q, want %q", r.State, model.StateBusy)
		}
		if r.PrivateURL == "" {
			t.Errorf("runner %s: privateURL empty; state-index projection must include privateUrl", r.RunnerID)
		}
		got = append(got, r.RunnerID)
	}

	sort.Strings(got)
	sort.Strings(want)
	if len(got) != len(want) {
		t.Fatalf("len(got) = %d, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("got[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

// TestIntegration_ListBusyRunners_Empty は busy runner がいない場合に空リストを返す統合テスト。
func TestIntegration_ListBusyRunners_Empty(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	runners, err := repo.ListBusyRunners(context.Background())
	if err != nil {
		t.Fatalf("ListBusyRunners: %v", err)
	}
	if len(runners) != 0 {
		t.Errorf("len(runners) = %d, want 0", len(runners))
	}
}

// TestIntegration_ListBusyRunners_ExcludesIdle は idle runner が busy 一覧に含まれないことを検証する統合テスト。
func TestIntegration_ListBusyRunners_ExcludesIdle(t *testing.T) {
	t.Parallel()
	client, tableName := setupIntegrationTable(t)
	repo := NewDynamoRepository(client, tableName)

	ctx := context.Background()

	if err := repo.Register(ctx, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}
	if err := repo.Register(ctx, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "http://10.0.0.2:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}
	// AcquireIdle はランダム選択のため、bbbb を確実に busy 化するには assignSession を直接叩く。
	if err := repo.assignSession(ctx, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sess-1"); err != nil {
		t.Fatalf("assignSession: %v", err)
	}

	runners, err := repo.ListBusyRunners(ctx)
	if err != nil {
		t.Fatalf("ListBusyRunners: %v", err)
	}
	if len(runners) != 1 {
		t.Fatalf("len(runners) = %d, want 1", len(runners))
	}
	if runners[0].RunnerID != "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" {
		t.Errorf("runnerID = %q, want %q", runners[0].RunnerID, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
	}
}
