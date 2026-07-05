// Package store はリポジトリ層のテストを提供する。
package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/ogadra/bunshin/broker/model"
)

// mockDynamoDBAPI は DynamoDBAPI のモック実装。
type mockDynamoDBAPI struct {
	putItemFn    func(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	getItemFn    func(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	updateItemFn func(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	deleteItemFn func(ctx context.Context, params *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
	queryFn      func(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error)
}

// PutItem はモック PutItem を呼び出す。
func (m *mockDynamoDBAPI) PutItem(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
	return m.putItemFn(ctx, params, optFns...)
}

// GetItem はモック GetItem を呼び出す。
func (m *mockDynamoDBAPI) GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
	return m.getItemFn(ctx, params, optFns...)
}

// UpdateItem はモック UpdateItem を呼び出す。
func (m *mockDynamoDBAPI) UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	return m.updateItemFn(ctx, params, optFns...)
}

// DeleteItem はモック DeleteItem を呼び出す。
func (m *mockDynamoDBAPI) DeleteItem(ctx context.Context, params *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error) {
	return m.deleteItemFn(ctx, params, optFns...)
}

// Query はモック Query を呼び出す。
func (m *mockDynamoDBAPI) Query(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
	return m.queryFn(ctx, params, optFns...)
}

// idleItem は state = StateIdle の GSI item を組み立てるヘルパー。
func idleItem(runnerID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{
		"runnerId": &types.AttributeValueMemberS{Value: runnerID},
		"state":    &types.AttributeValueMemberS{Value: string(model.StateIdle)},
	}
}

// TestNewDynamoRepository はコンストラクタが必要な依存関係を設定することを検証する。
func TestNewDynamoRepository(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{}
	repo := NewDynamoRepository(mock, "test-table")
	if repo.client != mock {
		t.Error("client mismatch")
	}
	if repo.tableName != "test-table" {
		t.Errorf("tableName = %q, want %q", repo.tableName, "test-table")
	}
	if repo.randHexFn == nil {
		t.Error("randHexFn is nil")
	}
	if repo.marshalFn == nil {
		t.Error("marshalFn is nil")
	}
}

// TestDefaultRandHexFn はデフォルト乱数関数が 32 文字の hex 文字列を返し、
// 十分に分散していることを検証する。
func TestDefaultRandHexFn(t *testing.T) {
	t.Parallel()
	seen := map[string]struct{}{}
	for range 100 {
		v := defaultRandHexFn()
		if len(v) != 32 {
			t.Fatalf("len(defaultRandHexFn()) = %d, want 32", len(v))
		}
		for _, c := range v {
			if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
				t.Fatalf("non-hex character %q in %q", c, v)
			}
		}
		seen[v] = struct{}{}
	}
	if len(seen) < 90 {
		t.Errorf("distinct values = %d, want at least 90 in 100 iterations", len(seen))
	}
}

// TestRegister_MarshalError は MarshalMap がエラーを返す場合にエラーを返すことを検証する。
func TestRegister_MarshalError(t *testing.T) {
	t.Parallel()
	repo := NewDynamoRepository(&mockDynamoDBAPI{}, "t")
	repo.marshalFn = func(_ interface{}) (map[string]types.AttributeValue, error) {
		return nil, errors.New("marshal error")
	}

	err := repo.Register(context.Background(), "r1", "http://10.0.0.1:8080")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestRegister_Success は新規登録の成功ケースを検証する。state = "idle" が書き込まれる。
func TestRegister_Success(t *testing.T) {
	t.Parallel()
	called := false
	mock := &mockDynamoDBAPI{
		putItemFn: func(_ context.Context, params *dynamodb.PutItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			called = true
			if *params.ConditionExpression != "attribute_not_exists(runnerId)" {
				t.Errorf("unexpected condition: %s", *params.ConditionExpression)
			}
			state, ok := params.Item["state"].(*types.AttributeValueMemberS)
			if !ok || state.Value != string(model.StateIdle) {
				t.Errorf("state was not marshaled as idle, got %v", params.Item["state"])
			}
			v, ok := params.Item["privateUrl"].(*types.AttributeValueMemberS)
			if !ok || v.Value != "http://10.0.0.1:8080" {
				t.Errorf("privateUrl was not marshaled correctly")
			}
			return &dynamodb.PutItemOutput{}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	err := repo.Register(context.Background(), "r1", "http://10.0.0.1:8080")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Error("PutItem was not called")
	}
}

// TestRegister_AlreadyExists は登録済み runner の再登録が同一 privateURL なら冪等に成功することを検証する。
func TestRegister_AlreadyExists(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		putItemFn: func(_ context.Context, _ *dynamodb.PutItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			return nil, &types.ConditionalCheckFailedException{Message: aws.String("exists")}
		},
		getItemFn: func(_ context.Context, _ *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return &dynamodb.GetItemOutput{
				Item: map[string]types.AttributeValue{
					"runnerId":   &types.AttributeValueMemberS{Value: "r1"},
					"privateUrl": &types.AttributeValueMemberS{Value: "http://10.0.0.1:8080"},
					"state":      &types.AttributeValueMemberS{Value: string(model.StateIdle)},
				},
			}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	err := repo.Register(context.Background(), "r1", "http://10.0.0.1:8080")
	if err != nil {
		t.Fatalf("expected nil for idempotent register, got: %v", err)
	}
}

// TestRegister_ConflictPrivateURL は同一 runnerID で異なる privateURL の登録が ErrConflict を返すことを検証する。
func TestRegister_ConflictPrivateURL(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		putItemFn: func(_ context.Context, _ *dynamodb.PutItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			return nil, &types.ConditionalCheckFailedException{Message: aws.String("exists")}
		},
		getItemFn: func(_ context.Context, _ *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return &dynamodb.GetItemOutput{
				Item: map[string]types.AttributeValue{
					"runnerId":   &types.AttributeValueMemberS{Value: "r1"},
					"privateUrl": &types.AttributeValueMemberS{Value: "http://10.0.0.1:8080"},
					"state":      &types.AttributeValueMemberS{Value: string(model.StateIdle)},
				},
			}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	err := repo.Register(context.Background(), "r1", "http://10.0.0.2:9090")
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

// TestRegister_ConflictFindByIDError は条件失敗後の FindByID エラーを検証する。
func TestRegister_ConflictFindByIDError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		putItemFn: func(_ context.Context, _ *dynamodb.PutItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			return nil, &types.ConditionalCheckFailedException{Message: aws.String("exists")}
		},
		getItemFn: func(_ context.Context, _ *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return nil, errors.New("get error")
		},
	}
	repo := NewDynamoRepository(mock, "t")

	err := repo.Register(context.Background(), "r1", "http://10.0.0.1:8080")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestRegister_EmptyPrivateURL は privateURL が空の場合にエラーを返すことを検証する。
func TestRegister_EmptyPrivateURL(t *testing.T) {
	t.Parallel()
	repo := NewDynamoRepository(&mockDynamoDBAPI{}, "t")

	err := repo.Register(context.Background(), "r1", "")
	if err == nil {
		t.Fatal("expected error for empty privateURL")
	}
}

// TestRegister_PutItemError は PutItem の予期せぬエラーを検証する。
func TestRegister_PutItemError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		putItemFn: func(_ context.Context, _ *dynamodb.PutItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			return nil, errors.New("network error")
		},
	}
	repo := NewDynamoRepository(mock, "t")

	err := repo.Register(context.Background(), "r1", "http://10.0.0.1:8080")
	if err == nil {
		t.Fatal("expected error")
	}
}

// assertStateIdxRandomStart は random start query の KeyConditionExpression と bindings を検証する。
func assertStateIdxRandomStart(t *testing.T, params *dynamodb.QueryInput, wantStart string) {
	t.Helper()
	if params.IndexName == nil || *params.IndexName != "state-index" {
		t.Fatalf("IndexName = %v, want state-index", params.IndexName)
	}
	if *params.KeyConditionExpression != "#s = :s AND runnerId >= :r" {
		t.Errorf("KeyConditionExpression = %q", *params.KeyConditionExpression)
	}
	if got := params.ExpressionAttributeValues[":s"].(*types.AttributeValueMemberS).Value; got != string(model.StateIdle) {
		t.Errorf(":s = %q, want %q", got, model.StateIdle)
	}
	if got := params.ExpressionAttributeValues[":r"].(*types.AttributeValueMemberS).Value; got != wantStart {
		t.Errorf(":r = %q, want %q", got, wantStart)
	}
	if params.Limit == nil || *params.Limit != acquireQueryLimit {
		t.Errorf("Limit = %v, want %d", params.Limit, acquireQueryLimit)
	}
}

// assertStateIdxWrap は wrap query が partition 先頭 (minRunnerID) を開始位置に発行されていることを検証する。
func assertStateIdxWrap(t *testing.T, params *dynamodb.QueryInput) {
	t.Helper()
	assertStateIdxRandomStart(t, params, minRunnerID)
}

// TestAcquireIdle_Success はランダム開始位置で idle runner を確保できることを検証する。
func TestAcquireIdle_Success(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, params *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			assertStateIdxRandomStart(t, params, "0000000000000000")
			return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{idleItem("r1")}}, nil
		},
		updateItemFn: func(_ context.Context, params *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			if params.Key["runnerId"].(*types.AttributeValueMemberS).Value != "r1" {
				t.Errorf("unexpected runnerId")
			}
			if *params.ConditionExpression != "#s = :idle" {
				t.Errorf("ConditionExpression = %q", *params.ConditionExpression)
			}
			if *params.UpdateExpression != "SET currentSessionId = :sid REMOVE #s" {
				t.Errorf("UpdateExpression = %q", *params.UpdateExpression)
			}
			return &dynamodb.UpdateItemOutput{}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r1" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "r1")
	}
	if runner.CurrentSessionID != "sess-1" {
		t.Errorf("currentSessionId = %q, want %q", runner.CurrentSessionID, "sess-1")
	}
	if !runner.IsBusy() {
		t.Errorf("expected runner to be busy, state = %q", runner.State)
	}
}

// TestAcquireIdle_WrapFromHead は random start が空の場合に partition 先頭から wrap query して取得できることを検証する。
func TestAcquireIdle_WrapFromHead(t *testing.T) {
	t.Parallel()
	queryCount := 0
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, params *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			queryCount++
			if queryCount == 1 {
				assertStateIdxRandomStart(t, params, "ffffffffffffffff")
				return &dynamodb.QueryOutput{Items: nil}, nil
			}
			assertStateIdxWrap(t, params)
			return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{idleItem("r-first")}}, nil
		},
		updateItemFn: func(_ context.Context, _ *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			return &dynamodb.UpdateItemOutput{}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "ffffffffffffffff" }

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r-first" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "r-first")
	}
	if queryCount != 2 {
		t.Errorf("queryCount = %d, want 2", queryCount)
	}
}

