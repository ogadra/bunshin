// Package store は firestoreClient (firestoreDB を firestoreClientAPI 経由で実装する層) のテストを提供する。
package store

import (
	"context"
	"errors"
	"reflect"
	"testing"
)

// mockFirestoreClientAPI は firestoreClientAPI の mock 実装。
type mockFirestoreClientAPI struct {
	createFn         func(ctx context.Context, docID string, data map[string]any) error
	getFn            func(ctx context.Context, docID string) (map[string]any, bool, error)
	deleteFn         func(ctx context.Context, docID string) error
	queryIdleFn      func(ctx context.Context, startAt string) (string, map[string]any, bool, error)
	iterBusyFn       func(ctx context.Context) firestoreDocIter
	queryBySessionFn func(ctx context.Context, sessionID string) (string, map[string]any, bool, error)
	runTxFn          func(ctx context.Context, fn func(tx firestoreTx) error) error
}

func (m *mockFirestoreClientAPI) Create(ctx context.Context, docID string, data map[string]any) error {
	return m.createFn(ctx, docID, data)
}

func (m *mockFirestoreClientAPI) Get(ctx context.Context, docID string) (map[string]any, bool, error) {
	return m.getFn(ctx, docID)
}

func (m *mockFirestoreClientAPI) Delete(ctx context.Context, docID string) error {
	return m.deleteFn(ctx, docID)
}

func (m *mockFirestoreClientAPI) QueryIdle(ctx context.Context, startAt string) (string, map[string]any, bool, error) {
	return m.queryIdleFn(ctx, startAt)
}

func (m *mockFirestoreClientAPI) IterBusy(ctx context.Context) firestoreDocIter {
	return m.iterBusyFn(ctx)
}

func (m *mockFirestoreClientAPI) QueryBySession(ctx context.Context, sessionID string) (string, map[string]any, bool, error) {
	return m.queryBySessionFn(ctx, sessionID)
}

func (m *mockFirestoreClientAPI) RunTx(ctx context.Context, fn func(tx firestoreTx) error) error {
	return m.runTxFn(ctx, fn)
}

// nextResult は mockFirestoreDocIter が返す値を表す。
type nextResult struct {
	id   string
	data map[string]any
	done bool
	err  error
}

// mockFirestoreDocIter は firestoreDocIter の mock 実装。
type mockFirestoreDocIter struct {
	results     []nextResult
	nextIdx     int
	stopped     bool
	stopCounter *int
}

func (m *mockFirestoreDocIter) Next() (string, map[string]any, bool, error) {
	if m.nextIdx >= len(m.results) {
		return "", nil, true, nil
	}
	r := m.results[m.nextIdx]
	m.nextIdx++
	return r.id, r.data, r.done, r.err
}

func (m *mockFirestoreDocIter) Stop() {
	m.stopped = true
	if m.stopCounter != nil {
		*m.stopCounter++
	}
}

// mockFirestoreTx は firestoreTx の mock 実装。
type mockFirestoreTx struct {
	getFn    func(docID string) (map[string]any, bool, error)
	updateFn func(docID, field string, value any) error
}

func (m *mockFirestoreTx) Get(docID string) (map[string]any, bool, error) {
	return m.getFn(docID)
}

func (m *mockFirestoreTx) Update(docID, field string, value any) error {
	return m.updateFn(docID, field, value)
}

// TestFirestoreClient_ImplementsFirestoreDB は firestoreClient が firestoreDB interface を満たすことを検証する。
func TestFirestoreClient_ImplementsFirestoreDB(t *testing.T) {
	t.Parallel()
	var _ firestoreDB = (*firestoreClient)(nil)
}

