//go:build !firestore_stub

// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"errors"
	"fmt"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// NewFirestoreRepository は指定した projectID / databaseID の Firestore client を作り Repository を返す。
// 認証は ADC (GKE では Workload Identity で Pod に注入される)。emulator を使う場合は
// FIRESTORE_EMULATOR_HOST を環境変数に設定しておくと SDK が自動的に emulator に接続する。
func NewFirestoreRepository(ctx context.Context, projectID, databaseID string) (*FirestoreRepository, error) {
	client, err := firestore.NewClientWithDatabase(ctx, projectID, databaseID)
	if err != nil {
		return nil, fmt.Errorf("firestore client: %w", err)
	}
	api := &firestoreClientAPIAdapter{client: client}
	return newFirestoreRepositoryWithDB(newFirestoreClient(api)), nil
}

// firestoreClientAPIAdapter は firestoreClientAPI を Firestore SDK で実装する。
// SDK 型が具象で unit test では触らず、integration test (emulator 実接続) で検証する。
type firestoreClientAPIAdapter struct {
	client *firestore.Client
}

func (a *firestoreClientAPIAdapter) Create(ctx context.Context, docID string, data map[string]any) error {
	_, err := a.client.Collection(firestoreCollection).Doc(docID).Create(ctx, data)
	if err != nil {
		if status.Code(err) == codes.AlreadyExists {
			return ErrConflict
		}
		return fmt.Errorf("firestore create: %w", err)
	}
	return nil
}

func (a *firestoreClientAPIAdapter) Get(ctx context.Context, docID string) (map[string]any, bool, error) {
	snap, err := a.client.Collection(firestoreCollection).Doc(docID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, false, nil
		}
		return nil, false, fmt.Errorf("firestore get: %w", err)
	}
	return snap.Data(), true, nil
}

func (a *firestoreClientAPIAdapter) Delete(ctx context.Context, docID string) error {
	if _, err := a.client.Collection(firestoreCollection).Doc(docID).Delete(ctx); err != nil {
		return fmt.Errorf("firestore delete: %w", err)
	}
	return nil
}

func (a *firestoreClientAPIAdapter) QueryIdle(ctx context.Context, startAt string) (string, map[string]any, bool, error) {
	q := a.client.Collection(firestoreCollection).
		Where(fieldCurrentSessionID, "==", nil).
		OrderBy(firestore.DocumentID, firestore.Asc)
	if startAt != "" {
		q = q.StartAt(startAt)
	}
	iter := q.Limit(1).Documents(ctx)
	defer iter.Stop()
	snap, err := iter.Next()
	if errors.Is(err, iterator.Done) {
		return "", nil, false, nil
	}
	if err != nil {
		return "", nil, false, fmt.Errorf("firestore query idle: %w", err)
	}
	return snap.Ref.ID, snap.Data(), true, nil
}

func (a *firestoreClientAPIAdapter) IterBusy(ctx context.Context) firestoreDocIter {
	return &firestoreDocIterAdapter{
		iter: a.client.Collection(firestoreCollection).
			Where(fieldCurrentSessionID, "!=", nil).
			Documents(ctx),
	}
}

func (a *firestoreClientAPIAdapter) QueryBySession(ctx context.Context, sessionID string) (string, map[string]any, bool, error) {
	iter := a.client.Collection(firestoreCollection).
		Where(fieldCurrentSessionID, "==", sessionID).
		Limit(1).
		Documents(ctx)
	defer iter.Stop()
	snap, err := iter.Next()
	if errors.Is(err, iterator.Done) {
		return "", nil, false, nil
	}
	if err != nil {
		return "", nil, false, fmt.Errorf("firestore find by session: %w", err)
	}
	return snap.Ref.ID, snap.Data(), true, nil
}

func (a *firestoreClientAPIAdapter) RunTx(ctx context.Context, fn func(tx firestoreTx) error) error {
	err := a.client.RunTransaction(ctx, func(ctx context.Context, sdkTx *firestore.Transaction) error {
		return fn(&firestoreTxAdapter{client: a.client, tx: sdkTx})
	})
	if err != nil {
		if errors.Is(err, ErrConditionFailed) {
			return ErrConditionFailed
		}
		return fmt.Errorf("firestore run tx: %w", err)
	}
	return nil
}

// firestoreDocIterAdapter は firestoreDocIter を Firestore SDK iterator で実装する。
type firestoreDocIterAdapter struct {
	iter *firestore.DocumentIterator
}

func (a *firestoreDocIterAdapter) Next() (string, map[string]any, bool, error) {
	snap, err := a.iter.Next()
	if errors.Is(err, iterator.Done) {
		return "", nil, true, nil
	}
	if err != nil {
		return "", nil, false, fmt.Errorf("firestore iter next: %w", err)
	}
	return snap.Ref.ID, snap.Data(), false, nil
}

func (a *firestoreDocIterAdapter) Stop() {
	a.iter.Stop()
}

// firestoreTxAdapter は firestoreTx を Firestore SDK transaction で実装する。
type firestoreTxAdapter struct {
	client *firestore.Client
	tx     *firestore.Transaction
}

func (a *firestoreTxAdapter) Get(docID string) (map[string]any, bool, error) {
	snap, err := a.tx.Get(a.client.Collection(firestoreCollection).Doc(docID))
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, false, nil
		}
		return nil, false, fmt.Errorf("firestore tx get: %w", err)
	}
	return snap.Data(), true, nil
}

func (a *firestoreTxAdapter) Update(docID, field string, value any) error {
	ref := a.client.Collection(firestoreCollection).Doc(docID)
	if err := a.tx.Update(ref, []firestore.Update{{Path: field, Value: value}}); err != nil {
		return fmt.Errorf("firestore tx update: %w", err)
	}
	return nil
}
