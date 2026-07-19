// Package handler は broker の HTTP ハンドラーのテストを提供する。
package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/ogadra/bunshin/broker/model"
	"github.com/ogadra/bunshin/broker/service"
	"github.com/ogadra/bunshin/broker/store"
)

// mockService は service.Service のモック実装。
type mockService struct {
	closeSessionFn     func(ctx context.Context, sessionID string) error
	resolveSessionFn   func(ctx context.Context, sessionID string) (*service.ResolveResult, error)
	lookupSessionFn    func(ctx context.Context, hex string) (*service.LookupResult, error)
	registerRunnerFn   func(ctx context.Context, runnerID, privateURL string) error
	deregisterRunnerFn func(ctx context.Context, runnerID string) error
	listBusyRunnersFn  func(ctx context.Context) ([]model.Runner, error)
}

// CloseSession はモック CloseSession を呼び出す。
func (m *mockService) CloseSession(ctx context.Context, sessionID string) error {
	return m.closeSessionFn(ctx, sessionID)
}

// ResolveSession はモック ResolveSession を呼び出す。
func (m *mockService) ResolveSession(ctx context.Context, sessionID string) (*service.ResolveResult, error) {
	return m.resolveSessionFn(ctx, sessionID)
}

// LookupSession はモック LookupSession を呼び出す。
func (m *mockService) LookupSession(ctx context.Context, hex string) (*service.LookupResult, error) {
	return m.lookupSessionFn(ctx, hex)
}

// RegisterRunner はモック RegisterRunner を呼び出す。
func (m *mockService) RegisterRunner(ctx context.Context, runnerID, privateURL string) error {
	return m.registerRunnerFn(ctx, runnerID, privateURL)
}

// DeregisterRunner はモック DeregisterRunner を呼び出す。
func (m *mockService) DeregisterRunner(ctx context.Context, runnerID string) error {
	return m.deregisterRunnerFn(ctx, runnerID)
}

// ListBusyRunners はモック ListBusyRunners を呼び出す。
func (m *mockService) ListBusyRunners(ctx context.Context) ([]model.Runner, error) {
	return m.listBusyRunnersFn(ctx)
}

// newTestRouter はテスト用のルーターを構築する。
func newTestRouter(h *Handler) *gin.Engine {
	r := gin.New()
	r.Use(RequestIDMiddleware(func() (string, error) {
		return "test-req-id", nil
	}))
	r.DELETE("/sessions/:sessionId", h.DeleteSession)
	r.GET("/resolve", h.GetResolve)
	r.GET("/resolve/app", h.GetResolveApp)
	r.POST("/internal/runners/register", h.PostRegister)
	r.DELETE("/internal/runners/:runnerId", h.DeleteRunner)
	r.GET("/runners/busy", h.GetListBusyRunners)
	return r
}

// TestDeleteSession_Success はセッション終了の成功を検証する。
func TestDeleteSession_Success(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		closeSessionFn: func(_ context.Context, sessionID string) error {
			if sessionID != "sess-abc" {
				t.Errorf("sessionID = %q, want %q", sessionID, "sess-abc")
			}
			return nil
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodDelete, "/sessions/sess-abc", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNoContent)
	}
}