// TestAcquireIdle_NoIdleRunner は両クエリが空の場合に最大 2 query で ErrNoIdleRunner を返すことを検証する。
func TestAcquireIdle_NoIdleRunner(t *testing.T) {
	t.Parallel()
	queryCount := 0
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			queryCount++
			return &dynamodb.QueryOutput{Items: nil}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
	if queryCount != 2 {
		t.Errorf("queryCount = %d, want 2 (random + wrap)", queryCount)
	}
}

// TestAcquireIdle_RandomQueryError は random start の Query エラー時にエラーを返すことを検証する。
func TestAcquireIdle_RandomQueryError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return nil, errors.New("query error")
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestAcquireIdle_WrapQueryError は wrap query の Query エラー時にエラーを返すことを検証する。
func TestAcquireIdle_WrapQueryError(t *testing.T) {
	t.Parallel()
	queryCount := 0
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			queryCount++
			if queryCount == 1 {
				return &dynamodb.QueryOutput{Items: nil}, nil
			}
			return nil, errors.New("wrap query error")
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestAcquireIdle_RetryWithinBatch はバッチ内で条件失敗した候補をスキップし次を試行することを検証する。
func TestAcquireIdle_RetryWithinBatch(t *testing.T) {
	t.Parallel()
	queryCount := 0
	updateCount := 0
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			queryCount++
			return &dynamodb.QueryOutput{
				Items: []map[string]types.AttributeValue{idleItem("r1"), idleItem("r2")},
			}, nil
		},
		updateItemFn: func(_ context.Context, params *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			updateCount++
			rid := params.Key["runnerId"].(*types.AttributeValueMemberS).Value
			if rid != "r2" {
				return nil, &types.ConditionalCheckFailedException{Message: aws.String("conflict")}
			}
			return &dynamodb.UpdateItemOutput{}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r2" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "r2")
	}
	if queryCount != 1 {
		t.Errorf("queryCount = %d, want 1", queryCount)
	}
	if updateCount != 2 {
		t.Errorf("updateCount = %d, want 2", updateCount)
	}
}

