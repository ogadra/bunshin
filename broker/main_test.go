package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/ogadra/bunshin/broker/handler"
	"github.com/ogadra/bunshin/broker/healthcheck"
	"github.com/ogadra/bunshin/broker/model"
	"github.com/ogadra/bunshin/broker/service"
	"github.com/ogadra/bunshin/broker/store"
)

// setDynamoEnv は dynamodb 経路で必要な env をまとめて設定する。
func setDynamoEnv(t *testing.T) {
	t.Helper()
	t.Setenv("STACK_NAME", "ap-northeast-1")
	t.Setenv("BUNSHIN_STACKS", "ap-northeast-1,ap-northeast-3")
	t.Setenv("BUNSHIN_STORE", "dynamodb")
	t.Setenv("DYNAMODB_ENDPOINT", "http://localhost:18000")
	t.Setenv("AWS_REGION", "ap-northeast-1")
	t.Setenv("AWS_ACCESS_KEY_ID", "localdev")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "localdev")
}

// saveAndRestore は全てのパッケージレベル変数を退避し、テスト終了時に復元する。
func saveAndRestore(t *testing.T) {
	t.Helper()
	origStdout := stdout
	origAddr := addr
	origShutdownTimeout := shutdownTimeout
	origFatalf := fatalf
	origSignalNotify := signalNotify
	origInitHandler := initHandler
	origLoadAWSConfig := loadAWSConfig
	t.Cleanup(func() {
		stdout = origStdout
		addr = origAddr
		shutdownTimeout = origShutdownTimeout
		fatalf = origFatalf
		signalNotify = origSignalNotify
		initHandler = origInitHandler
		loadAWSConfig = origLoadAWSConfig
	})
	initHandler = func() (*handler.Handler, error) { return nil, nil }
}

// TestHealthEndpoint は GET /health が 200 OK を返すことを検証する。
func TestHealthEndpoint(t *testing.T) {
	r := newRouter(nil)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
}

// TestRunGracefulShutdown は run がシグナル受信時にグレースフルシャットダウンすることを検証する。
func TestRunGracefulShutdown(t *testing.T) {
	saveAndRestore(t)

	var buf bytes.Buffer
	stdout = &buf
	addr = ":0"
	shutdownTimeout = 1 * time.Second

	sigCh := make(chan os.Signal, 1)
	signalNotify = func(c chan<- os.Signal, _ ...os.Signal) {
		go func() {
			sig := <-sigCh
			c <- sig
		}()
	}

	done := make(chan error, 1)
	go func() {
		done <- run()
	}()

	time.Sleep(100 * time.Millisecond)
	sigCh <- os.Interrupt

	err := <-done
	if err != nil {
		t.Errorf("expected nil error, got %v", err)
	}
	if !strings.Contains(buf.String(), "broker listening on") {
		t.Errorf("expected listening message, got %q", buf.String())
	}
	if !strings.Contains(buf.String(), "shutting down") {
		t.Errorf("expected shutdown message, got %q", buf.String())
	}
}

// TestRunListenError は run がリッスン失敗時にエラーを返すことを検証する。
func TestRunListenError(t *testing.T) {
	saveAndRestore(t)

	stdout = io.Discard
	shutdownTimeout = 1 * time.Second

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer srv.Close()
	addr = srv.Listener.Addr().String()

	signalNotify = func(c chan<- os.Signal, _ ...os.Signal) {}

	err := run()
	if err == nil {
		t.Error("expected error, got nil")
	}
}

// TestMainSuccess は main がサーバー起動後シグナルで正常終了することを検証する。
func TestMainSuccess(t *testing.T) {
	saveAndRestore(t)

	stdout = io.Discard
	addr = ":0"
	shutdownTimeout = 1 * time.Second

	sigCh := make(chan os.Signal, 1)
	signalNotify = func(c chan<- os.Signal, _ ...os.Signal) {
		go func() {
			sig := <-sigCh
			c <- sig
		}()
	}

	done := make(chan struct{})
	go func() {
		main()
		close(done)
	}()

	time.Sleep(100 * time.Millisecond)
	sigCh <- os.Interrupt
	<-done
}