// TestDeleteSession_NotFound はセッションが見つからない場合に 404 を返すことを検証する。
func TestDeleteSession_NotFound(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		closeSessionFn: func(_ context.Context, _ string) error {
			return store.ErrNotFound
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodDelete, "/sessions/sess-missing", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

// TestDeleteSession_InternalError は内部エラー時に 500 を返すことを検証する。
func TestDeleteSession_InternalError(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		closeSessionFn: func(_ context.Context, _ string) error {
			return errors.New("unexpected")
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodDelete, "/sessions/sess-abc", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// TestGetResolve_ExistingSession は既存セッションの解決成功を検証する。
func TestGetResolve_ExistingSession(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, sessionID string) (*service.ResolveResult, error) {
			if sessionID != "sess-abc" {
				t.Errorf("sessionID = %q, want %q", sessionID, "sess-abc")
			}
			return &service.ResolveResult{SessionID: "sess-abc", RunnerURL: "http://10.0.0.1:8080", Created: false}, nil
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	req.AddCookie(&http.Cookie{Name: "session_id", Value: "sess-abc"})
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("X-Runner-Url"); got != "http://10.0.0.1:8080" {
		t.Errorf("X-Runner-Url = %q, want %q", got, "http://10.0.0.1:8080")
	}
	for _, c := range rec.Result().Cookies() {
		if c.Name == "session_id" {
			t.Error("should not set session_id cookie for existing session")
		}
	}
}

// TestGetResolve_MissingCookie_CreatesSession は cookie がない場合にセッションを新規作成することを検証する。
func TestGetResolve_MissingCookie_CreatesSession(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, sessionID string) (*service.ResolveResult, error) {
			if sessionID != "" {
				t.Errorf("sessionID = %q, want empty", sessionID)
			}
			return &service.ResolveResult{SessionID: "ap-northeast-1_new-sess", RunnerURL: "http://10.0.0.2:8080", Created: true}, nil
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("X-Runner-Url"); got != "http://10.0.0.2:8080" {
		t.Errorf("X-Runner-Url = %q, want %q", got, "http://10.0.0.2:8080")
	}
	found := false
	for _, c := range rec.Result().Cookies() {
		if c.Name == "session_id" && c.Value == "ap-northeast-1_new-sess" {
			found = true
		}
	}
	if !found {
		t.Error("expected session_id cookie for new session")
	}
}

// TestGetResolve_NoIdleRunner は idle runner がない場合に 503 を返すことを検証する。
func TestGetResolve_NoIdleRunner(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, _ string) (*service.ResolveResult, error) {
			return nil, store.ErrNoIdleRunner
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
	if got := rec.Header().Get("X-Fallback-Stack"); got != "" {
		t.Errorf("X-Fallback-Stack = %q, want empty when no fallback configured", got)
	}
}

func noIdleResolve(fallback []string, reqHeaders map[string]string) *httptest.ResponseRecorder {
	return noIdleResolveWithCookie(fallback, reqHeaders, "")
}

func noIdleResolveWithCookie(fallback []string, reqHeaders map[string]string, sessionID string) *httptest.ResponseRecorder {
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, _ string) (*service.ResolveResult, error) {
			return nil, store.ErrNoIdleRunner
		},
	}, fallback)
	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	for k, v := range reqHeaders {
		req.Header.Set(k, v)
	}
	if sessionID != "" {
		req.AddCookie(&http.Cookie{Name: "session_id", Value: sessionID})
	}
	rec := httptest.NewRecorder()
	newTestRouter(h).ServeHTTP(rec, req)
	return rec
}

// TestGetResolve_FallbackOrigin は origin の枯渇で先頭を X-Fallback-Stack、残りを X-Fallback-Remaining に出すことを検証する。
func TestGetResolve_FallbackOrigin(t *testing.T) {
	t.Parallel()
	rec := noIdleResolve([]string{"ap-northeast-3", "ap-northeast-2"}, nil)
	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
	if got := rec.Header().Get("X-Fallback-Stack"); got != "ap-northeast-3" {
		t.Errorf("X-Fallback-Stack = %q, want %q", got, "ap-northeast-3")
	}
	if got := rec.Header().Get("X-Fallback-Remaining"); got != "ap-northeast-2" {
		t.Errorf("X-Fallback-Remaining = %q, want %q", got, "ap-northeast-2")
	}
}

// TestGetResolve_FallbackForwarded は転送済みで残りがある場合、remaining の先頭を次の forward にすることを検証する。
func TestGetResolve_FallbackForwarded(t *testing.T) {
	t.Parallel()
	rec := noIdleResolve([]string{}, map[string]string{
		"X-Fallback-Stack":     "ap-northeast-3",
		"X-Fallback-Remaining": "ap-northeast-2",
	})
	if got := rec.Header().Get("X-Fallback-Stack"); got != "ap-northeast-2" {
		t.Errorf("X-Fallback-Stack = %q, want %q", got, "ap-northeast-2")
	}
	if got := rec.Header().Get("X-Fallback-Remaining"); got != "" {
		t.Errorf("X-Fallback-Remaining = %q, want empty", got)
	}
}

// TestGetResolve_FallbackForwardedKeepsTail は remaining が複数のとき先頭を pop し残りを維持することを検証する。
func TestGetResolve_FallbackForwardedKeepsTail(t *testing.T) {
	t.Parallel()
	rec := noIdleResolve([]string{}, map[string]string{
		"X-Fallback-Stack":     "ap-northeast-3",
		"X-Fallback-Remaining": "ap-northeast-2,us-east-1",
	})
	if got := rec.Header().Get("X-Fallback-Stack"); got != "ap-northeast-2" {
		t.Errorf("X-Fallback-Stack = %q, want %q", got, "ap-northeast-2")
	}
	if got := rec.Header().Get("X-Fallback-Remaining"); got != "us-east-1" {
		t.Errorf("X-Fallback-Remaining = %q, want %q", got, "us-east-1")
	}
}

// TestGetResolve_FallbackLastStack は転送済みで残りが無い(最後の stack)場合に forward を出さないことを検証する。
func TestGetResolve_FallbackLastStack(t *testing.T) {
	t.Parallel()
	rec := noIdleResolve([]string{}, map[string]string{"X-Fallback-Stack": "ap-northeast-2"})
	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
	if got := rec.Header().Get("X-Fallback-Stack"); got != "" {
		t.Errorf("X-Fallback-Stack = %q, want empty for last stack", got)
	}
}

// TestGetResolve_InternalError は内部エラー時に 500 を返すことを検証する。
func TestGetResolve_InternalError(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, _ string) (*service.ResolveResult, error) {
			return nil, errors.New("unexpected")
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	req.AddCookie(&http.Cookie{Name: "session_id", Value: "sess-abc"})
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// TestPostRegister_Success は runner 登録の成功を検証する。
func TestPostRegister_Success(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		registerRunnerFn: func(_ context.Context, runnerID, privateURL string) error {
			if runnerID != "r1" {
				t.Errorf("runnerID = %q, want %q", runnerID, "r1")
			}
			if privateURL != "http://10.0.0.1:8080" {
				t.Errorf("privateURL = %q, want %q", privateURL, "http://10.0.0.1:8080")
			}
			return nil
		},
	}, []string{})
	r := newTestRouter(h)

	body := strings.NewReader(`{"runnerId":"r1","privateUrl":"http://10.0.0.1:8080"}`)
	req := httptest.NewRequest(http.MethodPost, "/internal/runners/register", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusCreated)
	}
}