// TestAcquireIdle_RegenRandomOnAllConflict は全候補が条件失敗した場合に乱数を作り直して再試行することを検証する。
func TestAcquireIdle_RegenRandomOnAllConflict(t *testing.T) {
	t.Parallel()
	queryCount := 0
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			queryCount++
			if queryCount == 1 {
				return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{idleItem("r-conflict")}}, nil
			}
			return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{idleItem("r-ok")}}, nil
		},
		updateItemFn: func(_ context.Context, params *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			if params.Key["runnerId"].(*types.AttributeValueMemberS).Value == "r-conflict" {
				return nil, &types.ConditionalCheckFailedException{Message: aws.String("conflict")}
			}
			return &dynamodb.UpdateItemOutput{}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")
	seq := []string{"11111111111111111111111111111111", "22222222222222222222222222222222"}
	i := 0
	repo.randHexFn = func() string {
		v := seq[i]
		i++
		return v
	}

	runner, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r-ok" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "r-ok")
	}
	if i != 2 {
		t.Errorf("randHexFn calls = %d, want 2", i)
	}
}

// TestAcquireIdle_StaleGSI は stale item を返し続ける GSI に対しても tried set で有限時間で ErrNoIdleRunner に収束することを検証する。
func TestAcquireIdle_StaleGSI(t *testing.T) {
	t.Parallel()
	queryCount := 0
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			queryCount++
			return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{idleItem("r-stale")}}, nil
		},
		updateItemFn: func(_ context.Context, _ *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			return nil, &types.ConditionalCheckFailedException{Message: aws.String("stale")}
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
	// 1 回目: 候補 r-stale → conflict → tried に追加
	// 2 回目: 候補 r-stale → tried で除外 → 前進なし → ErrNoIdleRunner
	if queryCount != 2 {
		t.Errorf("queryCount = %d, want 2 (initial + stale detection)", queryCount)
	}
}

