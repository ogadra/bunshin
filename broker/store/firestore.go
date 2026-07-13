// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/ogadra/bunshin/broker/model"
)

// maxAcquireRetries は AcquireIdle のリトライ上限。この回数を超えても取れなければ ErrNoIdleRunner に落とす。
// stale document による無限ループ回避と、実際に idle が枯渇した状態のフェイルクローズを兼ねる。
const maxAcquireRetries = 20

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
	Create(ctx context.Context, docID, privateURL string) error
	Get(ctx context.Context, docID string) (*runnerDoc, error)
	Delete(ctx context.Context, docID string) error
	QueryIdle(ctx context.Context, startAt string) (*runnerDoc, error)
	ListBusy(ctx context.Context) ([]runnerDoc, error)
	FindBySession(ctx context.Context, sessionID string) (*runnerDoc, error)
	AssignSession(ctx context.Context, docID, sessionID string) error
}

// firestoreClientAPI は Firestore SDK 呼出を primitive レベルで抽象化する。
// SDK の chain (Collection().Doc().Get()) やイテレータ / トランザクションを testable にするため、
// return は SDK 具象型を露出せず map[string]any / bool / 独自 interface のみを使う。
// production では firestore_adapter.go の SDK 実装、unit test では mock が実装する。
type firestoreClientAPI interface {
	Create(ctx context.Context, docID string, data map[string]any) error
	Get(ctx context.Context, docID string) (data map[string]any, exists bool, err error)
	Delete(ctx context.Context, docID string) error
	QueryIdle(ctx context.Context, startAt string) (id string, data map[string]any, exists bool, err error)
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
	Get(docID string) (data map[string]any, exists bool, err error)
	Update(docID, field string, value any) error
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

func (c *firestoreClient) Create(ctx context.Context, docID, privateURL string) error {
	return c.api.Create(ctx, docID, map[string]any{
		fieldPrivateURL:       privateURL,
		fieldCurrentSessionID: nil,
	})
}

func (c *firestoreClient) Get(ctx context.Context, docID string) (*runnerDoc, error) {
	data, exists, err := c.api.Get(ctx, docID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}
	return snapshotToDoc(docID, data), nil
}

func (c *firestoreClient) Delete(ctx context.Context, docID string) error {
	return c.api.Delete(ctx, docID)
}

func (c *firestoreClient) QueryIdle(ctx context.Context, startAt string) (*runnerDoc, error) {
	id, data, exists, err := c.api.QueryIdle(ctx, startAt)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}
	return snapshotToDoc(id, data), nil
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

func (c *firestoreClient) AssignSession(ctx context.Context, docID, sessionID string) error {
	return c.api.RunTx(ctx, func(tx firestoreTx) error {
		data, exists, err := tx.Get(docID)
		if err != nil {
			return err
		}
		if !exists {
			return ErrConditionFailed
		}
		if v, ok := data[fieldCurrentSessionID]; !ok || v != nil {
			return ErrConditionFailed
		}
		return tx.Update(docID, fieldCurrentSessionID, sessionID)
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

func (r *FirestoreRepository) AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error) {
	for range maxAcquireRetries {
		doc, err := r.findIdleCandidate(ctx)
		if err != nil {
			return nil, err
		}
		if doc == nil {
			return nil, ErrNoIdleRunner
		}
		err = r.db.AssignSession(ctx, doc.RunnerID, sessionID)
		if errors.Is(err, ErrConditionFailed) {
			continue
		}
		if err != nil {
			return nil, err
		}
		return &model.Runner{
			RunnerID:         doc.RunnerID,
			State:            model.StateBusy,
			PrivateURL:       doc.PrivateURL,
			CurrentSessionID: sessionID,
		}, nil
	}
	return nil, ErrNoIdleRunner
}

// findIdleCandidate は idle runner を 1 件返す。
// 乱数開始位置で見つからなければ先頭から wrap query する。両方空なら nil を返す。
func (r *FirestoreRepository) findIdleCandidate(ctx context.Context) (*runnerDoc, error) {
	doc, err := r.db.QueryIdle(ctx, r.randHexFn())
	if err != nil {
		return nil, err
	}
	if doc != nil {
		return doc, nil
	}
	return r.db.QueryIdle(ctx, "")
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
func snapshotToDoc(docID string, data map[string]any) *runnerDoc {
	doc := &runnerDoc{RunnerID: docID}
	if v, ok := data[fieldPrivateURL].(string); ok {
		doc.PrivateURL = v
	}
	if v, ok := data[fieldCurrentSessionID].(string); ok {
		doc.CurrentSessionID = v
	}
	return doc
}
