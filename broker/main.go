// Package main は broker サービスのエントリポイントを提供する。
package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/gin-gonic/gin"
	"github.com/ogadra/bunshin/broker/handler"
	"github.com/ogadra/bunshin/broker/healthcheck"
	"github.com/ogadra/bunshin/broker/service"
	"github.com/ogadra/bunshin/broker/store"
)

// newRouter は broker の HTTP ルーティングを構成した gin.Engine を返す。
// h が nil の場合はヘルスチェックのみ登録する。
func newRouter(h *handler.Handler) *gin.Engine {
	r := gin.Default()
	r.GET("/health", func(c *gin.Context) {
		c.String(http.StatusOK, "ok\n")
	})
	if h != nil {
		r.Use(handler.RequestIDMiddleware(handler.DefaultIDFn))
		r.DELETE("/sessions/:sessionId", h.DeleteSession)
		r.GET("/resolve", h.GetResolve)
		r.POST("/internal/runners/register", h.PostRegister)
		r.DELETE("/internal/runners/:runnerId", h.DeleteRunner)
		r.GET("/runners/busy", h.GetListBusyRunners)
	}
	return r
}

// stdout はメインの出力先。テスト時に差し替える。
var stdout io.Writer = os.Stdout

// addr はサーバーのリッスンアドレス。テスト時に差し替える。
var addr = ":8080"

// shutdownTimeout はグレースフルシャットダウンのタイムアウト。テスト時に差し替える。
var shutdownTimeout = 5 * time.Second

// fatalf はエラー時の終了処理。テスト時に差し替える。
var fatalf = log.Fatalf

// signalNotify は os/signal.Notify のラッパー。テスト時に差し替える。
var signalNotify = signal.Notify

// initHandler はストアクライアントを初期化し Handler を生成する関数。テスト時に差し替える。
var initHandler = defaultInitHandler

// loadAWSConfig は AWS SDK の設定をロードする関数。テスト時に差し替える。
var loadAWSConfig = config.LoadDefaultConfig

var newBrokerService = func(repo store.Repository, stack string, checker healthcheck.Checker) service.Service {
	return service.NewBrokerService(repo, stack, service.WithChecker(checker))
}

// defaultInitHandler は環境変数から Repository を構築し Handler を返す。
func defaultInitHandler() (*handler.Handler, error) {
	stack := os.Getenv("STACK_NAME")
	if stack == "" {
		return nil, fmt.Errorf("missing required environment variable: STACK_NAME")
	}
	stackList := os.Getenv("BUNSHIN_STACKS")
	if err := verifyStackInList(stack, stackList); err != nil {
		return nil, err
	}

	repo, err := newRepositoryFromEnv(context.Background())
	if err != nil {
		return nil, err
	}
	checker := healthcheck.NewHTTPChecker(&http.Client{Timeout: 3 * time.Second})
	svc := newBrokerService(repo, stack, checker)
	return handler.NewHandler(svc, handler.FallbackStacksFromStackList(stackList, stack)), nil
}

// verifyStackInList は BUNSHIN_STACKS が設定されている場合に STACK_NAME がその中に含まれることを検証する。
// BUNSHIN_STACKS 未設定 (single stack 想定) は許容する。
func verifyStackInList(stack, rawList string) error {
	if rawList == "" {
		return nil
	}
	for _, s := range strings.Split(rawList, ",") {
		if strings.TrimSpace(s) == stack {
			return nil
		}
	}
	return fmt.Errorf("STACK_NAME %q is not listed in BUNSHIN_STACKS %q", stack, rawList)
}

func newRepositoryFromEnv(ctx context.Context) (store.Repository, error) {
	switch kind := os.Getenv("BUNSHIN_STORE"); kind {
	case "dynamodb":
		return newDynamoRepositoryFromEnv(ctx)
	case "":
		return nil, fmt.Errorf("missing required environment variable: BUNSHIN_STORE")
	default:
		return nil, fmt.Errorf("unsupported BUNSHIN_STORE %q (expected dynamodb)", kind)
	}
}

func newDynamoRepositoryFromEnv(ctx context.Context) (store.Repository, error) {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		return nil, fmt.Errorf("missing required environment variable: AWS_REGION")
	}

	accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
	secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")
	if (accessKey == "") != (secretKey == "") {
		return nil, fmt.Errorf("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must both be set or both be empty")
	}

	opts := []func(*config.LoadOptions) error{
		config.WithRegion(region),
	}
	if accessKey != "" {
		opts = append(opts, config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")))
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
	client := dynamodb.NewFromConfig(cfg, ddbOpts...)
	return store.NewDynamoRepository(client, "bunshin-runners"), nil
}

// run はサーバーの起動とグレースフルシャットダウンを行う。
func run() error {
	h, err := initHandler()
	if err != nil {
		return fmt.Errorf("init handler: %w", err)
	}
	r := newRouter(h)

	srv := &http.Server{
		Addr:    addr,
		Handler: r,
	}

	fmt.Fprintf(stdout, "broker listening on %s\n", addr)

	errCh := make(chan error, 1)
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	quit := make(chan os.Signal, 1)
	signalNotify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		return err
	case sig := <-quit:
		fmt.Fprintf(stdout, "received signal %s, shutting down...\n", sig)
	}

	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	return srv.Shutdown(ctx)
}

// main は broker の HTTP サーバーを起動する。
func main() {
	if err := run(); err != nil {
		fatalf("server error: %v", err)
	}
}