// TestAcquireIdle_UpdateError は UpdateItem の予期せぬエラーを検証する。
func TestAcquireIdle_UpdateError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{idleItem("r1")}}, nil
		},
		updateItemFn: func(_ context.Context, _ *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			return nil, errors.New("update error")
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestAcquireIdle_UnmarshalError は Query 結果の unmarshal 失敗を検証する。
func TestAcquireIdle_UnmarshalError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return &dynamodb.QueryOutput{
				Items: []map[string]types.AttributeValue{
					{"runnerId": &types.AttributeValueMemberL{Value: []types.AttributeValue{}}},
				},
			}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")
	repo.randHexFn = func() string { return "0000000000000000" }

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected unmarshal error")
	}
}

// TestFindBySessionID_Success は session ID で runner が見つかるケースを検証する。
func TestFindBySessionID_Success(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, params *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			if *params.IndexName != "session-index" {
				t.Errorf("unexpected index: %s", *params.IndexName)
			}
			return &dynamodb.QueryOutput{
				Items: []map[string]types.AttributeValue{
					{
						"runnerId":         &types.AttributeValueMemberS{Value: "r1"},
						"currentSessionId": &types.AttributeValueMemberS{Value: "sess-1"},
					},
				},
			}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	runner, err := repo.FindBySessionID(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r1" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "r1")
	}
}

// TestFindBySessionID_NotFound は session が見つからない場合に ErrNotFound を返すことを検証する。
func TestFindBySessionID_NotFound(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return &dynamodb.QueryOutput{Items: nil}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	_, err := repo.FindBySessionID(context.Background(), "sess-x")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

// TestFindBySessionID_QueryError は Query エラー時にエラーを返すことを検証する。
func TestFindBySessionID_QueryError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return nil, errors.New("query error")
		},
	}
	repo := NewDynamoRepository(mock, "t")

	_, err := repo.FindBySessionID(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestFindBySessionID_UnmarshalError は Query 結果の unmarshal 失敗を検証する。
func TestFindBySessionID_UnmarshalError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, _ *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return &dynamodb.QueryOutput{
				Items: []map[string]types.AttributeValue{
					{"runnerId": &types.AttributeValueMemberL{Value: []types.AttributeValue{}}},
				},
			}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	_, err := repo.FindBySessionID(context.Background(), "sess-1")
	if err == nil {
		t.Fatal("expected unmarshal error")
	}
}