// TestRunInitHandlerError は initHandler がエラーを返す場合に run がエラーを返すことを検証する。
func TestRunInitHandlerError(t *testing.T) {
	saveAndRestore(t)

	stdout = io.Discard
	initHandler = func() (*handler.Handler, error) {
		return nil, errors.New("init failed")
	}

	err := run()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "init handler") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "init handler")
	}
}

// TestDefaultInitHandler は defaultInitHandler が全環境変数指定時に Handler を返すことを検証する。
func TestDefaultInitHandler(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	h, err := defaultInitHandler()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if h == nil {
		t.Fatal("expected non-nil handler")
	}
}

type fakeNoIdleService struct{}

func (fakeNoIdleService) CloseSession(context.Context, string) error { return nil }
func (fakeNoIdleService) ResolveSession(context.Context, string) (*service.ResolveResult, error) {
	return nil, store.ErrNoIdleRunner
}
func (fakeNoIdleService) RegisterRunner(context.Context, string, string) error { return nil }
func (fakeNoIdleService) DeregisterRunner(context.Context, string) error       { return nil }
func (fakeNoIdleService) ListBusyRunners(context.Context) ([]model.Runner, error) {
	return nil, nil
}

// TestDefaultInitHandler_FallbackSignal は BUNSHIN_STACKS から自スタックを除いた fallback を X-Fallback-Stack で返すことを検証する。
func TestDefaultInitHandler_FallbackSignal(t *testing.T) {
	origNewBrokerService := newBrokerService
	t.Cleanup(func() { newBrokerService = origNewBrokerService })
	newBrokerService = func(_ store.Repository, stack string, checker healthcheck.Checker) service.Service {
		if stack != "ap-northeast-1" {
			t.Errorf("stack = %q, want %q", stack, "ap-northeast-1")
		}
		if checker == nil {
			t.Error("checker is nil")
		}
		return fakeNoIdleService{}
	}

	setDynamoEnv(t)
	t.Setenv("BUNSHIN_STACKS", "ap-northeast-1,ap-northeast-3")

	h, err := defaultInitHandler()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	rec := httptest.NewRecorder()
	newRouter(h).ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
	if got := rec.Header().Get("X-Fallback-Stack"); got != "ap-northeast-3" {
		t.Errorf("X-Fallback-Stack = %q, want %q", got, "ap-northeast-3")
	}
	if got := rec.Header().Get("X-Fallback-Remaining"); got != "" {
		t.Errorf("X-Fallback-Remaining = %q, want empty", got)
	}
}

// TestDefaultInitHandler_MissingStack は STACK_NAME 未設定時にエラーを返すことを検証する。
func TestDefaultInitHandler_MissingStack(t *testing.T) {
	saveAndRestore(t)

	t.Setenv("STACK_NAME", "")

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "STACK_NAME") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "STACK_NAME")
	}
}

// TestDefaultInitHandler_StackNotInList は STACK_NAME が BUNSHIN_STACKS の列挙外なら起動失敗することを検証する。
func TestDefaultInitHandler_StackNotInList(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	t.Setenv("STACK_NAME", "ap-northeast-1")
	t.Setenv("BUNSHIN_STACKS", "ap-northeast-2,ap-northeast-3")

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "BUNSHIN_STACKS") {
		t.Errorf("error = %q, want to mention BUNSHIN_STACKS", err.Error())
	}
}

// TestDefaultInitHandler_MissingStacks は BUNSHIN_STACKS 未設定時にエラーを返すことを検証する。
func TestDefaultInitHandler_MissingStacks(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	t.Setenv("BUNSHIN_STACKS", "")

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "BUNSHIN_STACKS") {
		t.Errorf("error = %q, want to mention BUNSHIN_STACKS", err.Error())
	}
}

// TestDefaultInitHandler_MissingStore は BUNSHIN_STORE 未設定時にエラーを返すことを検証する。
func TestDefaultInitHandler_MissingStore(t *testing.T) {
	saveAndRestore(t)

	t.Setenv("STACK_NAME", "ap-northeast-1")
	t.Setenv("BUNSHIN_STACKS", "ap-northeast-1")
	t.Setenv("BUNSHIN_STORE", "")

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "BUNSHIN_STORE") {
		t.Errorf("error = %q, want to contain BUNSHIN_STORE", err.Error())
	}
}

