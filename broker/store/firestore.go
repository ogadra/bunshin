// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/ogadra/bunshin/broker/model"
)

// firestoreCollection は runner document を格納するコレクション名。
const firestoreCollection = "runners"

// firestore document の field 名。DynamoDB 側の属性名と揃える。
const (
	fieldPrivateURL       = "privateUrl"
	fieldCurrentSessionID = "currentSessionId"
)

// runnerDoc は Firestore の runners document の内部表現。
// CurrentSessionID の空文字列は Firestore 上の null (idle) に対応する。
type runnerDoc struct {
	RunnerID         string
	PrivateURL       string
	CurrentSessionID string
}

func (d runnerDoc) toModel() *model.Runner {
	r := &model.Runner{
		RunnerID:         d.RunnerID,
		PrivateURL:       d.PrivateURL,
		CurrentSessionID: d.CurrentSessionID,
	}
	if d.CurrentSessionID == "" {
		r.State = model.StateIdle
	} else {
		r.State = model.StateBusy
	}
	return r
}

// firestoreDB は Firestore の runners コレクションに対する semantic 操作。
// Repository はこの interface に依存し、mock による unit test で全経路をカバーする。
type firestoreDB interface {
	Create(ctx context.Context, runnerID, privateURL string) error
	Get(ctx context.Context, runnerID string) (*runnerDoc, error)
	Delete(ctx context.Context, runnerID string) error
	QueryIdleRange(ctx context.Context, after, upTo string, limit int) ([]runnerDoc, error)
	ListBusy(ctx context.Context) ([]runnerDoc, error)
	FindBySession(ctx context.Context, sessionID string) (*runnerDoc, error)
	AssignSession(ctx context.Context, runnerID, sessionID string) error
}

// firestoreDocSnapshot は Firestore query の 1 doc 分を primitive レベルで表現する。
// firestoreClientAPI から複数 doc を返すために使う。
type firestoreDocSnapshot struct {
	ID   string
	Data map[string]any
}

// firestoreClientAPI は Firestore SDK 呼出を primitive レベルで抽象化する。
// SDK の chain (Collection().Doc().Get()) やイテレータ / トランザクションを testable にするため、
// return は SDK 具象型を露出せず map[string]any / bool / 独自 interface のみを使う。
// production では firestore_adapter.go の SDK 実装、unit test では mock が実装する。
type firestoreClientAPI interface {
	Create(ctx context.Context, runnerID string, data map[string]any) error
	Get(ctx context.Context, runnerID string) (data map[string]any, exists bool, err error)
	Delete(ctx context.Context, runnerID string) error
	QueryIdleRange(ctx context.Context, after, upTo string, limit int) ([]firestoreDocSnapshot, error)
	IterBusy(ctx context.Context) firestoreDocIter
	QueryBySession(ctx context.Context, sessionID string) (id string, data map[string]any, exists bool, err error)
	RunTx(ctx context.Context, fn func(tx firestoreTx) error) error
}

// firestoreDocIter は Firestore query iterator の抽象化。
// SDK の *firestore.DocumentIterator を隠蔽し、mock によるループロジックの unit test を可能にする。
type firestoreDocIter interface {
	Next() (id string, data map[string]any, done bool, err error)
	Stop()
}

// firestoreTx は Firestore transaction 内で使う操作の抽象化。
// SDK の *firestore.Transaction を隠蔽し、mock によるトランザクション orchestration の unit test を可能にする。
type firestoreTx interface {
	Get(runnerID string) (data map[string]any, exists bool, err error)
	Update(runnerID, field string, value any) error
}

// firestoreClient は firestoreDB を firestoreClientAPI 経由で実装する。
// SDK primitive を semantic 操作に集約し、snapshotToDoc / iterator / transaction の
// orchestration ロジックをこの層に置くことで unit test で mock 可能にしている。
type firestoreClient struct {
	api firestoreClientAPI
}

func newFirestoreClient(api firestoreClientAPI) *firestoreClient {
	return &firestoreClient{api: api}
}

func (c *firestoreClient) Create(ctx context.Context, runnerID, privateURL string) error {
	return c.api.Create(ctx, runnerID, map[string]any{
		fieldPrivateURL:       privateURL,
		fieldCurrentSessionID: nil,
	})
}

func (c *firestoreClient) Get(ctx context.Context, runnerID string) (*runnerDoc, error) {
	data, exists, err := c.api.Get(ctx, runnerID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}
	return snapshotToDoc(runnerID, data), nil
}

func (c *firestoreClient) Delete(ctx context.Context, runnerID string) error {
	return c.api.Delete(ctx, runnerID)
}

func (c *firestoreClient) QueryIdleRange(ctx context.Context, after, upTo string, limit int) ([]runnerDoc, error) {
	snaps, err := c.api.QueryIdleRange(ctx, after, upTo, limit)
	if err != nil {
		return nil, err
	}
	docs := make([]runnerDoc, 0, len(snaps))
	for _, s := range snaps {
		docs = append(docs, *snapshotToDoc(s.ID, s.Data))
	}
	return docs, nil
}

func (c *firestoreClient) ListBusy(ctx context.Context) ([]runnerDoc, error) {
	iter := c.api.IterBusy(ctx)
	defer iter.Stop()
	var docs []runnerDoc
	for {
		id, data, done, err := iter.Next()
		if err != nil {
			return nil, err
		}
		if done {
			return docs, nil
		}
		docs = append(docs, *snapshotToDoc(id, data))
	}
}

