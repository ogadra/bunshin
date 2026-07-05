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
// fast path として state-index (hash=state, range=runnerId) をランダムな runnerId から前方走査し、
// acquireQueryLimit に満たなければ partition 先頭 (minRunnerID) から不足分を補って候補を埋める。
// runnerId は crypto/rand hex で keyspace に一様分布するため、ランダム開始点の successor 自体が
// idle 集合上で一様になり、最初に試す候補が分散して head のホットスポットを避けられる。
// fast path の窓が stale (既 busy) item で埋まると小さい runnerId の idle を見落としうるため、
// fast path で確保できなければ partition 先頭から LastEvaluatedKey で idle 全体を走査し、
// 未試行 idle が存在しないことを確認してから ErrNoIdleRunner を返す。
// tried set が走査済み候補を除外するので、stale index に対しても有限時間で枯渇判定に収束する。
func (r *DynamoRepository) AcquireIdle(ctx context.Context, sessionID string) (*model.Runner, error) {
	tried := map[string]struct{}{}

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
	if runner, err := r.assignFirst(ctx, sessionID, candidates, tried); runner != nil || err != nil {
		return runner, err
	}

	var startKey map[string]types.AttributeValue
	for {
		runners, next, err := r.scanIdlePage(ctx, startKey)
		if err != nil {
			return nil, err
		}
		if runner, err := r.assignFirst(ctx, sessionID, runners, tried); runner != nil || err != nil {
			return runner, err
		}
		if len(next) == 0 {
			return nil, ErrNoIdleRunner
		}
		startKey = next
	}
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
	return unmarshalRunners(out.Items)
}

// scanIdlePage は idle partition を先頭 (minRunnerID) から 1 ページ query し、runner 群と続きの
// LastEvaluatedKey を返す。exclusiveStart が nil なら先頭ページから走査する。
func (r *DynamoRepository) scanIdlePage(ctx context.Context, exclusiveStart map[string]types.AttributeValue) ([]model.Runner, map[string]types.AttributeValue, error) {
	out, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:                aws.String(r.tableName),
		IndexName:                aws.String("state-index"),
		KeyConditionExpression:   aws.String("#s = :s AND runnerId >= :r"),
		ExpressionAttributeNames: map[string]string{"#s": "state"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":s": &types.AttributeValueMemberS{Value: string(model.StateIdle)},
			":r": &types.AttributeValueMemberS{Value: minRunnerID},
		},
		ExclusiveStartKey: exclusiveStart,
	})
	if err != nil {
		return nil, nil, fmt.Errorf("scan state-index: %w", err)
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
