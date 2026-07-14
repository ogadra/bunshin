//go:build firestore_stub

// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"errors"
)

// firestore_stub build では real adapter が除外されるので factory は常にエラー。
func NewFirestoreRepository(_ context.Context, _, _ string) (*FirestoreRepository, error) {
	return nil, errors.New("firestore repository is unavailable in this build")
}
