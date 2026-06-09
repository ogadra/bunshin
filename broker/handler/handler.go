// Package handler は broker の HTTP ハンドラーを提供する。
package handler

import (
	"errors"
	"net/http"
	"net/url"
	"regexp"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/ogadra/20260327-cli-demo/broker/model"
	"github.com/ogadra/20260327-cli-demo/broker/service"
	"github.com/ogadra/20260327-cli-demo/broker/store"
)

var runnerHostRe = regexp.MustCompile(`^[A-Za-z0-9.-]+$`)

// sessionIDCookie は session 識別用の cookie 名。
const sessionIDCookie = "session_id"

const delegatedResolveHeader = "X-Bunshin-Delegated-Resolve"

// Handler は broker の HTTP ハンドラー。
type Handler struct {
	svc             service.Service
	localStack      string
	fallbackTargets []StackTarget
	resolveClient   ResolveClient
}

type Option func(*Handler)

func WithStack(stack string) Option {
	return func(h *Handler) {
		h.localStack = stack
	}
}

func WithFallbackTargets(targets []StackTarget) Option {
	return func(h *Handler) {
		h.fallbackTargets = append([]StackTarget(nil), targets...)
	}
}

func WithResolveClient(client ResolveClient) Option {
	return func(h *Handler) {
		if client != nil {
			h.resolveClient = client
		}
	}
}

// NewHandler は Handler を生成する。svc が nil の場合は panic する。
func NewHandler(svc service.Service, opts ...Option) *Handler {
	if svc == nil {
		panic("handler: nil service")
	}
	h := &Handler{
		svc:           svc,
		resolveClient: NewHTTPResolveClient(http.DefaultClient),
	}
	for _, opt := range opts {
		opt(h)
	}
	return h
}

// registerRequest は POST /internal/runners/register のリクエストボディ。
type registerRequest struct {
	// RunnerID は runner の一意識別子。
	RunnerID string `json:"runnerId" binding:"required"`
	// PrivateURL は runner のプライベート URL。
	PrivateURL string `json:"privateUrl" binding:"required"`
}

// DeleteSession は DELETE /sessions/:sessionId を処理しセッションを終了する。
func (h *Handler) DeleteSession(c *gin.Context) {
	sessionID := c.Param("sessionId")
	err := h.svc.CloseSession(c.Request.Context(), sessionID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeError(c, http.StatusNotFound, model.CodeSessionNotFound, "session not found")
			return
		}
		writeError(c, http.StatusInternalServerError, model.CodeInternalError, "failed to close session")
		return
	}
	c.Status(http.StatusNoContent)
}

// GetResolve は GET /resolve を処理し session_id cookie からセッションを解決する。
// cookie が無い、またはセッションが見つからない場合は新規作成して Set-Cookie を返す。
func (h *Handler) GetResolve(c *gin.Context) {
	sessionID, _ := c.Cookie(sessionIDCookie)
	result, err := h.svc.ResolveSession(c.Request.Context(), sessionID)
	if err != nil {
		if errors.Is(err, store.ErrNoIdleRunner) {
			if c.GetHeader(delegatedResolveHeader) != "true" && h.resolveFromFallbacks(c, sessionID) {
				return
			}
			writeError(c, http.StatusServiceUnavailable, model.CodeNoIdleRunner, "no idle runner available")
			return
		}
		writeError(c, http.StatusInternalServerError, model.CodeInternalError, "failed to resolve session")
		return
	}
	if result.Created {
		c.SetSameSite(http.SameSiteStrictMode)
		c.SetCookie(sessionIDCookie, result.SessionID, 0, "/", "", true, true)
	}
	if result.Reassigned {
		c.Header("X-Session-Reassigned", "true")
	}
	c.Header("X-Runner-Url", result.RunnerURL)
	c.Status(http.StatusOK)
}

func (h *Handler) resolveFromFallbacks(c *gin.Context, sessionID string) bool {
	for _, target := range h.fallbackTargets {
		if h.localStack != "" && target.Stack == h.localStack {
			continue
		}
		if h.resolveFromTarget(c, target, sessionID, true) {
			return true
		}
	}
	return false
}

func (h *Handler) resolveFromTarget(c *gin.Context, target StackTarget, sessionID string, delegated bool) bool {
	result, err := h.resolveClient.Resolve(c.Request.Context(), target, sessionID, delegated)
	if err != nil {
		if errors.Is(err, store.ErrNoIdleRunner) {
			return false
		}
		writeError(c, http.StatusBadGateway, model.CodeInternalError, "failed to delegate resolve")
		return true
	}
	c.SetSameSite(http.SameSiteStrictMode)
	if result.SessionID != "" && result.SessionID != sessionID {
		c.SetCookie(sessionIDCookie, result.SessionID, 0, "/", "", true, true)
	}
	if result.Reassigned {
		c.Header("X-Session-Reassigned", "true")
	}
	c.Header("X-Runner-Url", result.RunnerURL)
	c.Status(http.StatusOK)
	return true
}

// runner の PrivateURL が http スキームの host[:port] 形式であることを検証する。
func validateRunnerURL(rawURL string) error {
	u, err := url.Parse(rawURL)
	if err != nil {
		return err
	}
	if u.Scheme != "http" {
		return errors.New("scheme must be http")
	}
	if u.User != nil {
		return errors.New("userinfo is not allowed")
	}
	if u.Host == "" {
		return errors.New("host is required")
	}
	if u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return errors.New("url must not contain path, query, or fragment")
	}
	if !runnerHostRe.MatchString(u.Hostname()) {
		return errors.New("host must be hostname-style")
	}
	if port := u.Port(); port != "" {
		n, err := strconv.Atoi(port)
		if err != nil || n < 1 || n > 65535 {
			return errors.New("port must be between 1 and 65535")
		}
	}
	return nil
}

// PostRegister は POST /internal/runners/register を処理し runner を登録する。
func (h *Handler) PostRegister(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, model.CodeInvalidRequest, "invalid request body")
		return
	}
	if err := validateRunnerURL(req.PrivateURL); err != nil {
		writeError(c, http.StatusBadRequest, model.CodeInvalidRequest, "invalid privateUrl: "+err.Error())
		return
	}
	err := h.svc.RegisterRunner(c.Request.Context(), req.RunnerID, req.PrivateURL)
	if err != nil {
		if errors.Is(err, store.ErrConflict) {
			writeError(c, http.StatusConflict, model.CodeRunnerConflict, "runner already registered with different attributes")
			return
		}
		writeError(c, http.StatusInternalServerError, model.CodeInternalError, "failed to register runner")
		return
	}
	c.Status(http.StatusCreated)
}

// DeleteRunner は DELETE /internal/runners/:runnerId を処理し runner を削除する。
func (h *Handler) DeleteRunner(c *gin.Context) {
	runnerID := c.Param("runnerId")
	err := h.svc.DeregisterRunner(c.Request.Context(), runnerID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, model.CodeInternalError, "failed to deregister runner")
		return
	}
	c.Status(http.StatusNoContent)
}

// writeError はエラーレスポンスを JSON で返す。
func writeError(c *gin.Context, status int, code, message string) {
	reqID, _ := c.Get(requestIDKey)
	rid, _ := reqID.(string)
	c.JSON(status, model.ErrorResponse{Code: code, Message: message, RequestID: rid})
}
