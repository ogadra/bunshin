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

// minRunnerID は runnerId の辞書順最小値。runnerId は 32 hex なので全 item がこれ以上になり、
// wrap query の開始位置として partition 先頭を表す。
const minRunnerID = "00000000000000000000000000000000"

// DynamoRepository は DynamoDB を使った Repository の実装。
type DynamoRepository struct {
	client    DynamoDBAPI
	tableName string
	randHexFn func() string
	marshalFn func(in interface{}) (map[string]types.AttributeValue, error)
}

// NewDynamoRepository は DynamoRepository を生成する。
func NewDynamoRepository(client DynamoDBAPI, tableName string) *DynamoRepository {
	return &DynamoRepository{
		client:    client,
		tableName: tableName,
		randHexFn: defaultRandHexFn,
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
// acquireQueryLimit に満たなければ partition 先頭 (minRunnerID) から不足分を補って候補を埋める。
// 候補を条件付き更新で idle→busy に遷移させ、全候補が条件失敗なら乱数を作り直して再試行する。
// runnerId は crypto/rand hex で keyspace に一様分布するため、ランダム開始点の successor 自体が
// idle 集合上で一様になり、最初に試す候補も分散する。よって候補内の shuffle は不要。
// idle 総数が acquireQueryLimit 未満のときは 2 クエリの結果が重複しうるため seen set で除く。
// tried set により走査済み候補を除外することで、stale index に対しても有限時間で ErrNoIdleRunner に収束する。
func (r *DynamoRepository) AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error) {
	tried := map[string]struct{}{}
	for {
		candidates, err := r.queryIdleFrom(ctx, r.randHexFn(), acquireQueryLimit)
		if err != nil {
			return nil, err
		}
		if len(candidates) < acquireQueryLimit {
			head, err := r.queryIdleFrom(ctx, minRunnerID, acquireQueryLimit-len(candidates))
			if err != nil {
				return nil, err
			}
			candidates = append(candidates, head...)
		}

		seen := make(map[string]struct{}, len(candidates))
		fresh := candidates[:0]
		for _, c := range candidates {
			if _, dup := seen[c.RunnerID]; dup {
				continue
			}
			seen[c.RunnerID] = struct{}{}
			if _, done := tried[c.RunnerID]; done {
				continue
			}
			fresh = append(fresh, c)
		}
		if len(fresh) == 0 {
			return nil, ErrNoIdleRunner
		}

		for i := range fresh {
			runner := &fresh[i]
			err := r.assignSession(ctx, runner.RunnerID, sessionID)
			if err == nil {
				runner.State = ""
				runner.CurrentSessionID = sessionID
				return runner, nil
			}
			if !errors.Is(err, ErrConditionFailed) {
				return nil, err
			}
			tried[runner.RunnerID] = struct{}{}
		}
	}
}

// queryIdleFrom は state-index を state = "idle" かつ runnerId >= startKey で query し、
// 辞書順に最大 limit 件を返す。partition 先頭から走査する場合は minRunnerID を渡す。
func (r *DynamoRepository) queryIdleFrom(ctx context.Context, startKey string, limit int) ([]model.Runner, error) {
	out, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:                aws.String(r.tableName),
		IndexName:                aws.String("state-index"),
		KeyConditionExpression:   aws.String("#s = :s AND runnerId >= :r"),
		ExpressionAttributeNames: map[string]string{"#s": "state"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":s": &types.AttributeValueMemberS{Value: string(model.StateIdle)},
			":r": &types.AttributeValueMemberS{Value: startKey},
		},
		Limit: aws.Int32(int32(limit)),
	})
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
