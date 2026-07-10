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

// errFirestoreDocExists は firestoreDB.Create が既存 doc を検出した内部シグナル。
// Repository が FindByID による conflict / idempotent 判定に分岐するためだけに使う。
var errFirestoreDocExists = errors.New("firestore: doc already exists")

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

// firestoreDB は Firestore の runners コレクションに対する低レベル操作。
// Firestore SDK の型が具象で unit test 用の mock を作れないため、Repository が必要とする操作だけを
// 集約したアダプタ層として interface に切る。
type firestoreDB interface {
	Create(ctx context.Context, docID, privateURL string) error
	Get(ctx context.Context, docID string) (*runnerDoc, error)
	Delete(ctx context.Context, docID string) error
	QueryIdle(ctx context.Context, startAt string) (*runnerDoc, error)
	ListBusy(ctx context.Context) ([]runnerDoc, error)
	FindBySession(ctx context.Context, sessionID string) (*runnerDoc, error)
	AssignSession(ctx context.Context, docID, sessionID string) error
}

// FirestoreRepository は Repository interface の Firestore Native 実装。
type FirestoreRepository struct {
	db        firestoreDB
	randHexFn func() string
}

// newFirestoreRepositoryWithDB は firestoreDB を差し替えられる形で Repository を組み立てる。
// production では NewFirestoreRepository が real adapter を組み合わせて呼び出す。
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

	err := r.db.Create(ctx, runnerID, privateURL)
	if err == nil {
		return nil
	}
	if !errors.Is(err, errFirestoreDocExists) {
		return err
	}

	existing, findErr := r.FindByID(ctx, runnerID)
	if findErr != nil {
		return fmt.Errorf("find existing runner: %w", findErr)
	}
	if existing.PrivateURL != privateURL {
		return ErrConflict
	}
	return nil
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
