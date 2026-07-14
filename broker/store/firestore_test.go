// Package store は Firestore Repository のテストを提供する。
package store

import (
	"context"
	"errors"
	"testing"

	"github.com/ogadra/bunshin/broker/model"
)

// firestoreTestRunnerID は Firestore Register テストで使う 32 桁小文字 hex の runnerId。
const firestoreTestRunnerID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

// firestoreTestStart は AcquireIdle テストで固定するランダム開始 runnerId。
const firestoreTestStart = "88888888888888888888888888888888"

// mockFirestoreDB は firestoreDB の mock 実装。フィールドが nil の場合は t.Fatal する。
type mockFirestoreDB struct {
	createFn         func(ctx context.Context, runnerID, privateURL string) error
	getFn            func(ctx context.Context, runnerID string) (*runnerDoc, error)
	deleteFn         func(ctx context.Context, runnerID string) error
	queryIdleRangeFn func(ctx context.Context, after, upTo string, limit int) ([]runnerDoc, error)
	listBusyFn       func(ctx context.Context) ([]runnerDoc, error)
	findBySessionFn  func(ctx context.Context, sessionID string) (*runnerDoc, error)
	assignSessionFn  func(ctx context.Context, runnerID, sessionID string) error
}

func (m *mockFirestoreDB) Create(ctx context.Context, runnerID, privateURL string) error {
	return m.createFn(ctx, runnerID, privateURL)
}

func (m *mockFirestoreDB) Get(ctx context.Context, runnerID string) (*runnerDoc, error) {
	return m.getFn(ctx, runnerID)
}

func (m *mockFirestoreDB) Delete(ctx context.Context, runnerID string) error {
	return m.deleteFn(ctx, runnerID)
}

func (m *mockFirestoreDB) QueryIdleRange(ctx context.Context, after, upTo string, limit int) ([]runnerDoc, error) {
	return m.queryIdleRangeFn(ctx, after, upTo, limit)
}

func (m *mockFirestoreDB) ListBusy(ctx context.Context) ([]runnerDoc, error) {
	return m.listBusyFn(ctx)
}

func (m *mockFirestoreDB) FindBySession(ctx context.Context, sessionID string) (*runnerDoc, error) {
	return m.findBySessionFn(ctx, sessionID)
}

func (m *mockFirestoreDB) AssignSession(ctx context.Context, runnerID, sessionID string) error {
	return m.assignSessionFn(ctx, runnerID, sessionID)
}

func newFirestoreRepoForTest(db firestoreDB) *FirestoreRepository {
	return newFirestoreRepositoryWithDB(db)
}

// TestFirestoreRepository_ImplementsRepository は FirestoreRepository が Repository interface を満たすことを検証する。
func TestFirestoreRepository_ImplementsRepository(t *testing.T) {
	t.Parallel()
	var _ Repository = (*FirestoreRepository)(nil)
}

// TestNewFirestoreRepositoryWithDB はコンストラクタが必要な依存関係を設定することを検証する。
func TestNewFirestoreRepositoryWithDB(t *testing.T) {
	t.Parallel()
	db := &mockFirestoreDB{}
	repo := newFirestoreRepositoryWithDB(db)
	if repo.db != db {
		t.Error("db mismatch")
	}
	if repo.randHexFn == nil {
		t.Error("randHexFn is nil")
	}
}

// TestRunnerDoc_ToModel_Idle は currentSessionId 空文字列の doc が idle として model に変換されることを検証する。
func TestRunnerDoc_ToModel_Idle(t *testing.T) {
	t.Parallel()
	doc := runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080"}
	r := doc.toModel()
	if !r.IsIdle() {
		t.Errorf("expected idle, state = %q", r.State)
	}
	if r.PrivateURL != "http://10.0.0.1:8080" {
		t.Errorf("PrivateURL = %q", r.PrivateURL)
	}
}

// TestRunnerDoc_ToModel_Busy は currentSessionId 有りの doc が busy として model に変換されることを検証する。
func TestRunnerDoc_ToModel_Busy(t *testing.T) {
	t.Parallel()
	doc := runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080", CurrentSessionID: "sess-1"}
	r := doc.toModel()
	if !r.IsBusy() {
		t.Errorf("expected busy, state = %q", r.State)
	}
	if r.CurrentSessionID != "sess-1" {
		t.Errorf("CurrentSessionID = %q", r.CurrentSessionID)
	}
}