// TestFindByID_Success は runner ID で runner が見つかるケースを検証する。
func TestFindByID_Success(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		getItemFn: func(_ context.Context, _ *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return &dynamodb.GetItemOutput{Item: idleItem("r1")}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	runner, err := repo.FindByID(context.Background(), "r1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if runner.RunnerID != "r1" {
		t.Errorf("runnerID = %q, want %q", runner.RunnerID, "r1")
	}
	if !runner.IsIdle() {
		t.Error("expected runner to be idle")
	}
}

// TestFindByID_NotFound は runner が存在しない場合に ErrNotFound を返すことを検証する。
func TestFindByID_NotFound(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		getItemFn: func(_ context.Context, _ *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return &dynamodb.GetItemOutput{Item: nil}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	_, err := repo.FindByID(context.Background(), "r-missing")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

// TestFindByID_GetItemError は GetItem の予期せぬエラーを検証する。
func TestFindByID_GetItemError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		getItemFn: func(_ context.Context, _ *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return nil, errors.New("get error")
		},
	}
	repo := NewDynamoRepository(mock, "t")

	_, err := repo.FindByID(context.Background(), "r1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestFindByID_UnmarshalError は GetItem 結果の unmarshal 失敗を検証する。
func TestFindByID_UnmarshalError(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		getItemFn: func(_ context.Context, _ *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return &dynamodb.GetItemOutput{
				Item: map[string]types.AttributeValue{
					"runnerId": &types.AttributeValueMemberL{Value: []types.AttributeValue{}},
				},
			}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	_, err := repo.FindByID(context.Background(), "r1")
	if err == nil {
		t.Fatal("expected unmarshal error")
	}
}

// TestDelete_Success は正常な削除を検証する。
func TestDelete_Success(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		deleteItemFn: func(_ context.Context, params *dynamodb.DeleteItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error) {
			if params.Key["runnerId"].(*types.AttributeValueMemberS).Value != "r1" {
				t.Errorf("unexpected runnerId")
			}
			return &dynamodb.DeleteItemOutput{}, nil
		},
	}
	repo := NewDynamoRepository(mock, "t")

	err := repo.Delete(context.Background(), "r1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

// TestDelete_Error は DeleteItem の予期せぬエラーを検証する。
func TestDelete_Error(t *testing.T) {
	t.Parallel()
	mock := &mockDynamoDBAPI{
		deleteItemFn: func(_ context.Context, _ *dynamodb.DeleteItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error) {
			return nil, errors.New("delete error")
		},
	}
	repo := NewDynamoRepository(mock, "t")

	err := repo.Delete(context.Background(), "r1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// TestDynamoRepository_ImplementsRepository は DynamoRepository が Repository インターフェースを満たすことを検証する。
func TestDynamoRepository_ImplementsRepository(t *testing.T) {
	t.Parallel()
	var _ Repository = (*DynamoRepository)(nil)
}

// TestAcquireIdle_QueryStartsAreDistinctPerIteration は反復ごとに異なる randHexFn の値が :r に反映されることを検証する。
func TestAcquireIdle_QueryStartsAreDistinctPerIteration(t *testing.T) {
	t.Parallel()
	seen := []string{}
	mock := &mockDynamoDBAPI{
		queryFn: func(_ context.Context, params *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			if v, ok := params.ExpressionAttributeValues[":r"]; ok {
				seen = append(seen, v.(*types.AttributeValueMemberS).Value)
			}
			return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{idleItem("r-stale")}}, nil
		},
		updateItemFn: func(_ context.Context, _ *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			return nil, &types.ConditionalCheckFailedException{Message: aws.String("stale")}
		},
	}
	repo := NewDynamoRepository(mock, "t")
	seq := []string{fmt.Sprintf("%032d", 1), fmt.Sprintf("%032d", 2)}
	i := 0
	repo.randHexFn = func() string {
		v := seq[i%len(seq)]
		i++
		return v
	}

	_, err := repo.AcquireIdle(context.Background(), "sess-1")
	if !errors.Is(err, ErrNoIdleRunner) {
		t.Fatalf("expected ErrNoIdleRunner, got: %v", err)
	}
	if len(seen) < 2 {
		t.Fatalf("expected at least 2 query starts, got %d", len(seen))
	}
	if seen[0] == seen[1] {
		t.Errorf("expected distinct query starts, got %q twice", seen[0])
	}
	if !strings.Contains(seen[0], "1") || !strings.Contains(seen[1], "2") {
		t.Errorf("randHexFn sequence not respected, got %v", seen)
	}
}
