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
	return newFirestoreRepositoryWithDB(&firestoreClient{client: client}), nil
}

// firestoreClient は firestoreDB を Firestore SDK で実装するアダプタ。
// SDK 型が具象のため unit test では触らず、integration test (emulator 実接続) で検証する。
type firestoreClient struct {
	client *firestore.Client
}

func (c *firestoreClient) Create(ctx context.Context, docID, privateURL string) error {
	_, err := c.client.Collection(firestoreCollection).Doc(docID).Create(ctx, map[string]any{
		fieldPrivateURL:       privateURL,
		fieldCurrentSessionID: nil,
	})
	if err != nil {
		if status.Code(err) == codes.AlreadyExists {
			return ErrConflict
		}
		return fmt.Errorf("firestore create: %w", err)
	}
	return nil
}

func (c *firestoreClient) Get(ctx context.Context, docID string) (*runnerDoc, error) {
	snap, err := c.client.Collection(firestoreCollection).Doc(docID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, fmt.Errorf("firestore get: %w", err)
	}
	return snapshotToDoc(docID, snap.Data()), nil
}

func (c *firestoreClient) Delete(ctx context.Context, docID string) error {
	if _, err := c.client.Collection(firestoreCollection).Doc(docID).Delete(ctx); err != nil {
		return fmt.Errorf("firestore delete: %w", err)
	}
	return nil
}

func (c *firestoreClient) QueryIdle(ctx context.Context, startAt string) (*runnerDoc, error) {
	q := c.client.Collection(firestoreCollection).
		Where(fieldCurrentSessionID, "==", nil).
		OrderBy(firestore.DocumentID, firestore.Asc)
	if startAt != "" {
		q = q.StartAt(startAt)
	}
	iter := q.Limit(1).Documents(ctx)
	defer iter.Stop()
	snap, err := iter.Next()
	if errors.Is(err, iterator.Done) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("firestore query idle: %w", err)
	}
	return snapshotToDoc(snap.Ref.ID, snap.Data()), nil
}

func (c *firestoreClient) ListBusy(ctx context.Context) ([]runnerDoc, error) {
	iter := c.client.Collection(firestoreCollection).
		Where(fieldCurrentSessionID, "!=", nil).
		Documents(ctx)
	defer iter.Stop()

	var docs []runnerDoc
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			return docs, nil
		}
		if err != nil {
			return nil, fmt.Errorf("firestore list busy: %w", err)
		}
		docs = append(docs, *snapshotToDoc(snap.Ref.ID, snap.Data()))
	}
}

func (c *firestoreClient) FindBySession(ctx context.Context, sessionID string) (*runnerDoc, error) {
	iter := c.client.Collection(firestoreCollection).
		Where(fieldCurrentSessionID, "==", sessionID).
		Limit(1).
		Documents(ctx)
	defer iter.Stop()
	snap, err := iter.Next()
	if errors.Is(err, iterator.Done) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("firestore find by session: %w", err)
	}
	return snapshotToDoc(snap.Ref.ID, snap.Data()), nil
}

func (c *firestoreClient) AssignSession(ctx context.Context, docID, sessionID string) error {
	ref := c.client.Collection(firestoreCollection).Doc(docID)
	err := c.client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return ErrConditionFailed
			}
			return err
		}
		if v, ok := snap.Data()[fieldCurrentSessionID]; !ok || v != nil {
			return ErrConditionFailed
		}
		return tx.Update(ref, []firestore.Update{{Path: fieldCurrentSessionID, Value: sessionID}})
	})
	if err != nil {
		if errors.Is(err, ErrConditionFailed) {
			return ErrConditionFailed
		}
		return fmt.Errorf("firestore assign session: %w", err)
	}
	return nil
}