func (c *firestoreClient) FindBySession(ctx context.Context, sessionID string) (*runnerDoc, error) {
	id, data, exists, err := c.api.QueryBySession(ctx, sessionID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}
	return snapshotToDoc(id, data), nil
}

func (c *firestoreClient) AssignSession(ctx context.Context, runnerID, sessionID string) error {
	return c.api.RunTx(ctx, func(tx firestoreTx) error {
		data, exists, err := tx.Get(runnerID)
		if err != nil {
			return err
		}
		if !exists {
			return ErrConditionFailed
		}
		if v, ok := data[fieldCurrentSessionID]; !ok || v != nil {
			return ErrConditionFailed
		}
		return tx.Update(runnerID, fieldCurrentSessionID, sessionID)
	})
}

// FirestoreRepository は Repository interface の Firestore Native 実装。
type FirestoreRepository struct {
	db        firestoreDB
	randHexFn func() string
}

// newFirestoreRepositoryWithDB は firestoreDB を差し替えられる形で Repository を組み立てる。
// production では NewFirestoreRepository が firestoreClient + real adapter を組み合わせて呼び出す。
func newFirestoreRepositoryWithDB(db firestoreDB) *FirestoreRepository {
	return &FirestoreRepository{
		db:        db,
		randHexFn: defaultRandHexFn,
	}
}

func (r *FirestoreRepository) Register(ctx context.Context, runnerID, privateURL string) error {
	if !runnerIDRe.MatchString(runnerID) {
		return ErrInvalidRunnerID
	}
	if privateURL == "" {
		return fmt.Errorf("privateURL must not be empty")
	}
	return r.db.Create(ctx, runnerID, privateURL)
}

// AcquireIdle は乱数開始位置から (start, ∞) → [∅, start] の 2 segment を acquireQueryLimit 件ずつ
// paginate し、AssignSession で precondition 競合した runner は tried に記録して次候補へ進む。
// 全 segment を辿り切れば idle 枯渇として ErrNoIdleRunner を返す (DynamoDB 側と同構造)。
func (r *FirestoreRepository) AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error) {
	tried := map[string]struct{}{}
	start := r.randHexFn()
	for _, seg := range [][2]string{{start, ""}, {"", start}} {
		after, upTo := seg[0], seg[1]
		for {
			docs, err := r.db.QueryIdleRange(ctx, after, upTo, acquireQueryLimit)
			if err != nil {
				return nil, err
			}
			if len(docs) == 0 {
				break
			}
			runner, err := r.assignFirstIdle(ctx, sessionID, docs, tried)
			if runner != nil || err != nil {
				return runner, err
			}
			after = docs[len(docs)-1].RunnerID
			if len(docs) < acquireQueryLimit {
				break
			}
		}
	}
	return nil, ErrNoIdleRunner
}

func (r *FirestoreRepository) assignFirstIdle(ctx context.Context, sessionID string, candidates []runnerDoc, tried map[string]struct{}) (*model.Runner, error) {
	for _, d := range candidates {
		if _, done := tried[d.RunnerID]; done {
			continue
		}
		err := r.db.AssignSession(ctx, d.RunnerID, sessionID)
		if err == nil {
			return &model.Runner{
				RunnerID:         d.RunnerID,
				State:            model.StateBusy,
				PrivateURL:       d.PrivateURL,
				CurrentSessionID: sessionID,
			}, nil
		}
		if !errors.Is(err, ErrConditionFailed) {
			return nil, err
		}
		tried[d.RunnerID] = struct{}{}
	}
	return nil, nil
}

func (r *FirestoreRepository) ListBusyRunners(ctx context.Context) ([]model.Runner, error) {
	docs, err := r.db.ListBusy(ctx)
	if err != nil {
		return nil, err
	}
	runners := make([]model.Runner, 0, len(docs))
	for _, d := range docs {
		runners = append(runners, *d.toModel())
	}
	return runners, nil
}

func (r *FirestoreRepository) FindBySessionID(ctx context.Context, sessionID string) (*model.Runner, error) {
	doc, err := r.db.FindBySession(ctx, sessionID)
	if err != nil {
		return nil, err
	}
	if doc == nil {
		return nil, ErrNotFound
	}
	return doc.toModel(), nil
}

func (r *FirestoreRepository) FindByID(ctx context.Context, runnerID string) (*model.Runner, error) {
	doc, err := r.db.Get(ctx, runnerID)
	if err != nil {
		return nil, err
	}
	if doc == nil {
		return nil, ErrNotFound
	}
	return doc.toModel(), nil
}

func (r *FirestoreRepository) Delete(ctx context.Context, runnerID string) error {
	return r.db.Delete(ctx, runnerID)
}

// snapshotToDoc は Firestore document snapshot の data と ID から runnerDoc を組み立てる。
// unit test で adapter を経由せずに検証するため、firestore SDK に依存しないここに置く。
func snapshotToDoc(runnerID string, data map[string]any) *runnerDoc {
	doc := &runnerDoc{RunnerID: runnerID}
	if v, ok := data[fieldPrivateURL].(string); ok {
		doc.PrivateURL = v
	}
	if v, ok := data[fieldCurrentSessionID].(string); ok {
		doc.CurrentSessionID = v
	}
	return doc
}