// TestFirestoreClient_Create は Create が privateURL + null session の data で api.Create を呼ぶことを検証する。
func TestFirestoreClient_Create(t *testing.T) {
	t.Parallel()
	var gotData map[string]any
	api := &mockFirestoreClientAPI{
		createFn: func(_ context.Context, docID string, data map[string]any) error {
			if docID != "r1" {
				t.Errorf("docID = %q, want r1", docID)
			}
			gotData = data
			return nil
		},
	}
	if err := newFirestoreClient(api).Create(context.Background(), "r1", "http://10.0.0.1:8080"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := map[string]any{fieldPrivateURL: "http://10.0.0.1:8080", fieldCurrentSessionID: nil}
	if !reflect.DeepEqual(gotData, want) {
		t.Errorf("data = %v, want %v", gotData, want)
	}
}

// TestFirestoreClient_Create_Error は Create エラーが伝播することを検証する。
func TestFirestoreClient_Create_Error(t *testing.T) {
	t.Parallel()
	api := &mockFirestoreClientAPI{
		createFn: func(context.Context, string, map[string]any) error {
			return ErrConflict
		},
	}
	err := newFirestoreClient(api).Create(context.Background(), "r1", "http://10.0.0.1:8080")
	if !errors.Is(err, ErrConflict) {
		t.Errorf("expected ErrConflict, got %v", err)
	}
}

// TestFirestoreClient_Get_Exists は Get が data を runnerDoc に変換して返すことを検証する。
func TestFirestoreClient_Get_Exists(t *testing.T) {
	t.Parallel()
	api := &mockFirestoreClientAPI{
		getFn: func(_ context.Context, docID string) (map[string]any, bool, error) {
			if docID != "r1" {
				t.Errorf("docID = %q", docID)
			}
			return map[string]any{fieldPrivateURL: "http://10.0.0.1:8080", fieldCurrentSessionID: "sess-1"}, true, nil
		},
	}
	doc, err := newFirestoreClient(api).Get(context.Background(), "r1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := &runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080", CurrentSessionID: "sess-1"}
	if !reflect.DeepEqual(doc, want) {
		t.Errorf("doc = %+v, want %+v", doc, want)
	}
}

// TestFirestoreClient_Get_NotFound は Get が exists=false のとき nil, nil を返すことを検証する。
func TestFirestoreClient_Get_NotFound(t *testing.T) {
	t.Parallel()
	api := &mockFirestoreClientAPI{
		getFn: func(context.Context, string) (map[string]any, bool, error) {
			return nil, false, nil
		},
	}
	doc, err := newFirestoreClient(api).Get(context.Background(), "r1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if doc != nil {
		t.Errorf("doc = %+v, want nil", doc)
	}
}

// TestFirestoreClient_Get_Error は Get エラーが伝播することを検証する。
func TestFirestoreClient_Get_Error(t *testing.T) {
	t.Parallel()
	want := errors.New("boom")
	api := &mockFirestoreClientAPI{
		getFn: func(context.Context, string) (map[string]any, bool, error) {
			return nil, false, want
		},
	}
	_, err := newFirestoreClient(api).Get(context.Background(), "r1")
	if !errors.Is(err, want) {
		t.Errorf("expected %v, got %v", want, err)
	}
}

// TestFirestoreClient_Delete は Delete が api.Delete を呼ぶことを検証する。
func TestFirestoreClient_Delete(t *testing.T) {
	t.Parallel()
	called := false
	api := &mockFirestoreClientAPI{
		deleteFn: func(_ context.Context, docID string) error {
			called = true
			if docID != "r1" {
				t.Errorf("docID = %q", docID)
			}
			return nil
		},
	}
	if err := newFirestoreClient(api).Delete(context.Background(), "r1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Error("Delete was not called")
	}
}

// TestFirestoreClient_QueryIdle_Exists は QueryIdle が data を runnerDoc に変換して返すことを検証する。
func TestFirestoreClient_QueryIdle_Exists(t *testing.T) {
	t.Parallel()
	api := &mockFirestoreClientAPI{
		queryIdleFn: func(_ context.Context, startAt string) (string, map[string]any, bool, error) {
			if startAt != "abcd" {
				t.Errorf("startAt = %q", startAt)
			}
			return "r2", map[string]any{fieldPrivateURL: "http://10.0.0.2:8080"}, true, nil
		},
	}
	doc, err := newFirestoreClient(api).QueryIdle(context.Background(), "abcd")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := &runnerDoc{RunnerID: "r2", PrivateURL: "http://10.0.0.2:8080"}
	if !reflect.DeepEqual(doc, want) {
		t.Errorf("doc = %+v, want %+v", doc, want)
	}
}

// TestFirestoreClient_QueryIdle_NotFound は QueryIdle が exists=false のとき nil, nil を返すことを検証する。
func TestFirestoreClient_QueryIdle_NotFound(t *testing.T) {
	t.Parallel()
	api := &mockFirestoreClientAPI{
		queryIdleFn: func(context.Context, string) (string, map[string]any, bool, error) {
			return "", nil, false, nil
		},
	}
	doc, err := newFirestoreClient(api).QueryIdle(context.Background(), "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if doc != nil {
		t.Errorf("doc = %+v, want nil", doc)
	}
}

// TestFirestoreClient_QueryIdle_Error は QueryIdle エラーが伝播することを検証する。
func TestFirestoreClient_QueryIdle_Error(t *testing.T) {
	t.Parallel()
	want := errors.New("query boom")
	api := &mockFirestoreClientAPI{
		queryIdleFn: func(context.Context, string) (string, map[string]any, bool, error) {
			return "", nil, false, want
		},
	}
	_, err := newFirestoreClient(api).QueryIdle(context.Background(), "")
	if !errors.Is(err, want) {
		t.Errorf("expected %v, got %v", want, err)
	}
}

// TestFirestoreClient_ListBusy_Multiple は複数 doc を iterator から集めて slice で返すことを検証する。
func TestFirestoreClient_ListBusy_Multiple(t *testing.T) {
	t.Parallel()
	stopCount := 0
	iter := &mockFirestoreDocIter{
		results: []nextResult{
			{id: "r1", data: map[string]any{fieldPrivateURL: "http://10.0.0.1:8080", fieldCurrentSessionID: "sess-1"}, done: false},
			{id: "r2", data: map[string]any{fieldPrivateURL: "http://10.0.0.2:8080", fieldCurrentSessionID: "sess-2"}, done: false},
			{done: true},
		},
		stopCounter: &stopCount,
	}
	api := &mockFirestoreClientAPI{
		iterBusyFn: func(context.Context) firestoreDocIter { return iter },
	}
	docs, err := newFirestoreClient(api).ListBusy(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []runnerDoc{
		{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080", CurrentSessionID: "sess-1"},
		{RunnerID: "r2", PrivateURL: "http://10.0.0.2:8080", CurrentSessionID: "sess-2"},
	}
	if !reflect.DeepEqual(docs, want) {
		t.Errorf("docs = %+v, want %+v", docs, want)
	}
	if stopCount != 1 {
		t.Errorf("Stop called %d times, want 1", stopCount)
	}
}

// TestFirestoreClient_ListBusy_Empty は iterator が最初から done を返すケースで空 slice が返ることを検証する。
func TestFirestoreClient_ListBusy_Empty(t *testing.T) {
	t.Parallel()
	iter := &mockFirestoreDocIter{results: []nextResult{{done: true}}}
	api := &mockFirestoreClientAPI{
		iterBusyFn: func(context.Context) firestoreDocIter { return iter },
	}
	docs, err := newFirestoreClient(api).ListBusy(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(docs) != 0 {
		t.Errorf("docs = %+v, want empty", docs)
	}
}

// TestFirestoreClient_ListBusy_IterError は iterator エラーが伝播し Stop も呼ばれることを検証する。
func TestFirestoreClient_ListBusy_IterError(t *testing.T) {
	t.Parallel()
	stopCount := 0
	want := errors.New("iter boom")
	iter := &mockFirestoreDocIter{
		results: []nextResult{
			{id: "r1", data: map[string]any{fieldPrivateURL: "http://10.0.0.1:8080"}, done: false},
			{err: want},
		},
		stopCounter: &stopCount,
	}
	api := &mockFirestoreClientAPI{
		iterBusyFn: func(context.Context) firestoreDocIter { return iter },
	}
	_, err := newFirestoreClient(api).ListBusy(context.Background())
	if !errors.Is(err, want) {
		t.Errorf("expected %v, got %v", want, err)
	}
	if stopCount != 1 {
		t.Errorf("Stop called %d times, want 1", stopCount)
	}
}

// TestFirestoreClient_FindBySession_Exists は FindBySession が data を runnerDoc に変換して返すことを検証する。
func TestFirestoreClient_FindBySession_Exists(t *testing.T) {
	t.Parallel()
	api := &mockFirestoreClientAPI{
		queryBySessionFn: func(_ context.Context, sessionID string) (string, map[string]any, bool, error) {
			if sessionID != "sess-1" {
				t.Errorf("sessionID = %q", sessionID)
			}
			return "r1", map[string]any{fieldPrivateURL: "http://10.0.0.1:8080", fieldCurrentSessionID: "sess-1"}, true, nil
		},
	}
	doc, err := newFirestoreClient(api).FindBySession(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := &runnerDoc{RunnerID: "r1", PrivateURL: "http://10.0.0.1:8080", CurrentSessionID: "sess-1"}
	if !reflect.DeepEqual(doc, want) {
		t.Errorf("doc = %+v, want %+v", doc, want)
	}
}

// TestFirestoreClient_FindBySession_NotFound は FindBySession が exists=false のとき nil, nil を返すことを検証する。
func TestFirestoreClient_FindBySession_NotFound(t *testing.T) {
	t.Parallel()
	api := &mockFirestoreClientAPI{
		queryBySessionFn: func(context.Context, string) (string, map[string]any, bool, error) {
			return "", nil, false, nil
		},
	}
	doc, err := newFirestoreClient(api).FindBySession(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if doc != nil {
		t.Errorf("doc = %+v, want nil", doc)
	}
}

// TestFirestoreClient_FindBySession_Error は FindBySession エラーが伝播することを検証する。
func TestFirestoreClient_FindBySession_Error(t *testing.T) {
	t.Parallel()
	want := errors.New("find boom")
	api := &mockFirestoreClientAPI{
		queryBySessionFn: func(context.Context, string) (string, map[string]any, bool, error) {
			return "", nil, false, want
		},
	}
	_, err := newFirestoreClient(api).FindBySession(context.Background(), "sess-1")
	if !errors.Is(err, want) {
		t.Errorf("expected %v, got %v", want, err)
	}
}

// TestFirestoreClient_AssignSession_Success はトランザクションが idle doc を得て Update するケースを検証する。
func TestFirestoreClient_AssignSession_Success(t *testing.T) {
	t.Parallel()
	updateCalled := false
	tx := &mockFirestoreTx{
		getFn: func(docID string) (map[string]any, bool, error) {
			if docID != "r1" {
				t.Errorf("docID = %q", docID)
			}
			return map[string]any{fieldCurrentSessionID: nil}, true, nil
		},
		updateFn: func(docID, field string, value any) error {
			updateCalled = true
			if docID != "r1" || field != fieldCurrentSessionID || value != "sess-1" {
				t.Errorf("Update args = (%q, %q, %v)", docID, field, value)
			}
			return nil
		},
	}
	api := &mockFirestoreClientAPI{
		runTxFn: func(_ context.Context, fn func(firestoreTx) error) error {
			return fn(tx)
		},
	}
	if err := newFirestoreClient(api).AssignSession(context.Background(), "r1", "sess-1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !updateCalled {
		t.Error("Update was not called")
	}
}

// TestFirestoreClient_AssignSession_NotFound は tx.Get が exists=false を返す場合に ErrConditionFailed を返すことを検証する。
func TestFirestoreClient_AssignSession_NotFound(t *testing.T) {
	t.Parallel()
	tx := &mockFirestoreTx{
		getFn: func(string) (map[string]any, bool, error) {
			return nil, false, nil
		},
		updateFn: func(string, string, any) error {
			t.Fatal("Update should not be called")
			return nil
		},
	}
	api := &mockFirestoreClientAPI{
		runTxFn: func(_ context.Context, fn func(firestoreTx) error) error {
			return fn(tx)
		},
	}
	err := newFirestoreClient(api).AssignSession(context.Background(), "r1", "sess-1")
	if !errors.Is(err, ErrConditionFailed) {
		t.Errorf("expected ErrConditionFailed, got %v", err)
	}
}

// TestFirestoreClient_AssignSession_AlreadyBusy は既に session が入っている doc に対して ErrConditionFailed を返すことを検証する。
func TestFirestoreClient_AssignSession_AlreadyBusy(t *testing.T) {
	t.Parallel()
	tx := &mockFirestoreTx{
		getFn: func(string) (map[string]any, bool, error) {
			return map[string]any{fieldCurrentSessionID: "other-sess"}, true, nil
		},
		updateFn: func(string, string, any) error {
			t.Fatal("Update should not be called")
			return nil
		},
	}
	api := &mockFirestoreClientAPI{
		runTxFn: func(_ context.Context, fn func(firestoreTx) error) error {
			return fn(tx)
		},
	}
	err := newFirestoreClient(api).AssignSession(context.Background(), "r1", "sess-1")
	if !errors.Is(err, ErrConditionFailed) {
		t.Errorf("expected ErrConditionFailed, got %v", err)
	}
}

// TestFirestoreClient_AssignSession_MissingSessionField は field が data に無いケースを ErrConditionFailed で扱うことを検証する。
func TestFirestoreClient_AssignSession_MissingSessionField(t *testing.T) {
	t.Parallel()
	tx := &mockFirestoreTx{
		getFn: func(string) (map[string]any, bool, error) {
			return map[string]any{fieldPrivateURL: "http://10.0.0.1:8080"}, true, nil
		},
		updateFn: func(string, string, any) error {
			t.Fatal("Update should not be called")
			return nil
		},
	}
	api := &mockFirestoreClientAPI{
		runTxFn: func(_ context.Context, fn func(firestoreTx) error) error {
			return fn(tx)
		},
	}
	err := newFirestoreClient(api).AssignSession(context.Background(), "r1", "sess-1")
	if !errors.Is(err, ErrConditionFailed) {
		t.Errorf("expected ErrConditionFailed, got %v", err)
	}
}

// TestFirestoreClient_AssignSession_TxGetError は tx.Get のエラーが伝播することを検証する。
func TestFirestoreClient_AssignSession_TxGetError(t *testing.T) {
	t.Parallel()
	want := errors.New("tx get boom")
	tx := &mockFirestoreTx{
		getFn: func(string) (map[string]any, bool, error) {
			return nil, false, want
		},
	}
	api := &mockFirestoreClientAPI{
		runTxFn: func(_ context.Context, fn func(firestoreTx) error) error {
			return fn(tx)
		},
	}
	err := newFirestoreClient(api).AssignSession(context.Background(), "r1", "sess-1")
	if !errors.Is(err, want) {
		t.Errorf("expected %v, got %v", want, err)
	}
}

// TestFirestoreClient_AssignSession_TxUpdateError は tx.Update のエラーが伝播することを検証する。
func TestFirestoreClient_AssignSession_TxUpdateError(t *testing.T) {
	t.Parallel()
	want := errors.New("tx update boom")
	tx := &mockFirestoreTx{
		getFn: func(string) (map[string]any, bool, error) {
			return map[string]any{fieldCurrentSessionID: nil}, true, nil
		},
		updateFn: func(string, string, any) error {
			return want
		},
	}
	api := &mockFirestoreClientAPI{
		runTxFn: func(_ context.Context, fn func(firestoreTx) error) error {
			return fn(tx)
		},
	}
	err := newFirestoreClient(api).AssignSession(context.Background(), "r1", "sess-1")
	if !errors.Is(err, want) {
		t.Errorf("expected %v, got %v", want, err)
	}
}

// TestFirestoreClient_AssignSession_RunTxError は RunTx 自体が返すエラーがそのまま伝播することを検証する。
func TestFirestoreClient_AssignSession_RunTxError(t *testing.T) {
	t.Parallel()
	want := errors.New("run tx boom")
	api := &mockFirestoreClientAPI{
		runTxFn: func(context.Context, func(firestoreTx) error) error {
			return want
		},
	}
	err := newFirestoreClient(api).AssignSession(context.Background(), "r1", "sess-1")
	if !errors.Is(err, want) {
		t.Errorf("expected %v, got %v", want, err)
	}
}
