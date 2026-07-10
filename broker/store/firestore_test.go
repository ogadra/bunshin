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
	createFn        func(ctx context.Context, docID, privateURL string) error
	getFn           func(ctx context.Context, docID string) (*runnerDoc, error)
	deleteFn        func(ctx context.Context, docID string) error
	queryIdleFn     func(ctx context.Context, startAt string) (*runnerDoc, error)
	listBusyFn      func(ctx context.Context) ([]runnerDoc, error)
	findBySessionFn func(ctx context.Context, sessionID string) (*runnerDoc, error)
	assignSessionFn func(ctx context.Context, docID, sessionID string) error
}

func (m *mockFirestoreDB) Create(ctx context.Context, docID, privateURL string) error {
	return m.createFn(ctx, docID, privateURL)
}

func (m *mockFirestoreDB) Get(ctx context.Context, docID string) (*runnerDoc, error) {
	return m.getFn(ctx, docID)
}

func (m *mockFirestoreDB) Delete(ctx context.Context, docID string) error {
	return m.deleteFn(ctx, docID)
}

func (m *mockFirestoreDB) QueryIdle(ctx context.Context, startAt string) (*runnerDoc, error) {
	return m.queryIdleFn(ctx, startAt)
}

func (m *mockFirestoreDB) ListBusy(ctx context.Context) ([]runnerDoc, error) {
	return m.listBusyFn(ctx)
}

func (m *mockFirestoreDB) FindBySession(ctx context.Context, sessionID string) (*runnerDoc, error) {
	return m.findBySessionFn(ctx, sessionID)
}

func (m *mockFirestoreDB) AssignSession(ctx context.Context, docID, sessionID string) error {
	return m.assignSessionFn(ctx, docID, sessionID)
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
		createFn: func(_ context.Context, docID, privateURL string) error {
			called = true
			if docID != firestoreTestRunnerID {
				t.Errorf("docID = %q", docID)
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

// TestFirestoreRegister_AlreadyExists_Idempotent は同一 privateURL の再登録が冪等に成功することを検証する。
func TestFirestoreRegister_AlreadyExists_Idempotent(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(context.Context, string, string) error { return errFirestoreDocExists },
		getFn: func(_ context.Context, docID string) (*runnerDoc, error) {
			return &runnerDoc{RunnerID: docID, PrivateURL: "http://10.0.0.1:8080"}, nil
		},
	})
	if err := repo.Register(context.Background(), firestoreTestRunnerID, "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("expected nil for idempotent register, got: %v", err)
	}
}

// TestFirestoreRegister_AlreadyExists_Conflict は異なる privateURL の再登録が ErrConflict を返すことを検証する。
func TestFirestoreRegister_AlreadyExists_Conflict(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(context.Context, string, string) error { return errFirestoreDocExists },
		getFn: func(_ context.Context, docID string) (*runnerDoc, error) {
			return &runnerDoc{RunnerID: docID, PrivateURL: "http://10.0.0.1:8080"}, nil
		},
	})
	err := repo.Register(context.Background(), firestoreTestRunnerID, "http://10.0.0.2:9090")
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

