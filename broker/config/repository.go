// Package config は環境変数を読んで broker の依存を組み立てる composition-root 層。
// os.Getenv とクラウド SDK 初期化を集約し、上位 (main) からは値/結果のみを扱えるようにする。
package config

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/ogadra/bunshin/broker/store"
)

// loadAWSConfig は AWS SDK の設定をロードする関数。テスト時に差し替える。
var loadAWSConfig = awsconfig.LoadDefaultConfig

// NewRepositoryFromEnv は BUNSHIN_STORE を読み対応する Repository を組み立てる。
// dynamodb / firestore 以外の値・未設定は起動失敗させる (default は持たない)。
func NewRepositoryFromEnv(ctx context.Context) (store.Repository, error) {
	switch kind := os.Getenv("BUNSHIN_STORE"); kind {
	case "dynamodb":
		return newDynamoFromEnv(ctx)
	case "firestore":
		return newFirestoreFromEnv(ctx)
	case "":
		return nil, fmt.Errorf("missing required environment variable: BUNSHIN_STORE")
	default:
		return nil, fmt.Errorf("unsupported BUNSHIN_STORE %q (expected dynamodb or firestore)", kind)
	}
}

// NewFirestoreRepositoryFn は Firestore backend factory の test seam。
// 上位パッケージ (broker main_test) の Handler 組み立てテストからも差し替える必要があるため export する。
var NewFirestoreRepositoryFn = func(ctx context.Context, projectID, databaseID string) (store.Repository, error) {
	return store.NewFirestoreRepository(ctx, projectID, databaseID)
}

func newFirestoreFromEnv(ctx context.Context) (store.Repository, error) {
	projectID := os.Getenv("GOOGLE_CLOUD_PROJECT")
	if projectID == "" {
		return nil, fmt.Errorf("missing required environment variable: GOOGLE_CLOUD_PROJECT")
	}
	databaseID := os.Getenv("FIRESTORE_DATABASE")
	if databaseID == "" {
		return nil, fmt.Errorf("missing required environment variable: FIRESTORE_DATABASE")
	}
	return NewFirestoreRepositoryFn(ctx, projectID, databaseID)
}

func newDynamoFromEnv(ctx context.Context) (store.Repository, error) {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		return nil, fmt.Errorf("missing required environment variable: AWS_REGION")
	}

	accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
	secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")
	if (accessKey == "") != (secretKey == "") {
		return nil, fmt.Errorf("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must both be set or both be empty")
	}

	opts := []func(*awsconfig.LoadOptions) error{
		awsconfig.WithRegion(region),
	}
	if accessKey != "" {
		opts = append(opts, awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")))
	}
	cfg, err := loadAWSConfig(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}

	var ddbOpts []func(*dynamodb.Options)
	if endpoint := os.Getenv("DYNAMODB_ENDPOINT"); endpoint != "" {
		ddbOpts = append(ddbOpts, func(o *dynamodb.Options) {
			o.BaseEndpoint = aws.String(endpoint)
		})
	}
	return store.NewDynamoRepository(dynamodb.NewFromConfig(cfg, ddbOpts...), "bunshin-runners"), nil
}