// TestSnapshotToDoc は Firestore snapshot data から runnerDoc への変換を検証する。
func TestSnapshotToDoc(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		data map[string]any
		want runnerDoc
	}{
		{
			name: "idle (currentSessionId is nil)",
			data: map[string]any{fieldPrivateURL: "http://10.0.0.1:8080", fieldCurrentSessionID: nil},
			want: runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080"},
		},
		{
			name: "busy",
			data: map[string]any{fieldPrivateURL: "http://10.0.0.1:8080", fieldCurrentSessionID: "sess-1"},
			want: runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080", CurrentSessionID: "sess-1"},
		},
		{
			name: "unexpected field types are ignored",
			data: map[string]any{fieldPrivateURL: 42, fieldCurrentSessionID: 99},
			want: runnerDoc{RunnerID: "r1"},
		},
		{
			name: "empty data yields RunnerID only",
			data: map[string]any{},
			want: runnerDoc{RunnerID: "r1"},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := snapshotToDoc("r1", tc.data)
			if *got != tc.want {
				t.Errorf("got %+v, want %+v", *got, tc.want)
			}
		})
	}
}

// TestFirestoreRegister_InvalidRunnerID は runnerID が 32 桁小文字 hex でない場合に ErrInvalidRunnerID を返すことを検証する。
func TestFirestoreRegister_InvalidRunnerID(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(context.Context, string, string) error {
			t.Fatal("Create should not be called for invalid runnerID")
			return nil
		},
	})
	err := repo.Register(context.Background(), "not-hex", "http://10.0.0.1:8080")
	if !errors.Is(err, ErrInvalidRunnerID) {
		t.Errorf("got %v, want ErrInvalidRunnerID", err)
	}
}

// TestFirestoreRegister_EmptyPrivateURL は privateURL が空の場合にエラーを返すことを検証する。
func TestFirestoreRegister_EmptyPrivateURL(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{})
	if err := repo.Register(context.Background(), firestoreTestRunnerID, ""); err == nil {
		t.Fatal("expected error for empty privateURL")
	}
}

// TestFirestoreRegister_Success は新規登録の成功ケースを検証する。
func TestFirestoreRegister_Success(t *testing.T) {
	t.Parallel()
	called := false
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(_ context.Context, runnerID, privateURL string) error {
			called = true
			if runnerID != firestoreTestRunnerID {
				t.Errorf("runnerID = %q", runnerID)
			}
			if privateURL != "http://10.0.0.1:8080" {
				t.Errorf("privateURL = %q", privateURL)
			}
			return nil
		},
	})
	if err := repo.Register(context.Background(), firestoreTestRunnerID, "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Error("Create was not called")
	}
}

// TestFirestoreRegister_Conflict は Create が ErrConflict を返した場合にそのまま伝播することを検証する。
func TestFirestoreRegister_Conflict(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(context.Context, string, string) error { return ErrConflict },
	})
	err := repo.Register(context.Background(), firestoreTestRunnerID, "http://10.0.0.1:8080")
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

// TestFirestoreRegister_CreateError は Create の予期せぬエラーを検証する。
func TestFirestoreRegister_CreateError(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(context.Context, string, string) error { return errors.New("network error") },
	})
	err := repo.Register(context.Background(), firestoreTestRunnerID, "http://10.0.0.1:8080")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestFirestoreAcquireIdle_Success は乱数開始位置で idle runner を確保できることを検証する。