// TestPostRegister_InvalidBody はリクエストボディが不正な場合に 400 を返すことを検証する。
func TestPostRegister_InvalidBody(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{}, []string{})
	r := newTestRouter(h)

	body := strings.NewReader(`{}`)
	req := httptest.NewRequest(http.MethodPost, "/internal/runners/register", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

// TestPostRegister_InternalError は内部エラー時に 500 を返すことを検証する。
func TestPostRegister_InternalError(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		registerRunnerFn: func(_ context.Context, _, _ string) error {
			return errors.New("unexpected")
		},
	}, []string{})
	r := newTestRouter(h)

	body := strings.NewReader(`{"runnerId":"r1","privateUrl":"http://10.0.0.1:8080"}`)
	req := httptest.NewRequest(http.MethodPost, "/internal/runners/register", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// TestPostRegister_Conflict は同一 runnerId が別属性で登録済みの場合に 409 を返すことを検証する。
func TestPostRegister_Conflict(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		registerRunnerFn: func(_ context.Context, _, _ string) error {
			return store.ErrConflict
		},
	}, []string{})
	r := newTestRouter(h)

	body := strings.NewReader(`{"runnerId":"r1","privateUrl":"http://10.0.0.1:8080"}`)
	req := httptest.NewRequest(http.MethodPost, "/internal/runners/register", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusConflict)
	}
}

// TestDeleteRunner_Success は runner 削除の成功を検証する。
func TestDeleteRunner_Success(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		deregisterRunnerFn: func(_ context.Context, runnerID string) error {
			if runnerID != "r1" {
				t.Errorf("runnerID = %q, want %q", runnerID, "r1")
			}
			return nil
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodDelete, "/internal/runners/r1", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNoContent)
	}
}

// TestDeleteRunner_InternalError は内部エラー時に 500 を返すことを検証する。
func TestDeleteRunner_InternalError(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		deregisterRunnerFn: func(_ context.Context, _ string) error {
			return errors.New("unexpected")
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodDelete, "/internal/runners/r1", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// TestWriteError_IncludesRequestID はエラーレスポンスに requestId が含まれることを検証する。
func TestWriteError_IncludesRequestID(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, _ string) (*service.ResolveResult, error) {
			return nil, errors.New("unexpected")
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	req.AddCookie(&http.Cookie{Name: "session_id", Value: "sess-missing"})
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if !strings.Contains(rec.Body.String(), "test-req-id") {
		t.Errorf("body = %q, want to contain %q", rec.Body.String(), "test-req-id")
	}
}

// TestNewHandler は NewHandler のコンストラクタを検証する。
func TestNewHandler(t *testing.T) {
	t.Parallel()
	svc := &mockService{}
	h := NewHandler(svc, []string{})
	if h.svc != svc {
		t.Error("svc mismatch")
	}
}

// TestNewHandler_NilPanics は NewHandler に nil を渡すと panic することを検証する。
func TestNewHandler_NilPanics(t *testing.T) {
	t.Parallel()
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for nil service")
		}
	}()
	NewHandler(nil, []string{})
}

