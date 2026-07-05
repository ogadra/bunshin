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

// minRunnerID と maxRunnerID は runnerId の辞書順の下限・上限。runnerId は crypto/rand の 32 桁小文字 hex
// なので全 runner がこの閉区間に収まり、AcquireIdle の [R, max]・[min, R] 走査が漏れなく全体を覆う。
const (
	minRunnerID = "00000000000000000000000000000000"
	maxRunnerID = "ffffffffffffffffffffffffffffffff"
)

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
// state-index (hash=state, range=runnerId) を、ランダムな runnerId R を境に
// [R, max] → [min, R] の 2 区間で先頭から走査する。R から始めることで最初の試行先が
// keyspace 上に分散し (runnerId は crypto/rand hex で一様)、head のホットスポットを避ける。
// 各区間を acquireQueryLimit 件ずつ辿り、確保できなければ次区間へ、R まで一周したら枯渇として
// ErrNoIdleRunner を返す。tried set が走査済み候補を除外するので stale index でも有限で収束する。
func (r *DynamoRepository) AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error) {
	tried := map[string]struct{}{}
	start := r.randHexFn()
	for _, seg := range [][2]string{{start, maxRunnerID}, {minRunnerID, start}} {
		runner, err := r.acquireInRange(ctx, sessionID, seg[0], seg[1], nil, tried)
		if runner != nil || err != nil {
			return runner, err
		}
	}
	return nil, ErrNoIdleRunner
}

// acquireInRange は state-index の runnerId ∈ [lo, hi] を acquireQueryLimit 件ずつ走査し、未試行 idle を確保する。
// 1 ページで確保できなければ続き (LastEvaluatedKey) を再帰的に辿り、区間を走査し切ったら (nil, nil) を返す。
func (r *DynamoRepository) acquireInRange(ctx context.Context, sessionID, lo, hi string, exclusiveStart map[string]types.AttributeValue, tried map[string]struct{}) (*model.Runner, error) {
	runners, next, err := r.queryIdlePage(ctx, lo, hi, exclusiveStart)
	if err != nil {
		return nil, err
	}
	if runner, err := r.assignFirst(ctx, sessionID, runners, tried); runner != nil || err != nil {
		return runner, err
	}
	if len(next) == 0 {
		return nil, nil
	}
	return r.acquireInRange(ctx, sessionID, lo, hi, next, tried)
}

// assignFirst は candidates のうち未試行のものを順に idle→busy へ遷移させ、最初に確保できた runner を返す。
// 全て試行済み・条件失敗なら (nil, nil) を返し、呼び出し側が走査を継続する。条件失敗以外は error を返す。
// tried への記録が重複候補と走査済み候補の再試行を同時に防ぐ。
func (r *DynamoRepository) assignFirst(ctx context.Context, sessionID string, candidates []model.Runner, tried map[string]struct{}) (*model.Runner, error) {
	for i := range candidates {
		runner := &candidates[i]
		if _, done := tried[runner.RunnerID]; done {
			continue
		}
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
	return nil, nil
}

// queryIdlePage は state-index を state = "idle" かつ runnerId ∈ [lo, hi] で acquireQueryLimit 件 query し、
// runner 群と続きの LastEvaluatedKey を返す。exclusiveStart が nil なら区間先頭から走査する。
func (r *DynamoRepository) queryIdlePage(ctx context.Context, lo, hi string, exclusiveStart map[string]types.AttributeValue) ([]model.Runner, map[string]types.AttributeValue, error) {
	out, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:                aws.String(r.tableName),
		IndexName:                aws.String("state-index"),
		KeyConditionExpression:   aws.String("#s = :s AND runnerId BETWEEN :lo AND :hi"),
		ExpressionAttributeNames: map[string]string{"#s": "state"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":s":  &types.AttributeValueMemberS{Value: string(model.StateIdle)},
			":lo": &types.AttributeValueMemberS{Value: lo},
			":hi": &types.AttributeValueMemberS{Value: hi},
		},
		Limit:             aws.Int32(acquireQueryLimit),
		ExclusiveStartKey: exclusiveStart,
	})
	if err != nil {
		return nil, nil, fmt.Errorf("query state-index: %w", err)
	}
	runners, err := unmarshalRunners(out.Items)
	if err != nil {
		return nil, nil, err
	}
	return runners, out.LastEvaluatedKey, nil
}

// unmarshalRunners は Query 結果の item 群を model.Runner に unmarshal する。
func unmarshalRunners(items []map[string]types.AttributeValue) ([]model.Runner, error) {
	runners := make([]model.Runner, 0, len(items))
	for _, item := range items {
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