// (start, ∞) segment から acquireQueryLimit 件以内で候補を得て assign が通るケース。
func TestFirestoreAcquireIdle_Success(t *testing.T) {
	t.Parallel()
	assigned := false
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(_ context.Context, after, upTo string, limit int) ([]runnerDoc, error) {
			if after != firestoreTestStart {
				t.Errorf("after = %q, want %q", after, firestoreTestStart)
			}
			if upTo != "" {
				t.Errorf("upTo = %q, want empty", upTo)
			}
			if limit != acquireQueryLimit {
				t.Errorf("limit = %d, want %d", limit, acquireQueryLimit)
			}
			return []runnerDoc{{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080"}}, nil
		},
		assignSessionFn: func(_ context.Context, runnerID, sessionID string) error {
			assigned = true
			if runnerID != "r1" {
				t.Errorf("runnerID = %q, want r1", runnerID)
			}
			if sessionID != "sess-1" {
				t.Errorf("sessionID = %q, want sess-1", sessionID)
			}
			return nil
		},
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !assigned {
		t.Error("AssignSession was not called")
	}
	if runner.RunnerID != "r1" {
		t.Errorf("runnerID = %q", runner.RunnerID)
	}
	if runner.CurrentSessionID != "sess-1" {
		t.Errorf("currentSessionId = %q", runner.CurrentSessionID)
	}
	if !runner.IsBusy() {
		t.Errorf("expected busy, state = %q", runner.State)
	}
	if runner.PrivateURL != "http://10.0.0.1:8080" {
		t.Errorf("privateURL = %q", runner.PrivateURL)
	}
}

// TestFirestoreAcquireIdle_WrapFromHead は乱数開始位置の後に doc が無い場合に [∅, start] segment で拾えることを検証する。
func TestFirestoreAcquireIdle_WrapFromHead(t *testing.T) {
	t.Parallel()
	calls := 0
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(_ context.Context, after, upTo string, _ int) ([]runnerDoc, error) {
			calls++
			switch calls {
			case 1:
				if after != firestoreTestStart || upTo != "" {
					t.Errorf("call1 (after,upTo) = (%q,%q), want (%q,\"\")", after, upTo, firestoreTestStart)
				}
				return nil, nil
			case 2:
				if after != "" || upTo != firestoreTestStart {
					t.Errorf("call2 (after,upTo) = (%q,%q), want (\"\",%q)", after, upTo, firestoreTestStart)
				}
				return []runnerDoc{{RunnerID: "r-low", PrivateURL: "http://10.0.0.1:8080"}}, nil
			}
			t.Fatalf("unexpected extra QueryIdleRange call")
			return nil, nil
		},
		assignSessionFn: func(context.Context, string, string) error { return nil },
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r-low" {
		t.Errorf("runnerID = %q", runner.RunnerID)
	}
	if calls != 2 {
		t.Errorf("QueryIdleRange calls = %d, want 2", calls)
	}
}

// TestFirestoreAcquireIdle_NoIdleRunner は idle runner が存在しない場合に ErrNoIdleRunner を返すことを検証する。
func TestFirestoreAcquireIdle_NoIdleRunner(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(context.Context, string, string, int) ([]runnerDoc, error) { return nil, nil },
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
}

// TestFirestoreAcquireIdle_QueryError は QueryIdleRange がエラーを返す場合を検証する。
func TestFirestoreAcquireIdle_QueryError(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(context.Context, string, string, int) ([]runnerDoc, error) {
			return nil, errors.New("query error")
		},
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestFirestoreAcquireIdle_SkipStaleInPage は 1 ページ内で precondition 失敗した doc を tried に記録し、
// 同ページ内の次候補で assign を試すことを検証する。
func TestFirestoreAcquireIdle_SkipStaleInPage(t *testing.T) {
	t.Parallel()
	queryCalls := 0
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(context.Context, string, string, int) ([]runnerDoc, error) {
			queryCalls++
			return []runnerDoc{
				{RunnerID: "r-busy", PrivateURL: "http://10.0.0.1:8080"},
				{RunnerID: "r-good", PrivateURL: "http://10.0.0.2:8080"},
			}, nil
		},
		assignSessionFn: func(_ context.Context, runnerID, _ string) error {
			if runnerID == "r-busy" {
				return ErrConditionFailed
			}
			return nil
		},
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r-good" {
		t.Errorf("runnerID = %q, want r-good", runner.RunnerID)
	}
	if queryCalls != 1 {
		t.Errorf("QueryIdleRange calls = %d, want 1 (all candidates from single page)", queryCalls)
	}
}

// TestFirestoreAcquireIdle_AdvanceCursor は 1 ページ全 doc が precondition 失敗のとき、
// cursor を最終 doc の RunnerID 直後まで進めて次ページを引き、そこで assign が通ることを検証する。
func TestFirestoreAcquireIdle_AdvanceCursor(t *testing.T) {
	t.Parallel()
	queryCalls := 0
	firstPage := []runnerDoc{
		{RunnerID: "r-stale-1", PrivateURL: "http://10.0.0.1:8080"},
		{RunnerID: "r-stale-2", PrivateURL: "http://10.0.0.2:8080"},
		{RunnerID: "r-stale-3", PrivateURL: "http://10.0.0.3:8080"},
		{RunnerID: "r-stale-4", PrivateURL: "http://10.0.0.4:8080"},
		{RunnerID: "r-stale-5", PrivateURL: "http://10.0.0.5:8080"},
	}
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(_ context.Context, after, _ string, _ int) ([]runnerDoc, error) {
			queryCalls++
			switch queryCalls {
			case 1:
				if after != firestoreTestStart {
					t.Errorf("call1 after = %q, want %q", after, firestoreTestStart)
				}
				return firstPage, nil
			case 2:
				if after != "r-stale-5" {
					t.Errorf("call2 after = %q, want r-stale-5", after)
				}
				return []runnerDoc{{RunnerID: "r-good", PrivateURL: "http://10.0.0.9:8080"}}, nil
			}
			t.Fatalf("unexpected extra QueryIdleRange call")
			return nil, nil
		},
		assignSessionFn: func(_ context.Context, runnerID, _ string) error {
			if runnerID == "r-good" {
				return nil
			}
			return ErrConditionFailed
		},
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r-good" {
		t.Errorf("runnerID = %q, want r-good", runner.RunnerID)
	}
	if queryCalls != 2 {
		t.Errorf("QueryIdleRange calls = %d, want 2", queryCalls)
	}
}