// TestPostRegister_InvalidURL は不正な URL 形式の場合に 400 を返すことを検証する。
func TestPostRegister_InvalidURL(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		url  string
	}{
		{"no scheme", "10.0.0.1:8080"},
		{"ftp scheme", "ftp://10.0.0.1:8080"},
		{"no host", "http://"},
		{"relative path", "/runner"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			h := NewHandler(&mockService{
				registerRunnerFn: func(_ context.Context, _, _ string) error {
					t.Fatal("service should not be called for invalid URL")
					return nil
				},
			}, []string{})
			r := newTestRouter(h)

			body := strings.NewReader(`{"runnerId":"r1","privateUrl":"` + tt.url + `"}`)
			req := httptest.NewRequest(http.MethodPost, "/internal/runners/register", body)
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			r.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want %d for url %q", rec.Code, http.StatusBadRequest, tt.url)
			}
		})
	}
}

// TestValidateRunnerURL は validateRunnerURL の境界値を検証する。
func TestValidateRunnerURL(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		url     string
		wantErr bool
	}{
		{"valid http", "http://10.0.0.1:3000", false},
		{"valid http no port", "http://runner.local", false},
		{"trailing slash", "http://runner.local:3000/", true},
		{"https scheme", "https://runner.local:3000", true},
		{"no scheme", "10.0.0.1:3000", true},
		{"ftp scheme", "ftp://10.0.0.1:3000", true},
		{"empty host", "http://", true},
		{"relative", "/path", true},
		{"with path", "http://10.0.0.1:3000/base", true},
		{"with query", "http://10.0.0.1:3000?x=1", true},
		{"with fragment", "http://10.0.0.1:3000#frag", true},
		{"userinfo", "http://user:pass@runner.local:3000", true},
		{"underscore host", "http://runner_01:3000", true},
		{"ipv6 host", "http://[::1]:3000", true},
		{"port zero", "http://runner.local:0", true},
		{"port too large", "http://runner.local:99999", true},
		{"non-numeric port", "http://runner.local:abc", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			err := validateRunnerURL(tt.url)
			if (err != nil) != tt.wantErr {
				t.Errorf("validateRunnerURL(%q) error = %v, wantErr %v", tt.url, err, tt.wantErr)
			}
		})
	}
}

// TestGetResolve_CookieSecure はセッション新規作成時の session_id cookie が Secure=true であることを検証する。
func TestGetResolve_CookieSecure(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, _ string) (*service.ResolveResult, error) {
			return &service.ResolveResult{SessionID: "new-sess", RunnerURL: "http://10.0.0.1:8080", Created: true}, nil
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	for _, c := range rec.Result().Cookies() {
		if c.Name == "session_id" {
			if !c.Secure {
				t.Error("expected Secure=true on session_id cookie")
			}
			if !c.HttpOnly {
				t.Error("expected HttpOnly=true on session_id cookie")
			}
			if c.SameSite != http.SameSiteStrictMode {
				t.Errorf("expected SameSite=Strict on session_id cookie, got %v", c.SameSite)
			}
			return
		}
	}
	t.Error("session_id cookie not found")
}

// TestGetResolve_Reassigned はセッション再割当て時に X-Session-Reassigned ヘッダーが設定されることを検証する。
func TestGetResolve_Reassigned(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, _ string) (*service.ResolveResult, error) {
			return &service.ResolveResult{
				SessionID:  "new-sess",
				RunnerURL:  "http://10.0.0.2:8080",
				Created:    true,
				Reassigned: true,
			}, nil
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	req.AddCookie(&http.Cookie{Name: "session_id", Value: "old-sess"})
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("X-Session-Reassigned"); got != "true" {
		t.Errorf("X-Session-Reassigned = %q, want %q", got, "true")
	}
	if got := rec.Header().Get("X-Runner-Url"); got != "http://10.0.0.2:8080" {
		t.Errorf("X-Runner-Url = %q, want %q", got, "http://10.0.0.2:8080")
	}
}

