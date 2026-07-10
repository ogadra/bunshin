//go:build firestore_stub

// Package store は firestore_stub build のスタブ実装をテストする。
package store

import (
	"context"
	"testing"
)

// TestNewFirestoreRepository_Stub は firestore_stub build 下で NewFirestoreRepository がエラーを返すことを検証する。
// unit test では real adapter を除外するためスタブが有効になる。
func TestNewFirestoreRepository_Stub(t *testing.T) {
	t.Parallel()
	repo, err := NewFirestoreRepository(context.Background(), "proj", "db")
	if err == nil {
		t.Fatal("expected error from stub NewFirestoreRepository")
	}
	if repo != nil {
		t.Errorf("repo should be nil under stub, got %+v", repo)
	}
}