// TestFirestoreAcquireIdle_AssignError は AssignSession の precondition 以外のエラーで即返すことを検証する。
func TestFirestoreAcquireIdle_AssignError(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(context.Context, string, string, int) ([]runnerDoc, error) {
			return []runnerDoc{{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080"}}, nil
		},
		assignSessionFn: func(context.Context, string, string) error { return errors.New("assign error") },
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected error")
	}
	if errors.Is(err, ErrNoIdleRunner) {
		t.Errorf("expected non-nil non-ErrNoIdleRunner error, got: %v", err)
	}
}

// TestFirestoreAcquireIdle_AllStale は全 idle doc が precondition 失敗を返し続ける場合に、
// segment を走査し尽くして ErrNoIdleRunner を返すことを検証する。
func TestFirestoreAcquireIdle_AllStale(t *testing.T) {
	t.Parallel()
	queryCalls := 0
	assignCalls := 0
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleRangeFn: func(_ context.Context, after, _ string, _ int) ([]runnerDoc, error) {
			queryCalls++
			if after == "r-stale" {
				return nil, nil
			}
			return []runnerDoc{{RunnerID: "r-stale", PrivateURL: "http://10.0.0.1:8080"}}, nil
		},
		assignSessionFn: func(context.Context, string, string) error {
			assignCalls++
			return ErrConditionFailed
		},
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
	if assignCalls != 1 {
		t.Errorf("AssignSession calls = %d, want 1 (tried set skips repeats across segments)", assignCalls)
	}
	if queryCalls == 0 {
		t.Errorf("QueryIdleRange was never called")
	}
}

// TestFirestoreListBusyRunners_Success は busy 一覧が正しく変換されて返ることを検証する。
func TestFirestoreListBusyRunners_Success(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		listBusyFn: func(context.Context) ([]runnerDoc, error) {
			return []runnerDoc{
				{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080", CurrentSessionID: "sess-1"},
				{RunnerID: "r2", PrivateURL: "http://10.0.0.2:8080", CurrentSessionID: "sess-2"},
			}, nil
		},
	})
	runners, err := repo.ListBusyRunners(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runners) != 2 {
		t.Fatalf("len(runners) = %d, want 2", len(runners))
	}
	for i, r := range runners {
		if !r.IsBusy() {
			t.Errorf("runners[%d] not busy", i)
		}
	}
}

// TestFirestoreListBusyRunners_Empty は busy 一覧が空の場合を検証する。
func TestFirestoreListBusyRunners_Empty(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		listBusyFn: func(context.Context) ([]runnerDoc, error) { return nil, nil },
	})
	runners, err := repo.ListBusyRunners(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runners) != 0 {
		t.Errorf("len(runners) = %d, want 0", len(runners))
	}
}

// TestFirestoreListBusyRunners_Error は ListBusy がエラーを返すケースを検証する。
func TestFirestoreListBusyRunners_Error(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		listBusyFn: func(context.Context) ([]runnerDoc, error) { return nil, errors.New("list error") },
	})
	if _, err := repo.ListBusyRunners(context.Background()); err == nil {
		t.Fatal("expected error")
	}
}