// TestGetResolve_NotReassigned はセッション再割当てなしの場合に X-Session-Reassigned ヘッダーが設定されないことを検証する。
func TestGetResolve_NotReassigned(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		resolveSessionFn: func(_ context.Context, _ string) (*service.ResolveResult, error) {
			return &service.ResolveResult{
				SessionID:  "sess-1",
				RunnerURL:  "http://10.0.0.1:8080",
				Created:    false,
				Reassigned: false,
			}, nil
		},
	}, []string{})
	r := newTestRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/resolve", nil)
	req.AddCookie(&http.Cookie{Name: "session_id", Value: "sess-1"})
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	if got := rec.Header().Get("X-Session-Reassigned"); got != "" {
		t.Errorf("X-Session-Reassigned = %q, want empty", got)
	}
	if got := rec.Header().Get("X-Runner-Url"); got != "http://10.0.0.1:8080" {
		t.Errorf("X-Runner-Url = %q, want %q", got, "http://10.0.0.1:8080")
	}
}

// log.SetOutput はパッケージ全体のグローバル状態を触るため、これを使うテストでは t.Parallel() を付けない。
func captureStdLog(t *testing.T) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	origOut, origFlags := log.Writer(), log.Flags()
	log.SetOutput(&buf)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(origOut)
		log.SetFlags(origFlags)
	})
	return &buf
}

// TestSignalFallback_LogsUnavailable は fallback pool 枯渇時に
// fallback_signal unavailable ログが request_id と session_id 付きで出ることを検証する。
func TestSignalFallback_LogsUnavailable(t *testing.T) {
	buf := captureStdLog(t)
	rec := noIdleResolveWithCookie([]string{}, nil, "sess-xyz")
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
	for _, want := range []string{
		"fallback_signal unavailable",
		"request_id=test-req-id",
		"session_id=sess-xyz",
	} {
		if !strings.Contains(buf.String(), want) {
			t.Errorf("log = %q, want substring %q", buf.String(), want)
		}
	}
}

// TestSignalFallback_LogsNextStack は fallback 転送発生時に
// next_stack / remaining / request_id / session_id 付きのログが出ることを検証する。
func TestSignalFallback_LogsNextStack(t *testing.T) {
	buf := captureStdLog(t)
	rec := noIdleResolveWithCookie([]string{"ap-northeast-3", "ap-northeast-2"}, nil, "sess-abc")
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
	for _, want := range []string{
		"fallback_signal next_stack=ap-northeast-3",
		"remaining=ap-northeast-2",
		"request_id=test-req-id",
		"session_id=sess-abc",
	} {
		if !strings.Contains(buf.String(), want) {
			t.Errorf("log = %q, want substring %q", buf.String(), want)
		}
	}
}

