// Package config は NewRepositoryFromEnv の env dispatch を検証する。
package config

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/ogadra/bunshin/broker/store"
)

// setDynamoEnv は dynamodb 経路で必要な env をまとめて設定する。
func setDynamoEnv(t *testing.T) {
	t.Helper()
	t.Setenv("BUNSHIN_STORE", "dynamodb")
	t.Setenv("DYNAMODB_ENDPOINT", "http://localhost:18000")
	t.Setenv("AWS_REGION", "ap-northeast-1")
	t.Setenv("AWS_ACCESS_KEY_ID", "localdev")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "localdev")
}

// saveLoadAWSConfig は loadAWSConfig 変数を退避し、テスト終了時に復元する。
func saveLoadAWSConfig(t *testing.T) {
	t.Helper()
	orig := loadAWSConfig
	t.Cleanup(func() { loadAWSConfig = orig })
}

// TestNewRepositoryFromEnv_DynamoSuccess は BUNSHIN_STORE=dynamodb で Repository が返ることを検証する。
func TestNewRepositoryFromEnv_DynamoSuccess(t *testing.T) {
	setDynamoEnv(t)

	repo, err := NewRepositoryFromEnv(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo == nil {
		t.Fatal("expected non-nil Repository")
	}
}

// TestNewRepositoryFromEnv_MissingStore は BUNSHIN_STORE 未設定時にエラーを返すことを検証する。
func TestNewRepositoryFromEnv_MissingStore(t *testing.T) {
	t.Setenv("BUNSHIN_STORE", "")

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "BUNSHIN_STORE") {
		t.Errorf("error = %q, want to contain BUNSHIN_STORE", err.Error())
	}
}

// TestNewRepositoryFromEnv_UnsupportedStore は BUNSHIN_STORE の値が未対応時に
// 完全一致判定で fail-fast することを検証する。空白付き・大文字違いも
// dynamodb には fold されない。
func TestNewRepositoryFromEnv_UnsupportedStore(t *testing.T) {
	tests := []struct {
		name  string
		store string
	}{
		{"other engine", "cassandra"},
		{"with surrounding spaces", " dynamodb "},
		{"different case", "DynamoDB"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("BUNSHIN_STORE", tt.store)

			_, err := NewRepositoryFromEnv(context.Background())
			if err == nil {
				t.Fatal("expected error")
			}
			if !strings.Contains(err.Error(), "unsupported BUNSHIN_STORE") {
				t.Errorf("error = %q, want unsupported BUNSHIN_STORE", err.Error())
			}
			if !strings.Contains(err.Error(), tt.store) {
				t.Errorf("error = %q, want to include %q", err.Error(), tt.store)
			}
		})
	}
}

// TestNewRepositoryFromEnv_MissingRegion は BUNSHIN_STORE=dynamodb で AWS_REGION 未設定時にエラーを返すことを検証する。
func TestNewRepositoryFromEnv_MissingRegion(t *testing.T) {
	t.Setenv("BUNSHIN_STORE", "dynamodb")
	t.Setenv("AWS_REGION", "")

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "AWS_REGION") {
		t.Errorf("error = %q, want to contain AWS_REGION", err.Error())
	}
}

// TestNewRepositoryFromEnv_WithoutStaticCredentials は静的クレデンシャルなしでも Repository が返ることを検証する。
func TestNewRepositoryFromEnv_WithoutStaticCredentials(t *testing.T) {
	setDynamoEnv(t)
	t.Setenv("AWS_ACCESS_KEY_ID", "")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "")

	repo, err := NewRepositoryFromEnv(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo == nil {
		t.Fatal("expected non-nil Repository")
	}
}

// TestNewRepositoryFromEnv_WithoutEndpoint は DYNAMODB_ENDPOINT なしでも Repository が返ることを検証する。
func TestNewRepositoryFromEnv_WithoutEndpoint(t *testing.T) {
	setDynamoEnv(t)
	t.Setenv("DYNAMODB_ENDPOINT", "")

	repo, err := NewRepositoryFromEnv(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo == nil {
		t.Fatal("expected non-nil Repository")
	}
}

// TestNewRepositoryFromEnv_PartialCredentials は片側のクレデンシャルのみ設定時にエラーを返すことを検証する。
func TestNewRepositoryFromEnv_PartialCredentials(t *testing.T) {
	setDynamoEnv(t)
	t.Setenv("AWS_ACCESS_KEY_ID", "localdev")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "")

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "AWS_ACCESS_KEY_ID") || !strings.Contains(err.Error(), "AWS_SECRET_ACCESS_KEY") {
		t.Errorf("error = %q, want to mention both credential keys", err.Error())
	}
}

