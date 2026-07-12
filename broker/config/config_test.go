// Package config は NewRepositoryFromEnv の env dispatch を検証する。
package config

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
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

// TestNewRepositoryFromEnv_UnsupportedStore は BUNSHIN_STORE の値が未対応時にエラーを返すことを検証する。
func TestNewRepositoryFromEnv_UnsupportedStore(t *testing.T) {
	t.Setenv("BUNSHIN_STORE", "cassandra")

	_, err := NewRepositoryFromEnv(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "cassandra") {
		t.Errorf("error = %q, want to mention unsupported store", err.Error())
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