// TestFirestoreRegister_AlreadyExists_FindByIDError は AlreadyExists 後に FindByID がエラーを返すケースを検証する。
func TestFirestoreRegister_AlreadyExists_FindByIDError(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		createFn: func(context.Context, string, string) error { return errFirestoreDocExists },
		getFn:    func(context.Context, string) (*runnerDoc, error) { return nil, errors.New("get error") },
	})
	err := repo.Register(context.Background(), firestoreTestRunnerID, "http://10.0.0.1:8080")
	if err == nil {
		t.Fatal("expected error")
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
func TestFirestoreAcquireIdle_Success(t *testing.T) {
	t.Parallel()
	assigned := false
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleFn: func(_ context.Context, startAt string) (*runnerDoc, error) {
			if startAt != firestoreTestStart {
				t.Errorf("startAt = %q, want %q", startAt, firestoreTestStart)
			}
			return &runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080"}, nil
		},
		assignSessionFn: func(_ context.Context, docID, sessionID string) error {
			assigned = true
			if docID != "r1" {
				t.Errorf("docID = %q, want r1", docID)
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

// TestFirestoreAcquireIdle_WrapFromHead は乱数開始位置に doc がない場合に先頭から wrap query することを検証する。
func TestFirestoreAcquireIdle_WrapFromHead(t *testing.T) {
	t.Parallel()
	calls := 0
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleFn: func(_ context.Context, startAt string) (*runnerDoc, error) {
			calls++
			switch calls {
			case 1:
				if startAt != firestoreTestStart {
					t.Errorf("first startAt = %q", startAt)
				}
				return nil, nil
			case 2:
				if startAt != "" {
					t.Errorf("wrap startAt = %q, want empty", startAt)
				}
				return &runnerDoc{RunnerID: "r-low", PrivateURL: "http://10.0.0.1:8080"}, nil
			}
			t.Fatalf("unexpected extra QueryIdle call")
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
		t.Errorf("QueryIdle calls = %d, want 2", calls)
	}
}

// TestFirestoreAcquireIdle_NoIdleRunner は idle runner が存在しない場合に ErrNoIdleRunner を返すことを検証する。
func TestFirestoreAcquireIdle_NoIdleRunner(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleFn: func(context.Context, string) (*runnerDoc, error) { return nil, nil },
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
}

// TestFirestoreAcquireIdle_QueryError は QueryIdle がエラーを返す場合を検証する。
func TestFirestoreAcquireIdle_QueryError(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleFn: func(context.Context, string) (*runnerDoc, error) { return nil, errors.New("query error") },
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestFirestoreAcquireIdle_RetryOnConditionFailure は precondition 失敗時に乱数を作り直して retry することを検証する。
func TestFirestoreAcquireIdle_RetryOnConditionFailure(t *testing.T) {
	t.Parallel()
	starts := []string{}
	queryCalls := 0
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleFn: func(_ context.Context, startAt string) (*runnerDoc, error) {
			queryCalls++
			starts = append(starts, startAt)
			if queryCalls == 1 {
				return &runnerDoc{RunnerID: "r-busy", PrivateURL: "http://10.0.0.1:8080"}, nil
			}
			return &runnerDoc{RunnerID: "r-good", PrivateURL: "http://10.0.0.2:8080"}, nil
		},
		assignSessionFn: func(_ context.Context, docID, _ string) error {
			if docID == "r-busy" {
				return ErrConditionFailed
			}
			return nil
		},
	})
	rands := []string{"start-1", "start-2"}
	repo.randHexFn = func() string {
		v := rands[0]
		rands = rands[1:]
		return v
	}

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r-good" {
		t.Errorf("runnerID = %q, want r-good", runner.RunnerID)
	}
	if starts[0] != "start-1" || starts[1] != "start-2" {
		t.Errorf("starts = %v, want [start-1 start-2]", starts)
	}
}

// TestFirestoreAcquireIdle_AssignError は AssignSession の precondition 以外のエラーで即返すことを検証する。
func TestFirestoreAcquireIdle_AssignError(t *testing.T) {
	t.Parallel()
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleFn: func(context.Context, string) (*runnerDoc, error) {
			return &runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080"}, nil
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

// TestFirestoreAcquireIdle_MaxRetries は precondition が maxAcquireRetries 回連続で失敗した場合に ErrNoIdleRunner を返すことを検証する。
func TestFirestoreAcquireIdle_MaxRetries(t *testing.T) {
	t.Parallel()
	queryCalls := 0
	repo := newFirestoreRepoForTest(&mockFirestoreDB{
		queryIdleFn: func(context.Context, string) (*runnerDoc, error) {
			queryCalls++
			return &runnerDoc{RunnerID: "r-stale", PrivateURL: "http://10.0.0.1:8080"}, nil
		},
		assignSessionFn: func(context.Context, string, string) error { return ErrConditionFailed },
	})
	repo.randHexFn = func() string { return firestoreTestStart }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner after retry cap, got: %v", err)
	}
	if queryCalls != maxAcquireRetries {
		t.Errorf("queryCalls = %d, want %d", queryCalls, maxAcquireRetries)
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
		getFn: func(_ context.Context, docID string) (*runnerDoc, error) {
			return &runnerDoc{RunnerID: docID, PrivateURL: "http://10.0.0.1:8080"}, nil
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
		deleteFn: func(_ context.Context, docID string) error {
			called = true
			if docID != "r1" {
				t.Errorf("docID = %q", docID)
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
		createFn: func(_ context.Context, docID, privateURL string) error {
			stored[docID] = privateURL
			return nil
		},
		getFn: func(_ context.Context, docID string) (*runnerDoc, error) {
			url, ok := stored[docID]
			if !ok {
				return nil, nil
			}
			return &runnerDoc{RunnerID: docID, PrivateURL: url}, nil
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