// TestNewRepositoryFromEnv_LoadConfigError は AWS config ロードが失敗した場合にエラーを返すことを検証する。
func TestNewRepositoryFromEnv_LoadConfigError(t *testing.T) {
	setDynamoEnv(t)
	saveLoadAWSConfig(t)

	loadAWSConfig = func(_ context.Context, _ ...func(*awsconfig.LoadOptions) error) (aws.Config, error) {
		return aws.Config{}, errors.New("config load failed")
	}

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "load aws config") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "load aws config")
	}
}

// setFirestoreEnv は firestore 経路で必要な env をまとめて設定する。
func setFirestoreEnv(t *testing.T) {
	t.Helper()
	t.Setenv("BUNSHIN_STORE", "firestore")
	t.Setenv("GOOGLE_CLOUD_PROJECT", "test-project")
	t.Setenv("FIRESTORE_DATABASE", "test-db")
}

// saveNewFirestoreRepositoryFn は NewFirestoreRepositoryFn 変数を退避し、テスト終了時に復元する。
func saveNewFirestoreRepositoryFn(t *testing.T) {
	t.Helper()
	orig := NewFirestoreRepositoryFn
	t.Cleanup(func() { NewFirestoreRepositoryFn = orig })
}

// fakeFirestoreRepo は firestore 経路の test で NewFirestoreRepositoryFn を差し替えるためのダミー Repository。
type fakeFirestoreRepo struct{ store.Repository }

// TestNewRepositoryFromEnv_FirestoreSuccess は firestore 経路が env と factory を通って Repository を返すことを検証する。
func TestNewRepositoryFromEnv_FirestoreSuccess(t *testing.T) {
	setFirestoreEnv(t)
	saveNewFirestoreRepositoryFn(t)

	called := false
	NewFirestoreRepositoryFn = func(_ context.Context, projectID, databaseID string) (store.Repository, error) {
		called = true
		if projectID != "test-project" {
			t.Errorf("projectID = %q, want test-project", projectID)
		}
		if databaseID != "test-db" {
			t.Errorf("databaseID = %q, want test-db", databaseID)
		}
		return fakeFirestoreRepo{}, nil
	}

	repo, err := NewRepositoryFromEnv(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo == nil {
		t.Fatal("expected non-nil Repository")
	}
	if !called {
		t.Error("NewFirestoreRepositoryFn was not called")
	}
}

// TestNewRepositoryFromEnv_FirestoreFactoryError は firestore factory がエラーを返すケースを検証する。
func TestNewRepositoryFromEnv_FirestoreFactoryError(t *testing.T) {
	setFirestoreEnv(t)
	saveNewFirestoreRepositoryFn(t)

	NewFirestoreRepositoryFn = func(context.Context, string, string) (store.Repository, error) {
		return nil, errors.New("factory failed")
	}

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "factory failed") {
		t.Errorf("error = %q, want to contain factory error", err.Error())
	}
}

// TestNewRepositoryFromEnv_FirestoreMissingProject は BUNSHIN_STORE=firestore で GOOGLE_CLOUD_PROJECT 未設定時にエラーを返すことを検証する。
func TestNewRepositoryFromEnv_FirestoreMissingProject(t *testing.T) {
	setFirestoreEnv(t)
	t.Setenv("GOOGLE_CLOUD_PROJECT", "")

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "GOOGLE_CLOUD_PROJECT") {
		t.Errorf("error = %q, want to contain GOOGLE_CLOUD_PROJECT", err.Error())
	}
}

// TestNewRepositoryFromEnv_FirestoreMissingDatabase は BUNSHIN_STORE=firestore で FIRESTORE_DATABASE 未設定時にエラーを返すことを検証する。
func TestNewRepositoryFromEnv_FirestoreMissingDatabase(t *testing.T) {
	setFirestoreEnv(t)
	t.Setenv("FIRESTORE_DATABASE", "")

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "FIRESTORE_DATABASE") {
		t.Errorf("error = %q, want to contain FIRESTORE_DATABASE", err.Error())
	}
}
