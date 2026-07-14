// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/ogadra/bunshin/broker/model"
)

var (
	ErrNotFound          = errors.New("runner not found")
	ErrNoIdleRunner      = errors.New("no idle runner available")
	ErrConditionFailed   = errors.New("condition check failed")
	ErrConflict          = errors.New("runner already exists with different attributes")
	ErrInvalidRunnerID   = errors.New("runnerID must be 32 lowercase hex characters")
	ErrInvalidPrivateURL = errors.New("privateURL must not be empty")
)

// AcquireIdle が 1 ページで取得する idle 候補の件数上限。dynamo / firestore 両実装で共有する。
// stale item に当たっても同ページ内の次候補で assign を試せるよう複数取る。
const acquireQueryLimit = 5

type Repository interface {
	Register(ctx context.Context, runnerID, privateURL string) error
	AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error)
	ListBusyRunners(ctx context.Context) ([]model.Runner, error)
	FindBySessionID(ctx context.Context, sessionID string) (*model.Runner, error)
	FindByID(ctx context.Context, runnerID string) (*model.Runner, error)
	Delete(ctx context.Context, runnerID string) error
}

type DynamoDBAPI interface {
	PutItem(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	DeleteItem(ctx context.Context, params *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
	Query(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error)
}
