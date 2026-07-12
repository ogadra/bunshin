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

	"github.com/gin-gonic/gin"
	"github.com/ogadra/bunshin/broker/config"
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

// newBrokerService は BrokerService コンストラクタ。テスト時に差し替える。
var newBrokerService = func(repo store.Repository, stack string, checker healthcheck.Checker) service.Service {
	return service.NewBrokerService(repo, stack, service.WithChecker(checker))
}

// defaultInitHandler は環境変数を解決して Handler を組み立てる。
// 具体的な store 選択と client 生成は broker/config が担う。
func defaultInitHandler() (*handler.Handler, error) {
	stack := os.Getenv("STACK_NAME")
	if stack == "" {
		return nil, fmt.Errorf("missing required environment variable: STACK_NAME")
	}
	stackList := os.Getenv("BUNSHIN_STACKS")
	if stackList == "" {
		return nil, fmt.Errorf("missing required environment variable: BUNSHIN_STACKS")
	}
	if err := verifyStackInList(stack, stackList); err != nil {
		return nil, err
	}

	repo, err := config.NewRepositoryFromEnv(context.Background())
	if err != nil {
		return nil, err
	}
	checker := healthcheck.NewHTTPChecker(&http.Client{Timeout: 3 * time.Second})
	svc := newBrokerService(repo, stack, checker)
	return handler.NewHandler(svc, handler.FallbackStacksFromStackList(stackList, stack)), nil
}

// verifyStackInList は STACK_NAME が BUNSHIN_STACKS の中に含まれることを検証する。
func verifyStackInList(stack, rawList string) error {
	for _, s := range strings.Split(rawList, ",") {
		if strings.TrimSpace(s) == stack {
			return nil
		}
	}
	return fmt.Errorf("STACK_NAME %q is not listed in BUNSHIN_STACKS %q", stack, rawList)
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
