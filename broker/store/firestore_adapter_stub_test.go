//go:build firestore_stub

package store

import (
	"context"
	"testing"
)

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
