// Package store は Runner の永続化層を提供する。
package store

import (
	"context"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"math/rand/v2"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/ogadra/bunshin/broker/model"
)

// acquireQueryLimit は AcquireIdle の 1 query あたりの候補件数。
// 1 item は数百 byte のため RCU コストは Limit 1 と同等 (4KB 未満 = 0.5 RCU) で、
// stale item が混ざったときに再クエリせず手元の候補で試行を続けられる。
const acquireQueryLimit = 5

// DynamoRepository は DynamoDB を使った Repository の実装。
type DynamoRepository struct {
	client    DynamoDBAPI
	tableName string
	randHexFn func() string
	shuffleFn func(n int, swap func(i, j int))
	marshalFn func(in interface{}) (map[string]types.AttributeValue, error)
}

// NewDynamoRepository は DynamoRepository を生成する。
func NewDynamoRepository(client DynamoDBAPI, tableName string) *DynamoRepository {
	return &DynamoRepository{
		client:    client,
		tableName: tableName,
		randHexFn: defaultRandHexFn,
		shuffleFn: rand.Shuffle,
		marshalFn: attributevalue.MarshalMap,
	}
}

// defaultRandHexFn は AcquireIdle の走査開始位置に使う 32 hex の乱数を返す。
// 均等分布があれば足り暗号強度は不要のため math/rand/v2 を使う。
func defaultRandHexFn() string {
	var b [16]byte
	binary.LittleEndian.PutUint64(b[:8], rand.Uint64())
	binary.LittleEndian.PutUint64(b[8:], rand.Uint64())
	return hex.EncodeToString(b[:])
}

// Register は runner を idle 状態で登録する。attribute_not_exists で冪等性を確保する。
// 同一 runnerID で異なる privateURL が登録済みの場合は ErrConflict を返す。
func (r *DynamoRepository) Register(ctx context.Context, runnerID, privateURL string) error {
	if privateURL == "" {
		return fmt.Errorf("privateURL must not be empty")
	}

	item, err := r.marshalFn(model.Runner{
		RunnerID:   runnerID,
		State:      model.StateIdle,
		PrivateURL: privateURL,
	})
	if err != nil {
		return fmt.Errorf("marshal runner: %w", err)
	}

	_, err = r.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           &r.tableName,
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(runnerId)"),
	})
	if err != nil {
		var condErr *types.ConditionalCheckFailedException
		if isConditionalCheckFailed(err, &condErr) {
			existing, findErr := r.FindByID(ctx, runnerID)
			if findErr != nil {
				return fmt.Errorf("find existing runner: %w", findErr)
			}
			if existing.PrivateURL != privateURL {
				return ErrConflict
			}
			return nil
		}
		return fmt.Errorf("put item: %w", err)
	}
	return nil
}

// AcquireIdle は idle runner を 1 台確保し session を紐づける。
// state-index (hash=state, range=runnerId) をランダムな runnerId から前方走査し、
// 空なら partition 先頭から wrap query する。候補を shuffle しながら条件付き更新を試み、
// 全候補が条件失敗なら乱数を作り直して再試行する。
// tried set により走査済み候補を除外することで、stale index に対しても有限時間で ErrNoIdleRunner に収束する。
func (r *DynamoRepository) AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error) {
	tried := map[string]struct{}{}
	for {
		candidates, err := r.queryIdleFrom(ctx, r.randHexFn())
		if err != nil {
			return nil, err
		}
		if len(candidates) == 0 {
			candidates, err = r.queryIdleFrom(ctx, "")
			if err != nil {
				return nil, err
			}
		}
		if len(candidates) == 0 {
			return nil, ErrNoIdleRunner
		}

		fresh := candidates[:0]
		for _, c := range candidates {
			if _, seen := tried[c.RunnerID]; !seen {
				fresh = append(fresh, c)
			}
		}
		if len(fresh) == 0 {
			return nil, ErrNoIdleRunner
		}

		r.shuffleFn(len(fresh), func(i, j int) {
			fresh[i], fresh[j] = fresh[j], fresh[i]
		})
		for i := range fresh {
			runner := &fresh[i]
			tried[runner.RunnerID] = struct{}{}
			err := r.assignSession(ctx, runner.RunnerID, sessionID)
			if err == nil {
				runner.State = ""
				runner.CurrentSessionID = sessionID
				return runner, nil
			}
			if !errors.Is(err, ErrConditionFailed) {
				return nil, err
			}
		}
	}
}