// TestGetListBusyRunners_Success はサービスが返した runner を JSON で返すことを検証する。
// currentSessionId は cookie 値そのものなのでレスポンスに含めない。
func TestGetListBusyRunners_Success(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		listBusyRunnersFn: func(context.Context) ([]model.Runner, error) {
			return []model.Runner{
				{RunnerID: "r1", State: model.StateBusy, CurrentSessionID: "sess-1"},
				{RunnerID: "r2", State: model.StateBusy, CurrentSessionID: "sess-2"},
			}, nil
		},
	}, []string{})
	rec := httptest.NewRecorder()
	newTestRouter(h).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/runners/busy", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if strings.Contains(rec.Body.String(), "sess-") {
		t.Errorf("response leaks session id: %s", rec.Body.String())
	}
	var resp struct {
		Runners []struct {
			RunnerID string `json:"runnerId"`
		} `json:"runners"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal body: %v", err)
	}
	if len(resp.Runners) != 2 {
		t.Fatalf("len(runners) = %d, want 2", len(resp.Runners))
	}
	if resp.Runners[0].RunnerID != "r1" {
		t.Errorf("runners[0].RunnerID = %q, want r1", resp.Runners[0].RunnerID)
	}
	if resp.Runners[1].RunnerID != "r2" {
		t.Errorf("runners[1].RunnerID = %q, want r2", resp.Runners[1].RunnerID)
	}
}

// TestGetListBusyRunners_Empty は busy runner がいない場合に空配列を返すことを検証する。
func TestGetListBusyRunners_Empty(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		listBusyRunnersFn: func(context.Context) ([]model.Runner, error) {
			return nil, nil
		},
	}, []string{})
	rec := httptest.NewRecorder()
	newTestRouter(h).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/runners/busy", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if !strings.Contains(rec.Body.String(), `"runners":[]`) {
		t.Errorf("body = %q, want to contain \"runners\":[]", rec.Body.String())
	}
}

// TestGetListBusyRunners_ServiceError はサービスがエラーを返した場合に 500 を返すことを検証する。
func TestGetListBusyRunners_ServiceError(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		listBusyRunnersFn: func(context.Context) ([]model.Runner, error) {
			return nil, errors.New("boom")
		},
	}, []string{})
	rec := httptest.NewRecorder()
	newTestRouter(h).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/runners/busy", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// TestGetResolveApp_Existing は既存 session の hex から runner URL を返すことを検証する。
func TestGetResolveApp_Existing(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		lookupSessionFn: func(_ context.Context, hex string) (*service.LookupResult, error) {
			if hex != "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" {
				t.Errorf("hex = %q, want %q", hex, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
			}
			return &service.LookupResult{RunnerURL: "http://10.0.0.1:3000"}, nil
		},
	}, []string{})
	req := httptest.NewRequest(http.MethodGet, "/resolve/app", nil)
	req.Header.Set("X-Session-Hex", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	newTestRouter(h).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("X-Runner-Url"); got != "http://10.0.0.1:3000" {
		t.Errorf("X-Runner-Url = %q, want %q", got, "http://10.0.0.1:3000")
	}
	for _, c := range rec.Result().Cookies() {
		if c.Name == "session_id" {
			t.Errorf("lookup must not set session_id cookie")
		}
	}
}

// TestGetResolveApp_NotFound は不在 hex が 404 SESSION_NOT_FOUND を返すことを検証する。
func TestGetResolveApp_NotFound(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		lookupSessionFn: func(context.Context, string) (*service.LookupResult, error) {
			return nil, store.ErrNotFound
		},
	}, []string{})
	req := httptest.NewRequest(http.MethodGet, "/resolve/app", nil)
	req.Header.Set("X-Session-Hex", "00112233445566778899aabbccddeeff")
	rec := httptest.NewRecorder()
	newTestRouter(h).ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
	if !strings.Contains(rec.Body.String(), `"code":"SESSION_NOT_FOUND"`) {
		t.Errorf("body = %q, want SESSION_NOT_FOUND", rec.Body.String())
	}
	if got := rec.Header().Get("X-Runner-Url"); got != "" {
		t.Errorf("X-Runner-Url = %q, want empty", got)
	}
}

// TestGetResolveApp_InvalidHex は不正形式の hex が 400 INVALID_REQUEST を返し LookupSession を呼ばないことを検証する。
func TestGetResolveApp_InvalidHex(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		hex  string
	}{
		{"empty", ""},
		{"too short", "aaaa"},
		{"too long", strings.Repeat("a", 33)},
		{"uppercase", strings.Repeat("A", 32)},
		{"non hex", strings.Repeat("g", 32)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			h := NewHandler(&mockService{
				lookupSessionFn: func(context.Context, string) (*service.LookupResult, error) {
					t.Error("LookupSession must not be called for invalid hex")
					return nil, nil
				},
			}, []string{})
			req := httptest.NewRequest(http.MethodGet, "/resolve/app", nil)
			if tc.hex != "" {
				req.Header.Set("X-Session-Hex", tc.hex)
			}
			rec := httptest.NewRecorder()
			newTestRouter(h).ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
			}
			if !strings.Contains(rec.Body.String(), `"code":"INVALID_REQUEST"`) {
				t.Errorf("body = %q, want INVALID_REQUEST", rec.Body.String())
			}
		})
	}
}

// TestGetResolveApp_ServiceError は LookupSession のエラーが 500 INTERNAL_ERROR を返すことを検証する。
func TestGetResolveApp_ServiceError(t *testing.T) {
	t.Parallel()
	h := NewHandler(&mockService{
		lookupSessionFn: func(context.Context, string) (*service.LookupResult, error) {
			return nil, errors.New("boom")
		},
	}, []string{})
	req := httptest.NewRequest(http.MethodGet, "/resolve/app", nil)
	req.Header.Set("X-Session-Hex", "00112233445566778899aabbccddeeff")
	rec := httptest.NewRecorder()
	newTestRouter(h).ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
	if !strings.Contains(rec.Body.String(), `"code":"INTERNAL_ERROR"`) {
		t.Errorf("body = %q, want INTERNAL_ERROR", rec.Body.String())
	}
}
