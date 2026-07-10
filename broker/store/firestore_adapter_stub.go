//go:build firestore_stub

// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"errors"
)

// NewFirestoreRepository は firestore_stub build tag 下でのスタブ。
// unit test の coverage 対象から real adapter を除外するため用意している。
// production / integration test では firestore_adapter.go の real 実装が使われる。
func NewFirestoreRepository(_ context.Context, _, _ string) (*FirestoreRepository, error) {
	return nil, errors.New("firestore repository is unavailable in this build")
}