// TestFirestoreFindBySessionID_Success は session ID で runner が見つかるケースを検証する。
func TestFirestoreFindBySessionID_Success(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		findBySessionFn: func(_ context.Context, sessionID string) (*runnerDoc, error) {
			return &runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080", CurrentSessionID: sessionID}, nil
		},
	})
	runner, err := repo.FindBySessionID(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r1" {
		t.Errorf("runnerID = %q", runner.RunnerID)
	}
	if !runner.IsBusy() {
		t.Errorf("expected busy, state = %q", runner.State)
	}
}

// TestFirestoreFindBySessionID_NotFound は session が見つからない場合に ErrNotFound を返すことを検証する。
func TestFirestoreFindBySessionID_NotFound(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		findBySessionFn: func(context.Context, string) (*runnerDoc, error) { return nil, nil },
	})
	_, err := repo.FindBySessionID(context.Background(), "sess-x")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

// TestFirestoreFindBySessionID_Error は FindBySession がエラーを返すケースを検証する。
func TestFirestoreFindBySessionID_Error(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		findBySessionFn: func(context.Context, string) (*runnerDoc, error) { return nil, errors.New("find error") },
	})
	if _, err := repo.FindBySessionID(context.Background(), "sess-1"); err == nil {
		t.Fatal("expected error")
	}
}

// TestFirestoreFindByID_Success は runner ID で runner が見つかるケースを検証する。
func TestFirestoreFindByID_Success(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		getFn: func(_ context.Context, runnerID string) (*runnerDoc, error) {
			return &runnerDoc{RunnerID: runnerID, PrivateURL: "http://10.0.0.1:8080"}, nil
		},
	})
	runner, err := repo.FindByID(context.Background(), "r1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r1" {
		t.Errorf("runnerID = %q", runner.RunnerID)
	}
	if !runner.IsIdle() {
		t.Error("expected runner to be idle")
	}
}

// TestFirestoreFindByID_NotFound は runner が存在しない場合に ErrNotFound を返すことを検証する。
func TestFirestoreFindByID_NotFound(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		getFn: func(context.Context, string) (*runnerDoc, error) { return nil, nil },
	})
	_, err := repo.FindByID(context.Background(), "r-missing")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

// TestFirestoreFindByID_Error は Get の予期せぬエラーを検証する。
func TestFirestoreFindByID_Error(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		getFn: func(context.Context, string) (*runnerDoc, error) { return nil, errors.New("get error") },
	})
	if _, err := repo.FindByID(context.Background(), "r1"); err == nil {
		t.Fatal("expected error")
	}
}

// TestFirestoreDelete_Success は正常な削除を検証する。
func TestFirestoreDelete_Success(t *testing.T) {
	t.Parallel()
	called := false
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		deleteFn: func(_ context.Context, runnerID string) error {
			called = true
			if runnerID != "r1" {
				t.Errorf("runnerID = %q", runnerID)
			}
			return nil
		},
	})
	if err := repo.Delete(context.Background(), "r1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Error("Delete was not called")
	}
}

// TestFirestoreDelete_Error は Delete のエラーを検証する。
func TestFirestoreDelete_Error(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		deleteFn: func(context.Context, string) error { return errors.New("delete error") },
	})
	if err := repo.Delete(context.Background(), "r1"); err == nil {
		t.Fatal("expected error")
	}
}

// TestFirestoreRegister_ModelRoundtrip は register / find で model.Runner の PrivateURL 等が壊れずに渡ることを確認する。
func TestFirestoreRegister_ModelRoundtrip(t *testing.T) {
	t.Parallel()
	stored := map[string]string{}
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(_ context.Context, runnerID, privateURL string) error {
			stored[runnerID] = privateURL
			return nil
		},
		getFn: func(_ context.Context, runnerID string) (*runnerDoc, error) {
			url, ok := stored[runnerID]
			if !ok {
				return nil, nil
			}
			return &runnerDoc{RunnerID: runnerID, PrivateURL: url}, nil
		},
	})
	if err := repo.Register(context.Background(), firestoreTestRunnerID, "http://10.0.0.9:8080"); err != nil {
		t.Fatalf("Register: %v", err)
	}
	runner, err := repo.FindByID(context.Background(), firestoreTestRunnerID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if runner.PrivateURL != "http://10.0.0.9:8080" {
		t.Errorf("PrivateURL = %q", runner.PrivateURL)
	}
	if runner.State != model.StateIdle {
		t.Errorf("state = %q, want idle", runner.State)
	}
}