// queryIdleFrom は state-index を state = "idle" で query する。
// startKey が空文字列なら partition 先頭から、そうでなければ runnerId >= startKey から辞書順で走査する。
func (r *DynamoRepository) queryIdleFrom(ctx context.Context, startKey string) ([]model.Runner, error) {
	input := &dynamodb.QueryInput{
		TableName:                aws.String(r.tableName),
		IndexName:                aws.String("state-index"),
		ExpressionAttributeNames: map[string]string{"#s": "state"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":s": &types.AttributeValueMemberS{Value: string(model.StateIdle)},
		},
		Limit: aws.Int32(acquireQueryLimit),
	}
	if startKey == "" {
		input.KeyConditionExpression = aws.String("#s = :s")
	} else {
		input.KeyConditionExpression = aws.String("#s = :s AND runnerId >= :r")
		input.ExpressionAttributeValues[":r"] = &types.AttributeValueMemberS{Value: startKey}
	}
	out, err := r.client.Query(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("query state-index: %w", err)
	}
	runners := make([]model.Runner, 0, len(out.Items))
	for _, item := range out.Items {
		var runner model.Runner
		if err := attributevalue.UnmarshalMap(item, &runner); err != nil {
			return nil, fmt.Errorf("unmarshal runner: %w", err)
		}
		runners = append(runners, runner)
	}
	return runners, nil
}

// assignSession は runner を idle から busy に遷移させ session を紐づける。
// state = StateIdle が満たされるときのみ成功する。遷移後は state 属性を除去し
// state-index の idle partition から外す。busy 一覧の経路は後続で追加する。
func (r *DynamoRepository) assignSession(ctx context.Context, runnerID, sessionID string) error {
	_, err := r.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: &r.tableName,
		Key: map[string]types.AttributeValue{
			"runnerId": &types.AttributeValueMemberS{Value: runnerID},
		},
		UpdateExpression:         aws.String("SET currentSessionId = :sid REMOVE #s"),
		ConditionExpression:      aws.String("#s = :idle"),
		ExpressionAttributeNames: map[string]string{"#s": "state"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":sid":  &types.AttributeValueMemberS{Value: sessionID},
			":idle": &types.AttributeValueMemberS{Value: string(model.StateIdle)},
		},
	})
	if err != nil {
		var condErr *types.ConditionalCheckFailedException
		if isConditionalCheckFailed(err, &condErr) {
			return ErrConditionFailed
		}
		return fmt.Errorf("update item: %w", err)
	}
	return nil
}

// FindBySessionID は session ID から runner を検索する。
func (r *DynamoRepository) FindBySessionID(ctx context.Context, sessionID string) (*model.Runner, error) {
	out, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              &r.tableName,
		IndexName:              aws.String("session-index"),
		KeyConditionExpression: aws.String("currentSessionId = :sid"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":sid": &types.AttributeValueMemberS{Value: sessionID},
		},
		Limit: aws.Int32(1),
	})
	if err != nil {
		return nil, fmt.Errorf("query session-index: %w", err)
	}
	if len(out.Items) == 0 {
		return nil, ErrNotFound
	}
	var runner model.Runner
	if err := attributevalue.UnmarshalMap(out.Items[0], &runner); err != nil {
		return nil, fmt.Errorf("unmarshal runner: %w", err)
	}
	return &runner, nil
}

// FindByID は runner ID から runner を検索する。
func (r *DynamoRepository) FindByID(ctx context.Context, runnerID string) (*model.Runner, error) {
	out, err := r.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &r.tableName,
		Key: map[string]types.AttributeValue{
			"runnerId": &types.AttributeValueMemberS{Value: runnerID},
		},
		ConsistentRead: aws.Bool(true),
	})
	if err != nil {
		return nil, fmt.Errorf("get item: %w", err)
	}
	if out.Item == nil {
		return nil, ErrNotFound
	}
	var runner model.Runner
	if err := attributevalue.UnmarshalMap(out.Item, &runner); err != nil {
		return nil, fmt.Errorf("unmarshal runner: %w", err)
	}
	return &runner, nil
}

// Delete は runner レコードを削除する。条件なしで冪等。
func (r *DynamoRepository) Delete(ctx context.Context, runnerID string) error {
	_, err := r.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: &r.tableName,
		Key: map[string]types.AttributeValue{
			"runnerId": &types.AttributeValueMemberS{Value: runnerID},
		},
	})
	if err != nil {
		return fmt.Errorf("delete item: %w", err)
	}
	return nil
}

// isConditionalCheckFailed は err が ConditionalCheckFailedException かどうかを判定するヘルパー。
func isConditionalCheckFailed(err error, target **types.ConditionalCheckFailedException) bool {
	var condErr *types.ConditionalCheckFailedException
	if errors.As(err, &condErr) {
		*target = condErr
		return true
	}
	return false
}
