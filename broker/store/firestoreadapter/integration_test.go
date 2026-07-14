//go:build integration

package firestoreadapter_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/ogadra/bunshin/broker/model"
	"github.com/ogadra/bunshin/broker/store"
	"github.com/ogadra/bunshin/broker/store/firestoreadapter"
)

// firestoreProjectSeq は emulator 上の projectID を衝突不能にするためのプロセス内カウンタ。
// t.Parallel() 下で同一 nanosecond に time.Now() が並ぶ race を排除する。
var firestoreProjectSeq atomic.Uint64

// setupFirestoreIntegration は Firestore emulator を projectID で isolate した Repository を返す。
// t.Cleanup で client を close し、複数 test の gRPC connection を残さない。
func setupFirestoreIntegration(t *testing.T) *store.FirestoreRepository {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" {
		t.Skip("FIRESTORE_EMULATOR_HOST not set, skipping Firestore integration test")
	}
	// Firestore projectID は小文字英数 + ハイフンのみ、6-30 文字。
	// t.Name() は大文字と '_', '/' を含むため置換 & 小文字化する。
	// 衝突回避に unique seq を末尾に添え、余った長さで t.Name() を prefix する。
	suffix := fmt.Sprintf("-%d", firestoreProjectSeq.Add(1))
	const prefix = "bunshin-fs-"
	nameBudget := 30 - len(prefix) - len(suffix)
	safeName := strings.NewReplacer("_", "-", "/", "-").Replace(strings.ToLower(t.Name()))
	if len(safeName) > nameBudget {
		safeName = safeName[:nameBudget]
	}
	projectID := prefix + safeName + suffix
	repo, err := firestoreadapter.NewRepository(context.Background(), projectID, "(default)")
	if err != nil {
		t.Fatalf("firestoreadapter.NewRepository: %v", err)
	}
	t.Cleanup(func() {
		if err := repo.Close(); err != nil {
			t.Errorf("repo.Close: %v", err)
		}
	})
	return repo
}

func TestIntegration_Firestore_RegisterAndFindByID(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
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

func TestIntegration_Firestore_RegisterConflict(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("first Register: %v", err)
	}
	err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.2:9090")
	if !errors.Is(err, store.ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

func TestIntegration_Firestore_AcquireIdle(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
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
		t.Errorf("privateURL = %q, want %q", runner.PrivateURL, "http://10.0.0.1:8080")
	}

	persisted, err := repo.FindByID(ctx, "11111111111111111111111111111111")
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if persisted.CurrentSessionID != "sess-1" {
		t.Errorf("persisted currentSessionId = %q, want %q", persisted.CurrentSessionID, "sess-1")
	}
}

func TestIntegration_Firestore_AcquireIdle_Empty(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, store.ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
}

func TestIntegration_Firestore_AcquireIdle_FindBySessionID(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
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

func TestIntegration_Firestore_AcquireIdle_AlreadyBusy(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}
	if _, err := repo.AcquireIdle(ctx, "sess-1"); err != nil {
		t.Fatalf("first AcquireIdle: %v", err)
	}

	_, err := repo.AcquireIdle(ctx, "sess-2")
	if !errors.Is(err, store.ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
}

func TestIntegration_Firestore_Delete(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
	ctx := context.Background()

	if err := repo.Register(ctx, "11111111111111111111111111111111", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}
	if err := repo.Delete(ctx, "11111111111111111111111111111111"); err != nil {
		t.Fatalf("Delete: %v", err)
	}

	_, err := repo.FindByID(ctx, "11111111111111111111111111111111")
	if !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound after delete, got: %v", err)
	}
}

func TestIntegration_Firestore_Delete_Idempotent(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)

	err := repo.Delete(context.Background(), "11111111111111111111111111111111")
	if err != nil {
		t.Fatalf("expected nil for idempotent delete, got: %v", err)
	}
}

func TestIntegration_Firestore_FindBySessionID_NotFound(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)

	_, err := repo.FindBySessionID(context.Background(), "sess-missing")
	if !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

func TestIntegration_Firestore_FindByID_NotFound(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)

	_, err := repo.FindByID(context.Background(), "22222222222222222222222222222222")
	if !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

func TestIntegration_Firestore_ListBusyRunners_All(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
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
			t.Errorf("runner %s: privateURL empty", r.RunnerID)
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

func TestIntegration_Firestore_ListBusyRunners_Empty(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)

	runners, err := repo.ListBusyRunners(context.Background())
	if err != nil {
		t.Fatalf("ListBusyRunners: %v", err)
	}
	if len(runners) != 0 {
		t.Errorf("len(runners) = %d, want 0", len(runners))
	}
}

// ListBusyRunners は busy な doc だけを返す契約を、AcquireIdle した 1 件と登録のみ 1 件の 2 doc で検証する。
// どちらが acquired 側になるかは random start に依存するため id で判別する。
func TestIntegration_Firestore_ListBusyRunners_ExcludesIdle(t *testing.T) {
	t.Parallel()
	repo := setupFirestoreIntegration(t)
	ctx := context.Background()

	if err := repo.Register(ctx, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("Register aaaa: %v", err)
	}
	if err := repo.Register(ctx, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "http://10.0.0.2:8080"); err != nil {
		t.Fatalf("Register bbbb: %v", err)
	}
	acquired, err := repo.AcquireIdle(ctx, "sess-1")
	if err != nil {
		t.Fatalf("AcquireIdle: %v", err)
	}

	runners, err := repo.ListBusyRunners(ctx)
	if err != nil {
		t.Fatalf("ListBusyRunners: %v", err)
	}
	if len(runners) != 1 {
		t.Fatalf("len(runners) = %d, want 1 (idle 側は除外される)", len(runners))
	}
	if runners[0].RunnerID != acquired.RunnerID {
		t.Errorf("busy runnerID = %q, want %q", runners[0].RunnerID, acquired.RunnerID)
	}
}
