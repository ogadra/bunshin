// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/ogadra/bunshin/broker/model"
)

// ErrNotFound は指定された runner が存在しない場合に返される。
var ErrNotFound = errors.New("runner not found")

// ErrNoIdleRunner は idle 状態の runner が存在しない場合に返される。
var ErrNoIdleRunner = errors.New("no idle runner available")

// ErrConditionFailed は条件付き更新が失敗した場合に返される。
var ErrConditionFailed = errors.New("condition check failed")

// ErrConflict は登録済み runner の属性が異なる場合に返される。
var ErrConflict = errors.New("runner already exists with different attributes")

// Repository は Runner の永続化操作を定義するインターフェース。
type Repository interface {
	// Register は runner を idle として登録する。privateURL は runner のプライベート URL。
	Register(ctx context.Context, runnerID, privateURL string) error
	// AcquireIdle は idle runner を 1 台確保し session を紐づける。
	// 走査・リトライは実装内部に閉じており、呼び出し側は再試行不要。
	// idle runner がいない場合は ErrNoIdleRunner を返す。
	AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error)
	// FindBySessionID は session ID から runner を検索する。
	FindBySessionID(ctx context.Context, sessionID string) (*model.Runner, error)
	// FindByID は runner ID から runner を検索する。
	FindByID(ctx context.Context, runnerID string) (*model.Runner, error)
	// Delete は runner レコードを削除する。
	Delete(ctx context.Context, runnerID string) error
}

// DynamoDBAPI は DynamoDB クライアントの narrow interface。
type DynamoDBAPI interface {
	// PutItem は DynamoDB にアイテムを書き込む。
	PutItem(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	// GetItem は DynamoDB からアイテムを取得する。
	GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	// UpdateItem は DynamoDB のアイテムを更新する。
	UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	// DeleteItem は DynamoDB のアイテムを削除する。
	DeleteItem(ctx context.Context, params *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
	// Query は DynamoDB のクエリを実行する。
	Query(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error)
}