// TestDefaultInitHandler_UnsupportedStore は BUNSHIN_STORE の値が未対応の場合にエラーを返すことを検証する。
func TestDefaultInitHandler_UnsupportedStore(t *testing.T) {
	saveAndRestore(t)

	t.Setenv("STACK_NAME", "ap-northeast-1")
	t.Setenv("BUNSHIN_STACKS", "ap-northeast-1")
	t.Setenv("BUNSHIN_STORE", "cassandra")

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "cassandra") {
		t.Errorf("error = %q, want to mention unsupported store", err.Error())
	}
}

// TestDefaultInitHandler_MissingRegion は BUNSHIN_STORE=dynamodb で AWS_REGION が未設定時にエラーを返すことを検証する。
func TestDefaultInitHandler_MissingRegion(t *testing.T) {
	saveAndRestore(t)

	t.Setenv("STACK_NAME", "ap-northeast-1")
	t.Setenv("BUNSHIN_STACKS", "ap-northeast-1")
	t.Setenv("BUNSHIN_STORE", "dynamodb")
	t.Setenv("AWS_REGION", "")

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "AWS_REGION") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "AWS_REGION")
	}
}

// TestDefaultInitHandler_WithoutStaticCredentials は静的クレデンシャルなしでも Handler を返すことを検証する。
func TestDefaultInitHandler_WithoutStaticCredentials(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	t.Setenv("AWS_ACCESS_KEY_ID", "")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "")

	h, err := defaultInitHandler()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if h == nil {
		t.Fatal("expected non-nil handler")
	}
}

// TestDefaultInitHandler_WithoutEndpoint は DYNAMODB_ENDPOINT なしでも Handler を返すことを検証する。
func TestDefaultInitHandler_WithoutEndpoint(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	t.Setenv("DYNAMODB_ENDPOINT", "")

	h, err := defaultInitHandler()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if h == nil {
		t.Fatal("expected non-nil handler")
	}
}

// TestDefaultInitHandler_PartialCredentials は片側のクレデンシャルのみ設定時にエラーを返すことを検証する。
func TestDefaultInitHandler_PartialCredentials(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	t.Setenv("AWS_ACCESS_KEY_ID", "localdev")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "")

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "AWS_ACCESS_KEY_ID") || !strings.Contains(err.Error(), "AWS_SECRET_ACCESS_KEY") {
		t.Errorf("error = %q, want to mention both credential keys", err.Error())
	}
}

// TestNewRouter_WithHandler は handler が non-nil の場合に全ルートが登録されることを検証する。
func TestNewRouter_WithHandler(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	h, err := defaultInitHandler()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	r := newRouter(h)

	routes := r.Routes()
	expected := map[string]string{
		"GET /health":                        "",
		"DELETE /sessions/:sessionId":        "",
		"GET /resolve":                       "",
		"POST /internal/runners/register":    "",
		"DELETE /internal/runners/:runnerId": "",
	}
	for _, route := range routes {
		key := route.Method + " " + route.Path
		delete(expected, key)
	}
	for key := range expected {
		t.Errorf("missing route: %s", key)
	}
}

// TestDefaultInitHandler_LoadConfigError は AWS config ロードが失敗した場合にエラーを返すことを検証する。
func TestDefaultInitHandler_LoadConfigError(t *testing.T) {
	saveAndRestore(t)
	setDynamoEnv(t)

	loadAWSConfig = func(_ context.Context, _ ...func(*config.LoadOptions) error) (aws.Config, error) {
		return aws.Config{}, errors.New("config load failed")
	}

	_, err := defaultInitHandler()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "load aws config") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "load aws config")
	}
}

// TestMainServerError は main がサーバー起動失敗時に fatalf を呼ぶことを検証する。
func TestMainServerError(t *testing.T) {
	saveAndRestore(t)

	stdout = io.Discard
	shutdownTimeout = 1 * time.Second

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer srv.Close()
	addr = srv.Listener.Addr().String()

	signalNotify = func(c chan<- os.Signal, _ ...os.Signal) {}

	var got string
	fatalf = func(format string, args ...any) {
		got = fmt.Sprintf(format, args...)
	}

	main()

	if !strings.Contains(got, "server error") {
		t.Errorf("expected fatalf called with error, got %q", got)
	}
}
