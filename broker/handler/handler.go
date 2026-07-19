// Package handler は broker の HTTP ハンドラーを提供する。
package handler

import (
	"errors"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ogadra/bunshin/broker/model"
	"github.com/ogadra/bunshin/broker/service"
	"github.com/ogadra/bunshin/broker/stacklist"
	"github.com/ogadra/bunshin/broker/store"
)

var runnerHostRe = regexp.MustCompile(`^[A-Za-z0-9.-]+$`)

// hex は capability secret のため、ログに残る query ではなくヘッダで受ける。
var sessionHexRe = regexp.MustCompile(`^[0-9a-f]{32}$`)

// sessionIDCookie は session 識別用の cookie 名。
const sessionIDCookie = "session_id"

const fallbackStackHeader = "X-Fallback-Stack"

const fallbackRemainingHeader = "X-Fallback-Remaining"

const sessionHexHeader = "X-Session-Hex"

const runnerURLHeader = "X-Runner-Url"

// Handler は broker の HTTP ハンドラー。
type Handler struct {
	svc            service.Service
	fallbackStacks []string
}

// NewHandler は Handler を生成する。svc が nil の場合は panic する。
func NewHandler(svc service.Service, fallbackStacks []string) *Handler {
	if svc == nil {
		panic("handler: nil service")
	}
	return &Handler{svc: svc, fallbackStacks: fallbackStacks}
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
			h.signalFallback(c)
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
	c.Header(runnerURLHeader, result.RunnerURL)
	c.Status(http.StatusOK)
}

// GetResolveApp は GET /resolve/app を処理し X-Session-Hex から所属 runner を引く。
// port-forward 用に session 割り当ては行わず、既存 session の runner URL のみ返す。
func (h *Handler) GetResolveApp(c *gin.Context) {
	hex := c.GetHeader(sessionHexHeader)
	if !sessionHexRe.MatchString(hex) {
		writeError(c, http.StatusBadRequest, model.CodeInvalidRequest, "X-Session-Hex must be 32 lowercase hex characters")
		return
	}
	result, err := h.svc.LookupSession(c.Request.Context(), hex)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeError(c, http.StatusNotFound, model.CodeSessionNotFound, "session not found")
			return
		}
		writeError(c, http.StatusInternalServerError, model.CodeInternalError, "failed to look up session")
		return
	}
	c.Header(runnerURLHeader, result.RunnerURL)
	c.Status(http.StatusOK)
}

// X-Fallback-Stack の有無を転送済み判定に兼用し、専用のマーカーヘッダを増やさない。
func (h *Handler) signalFallback(c *gin.Context) {
	pool := h.fallbackStacks
	if c.GetHeader(fallbackStackHeader) != "" {
		pool = stacklist.Split(c.GetHeader(fallbackRemainingHeader))
	}
	if len(pool) == 0 {
		log.Printf("fallback_signal unavailable request_id=%s session_id=%s", requestID(c), sessionCookie(c))
		return
	}
	c.Header(fallbackStackHeader, pool[0])
	if len(pool) > 1 {
		c.Header(fallbackRemainingHeader, strings.Join(pool[1:], ","))
	}
	log.Printf(
		"fallback_signal next_stack=%s remaining=%s request_id=%s session_id=%s",
		pool[0],
		strings.Join(pool[1:], ","),
		requestID(c),
		sessionCookie(c),
	)
}

func requestID(c *gin.Context) string {
	reqID, _ := c.Get(requestIDKey)
	rid, _ := reqID.(string)
	return rid
}

func sessionCookie(c *gin.Context) string {
	sessionID, _ := c.Cookie(sessionIDCookie)
	return sessionID
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

// currentSessionId は session cookie 値そのままで、露出させると session hijack を許すため busy 一覧レスポンスには載せない。
type busyRunnerView struct {
	RunnerID string `json:"runnerId"`
}

type busyRunnersResponse struct {
	Runners []busyRunnerView `json:"runners"`
}

// GetListBusyRunners は GET /runners/busy を処理し busy runner の全件を返す。
func (h *Handler) GetListBusyRunners(c *gin.Context) {
	runners, err := h.svc.ListBusyRunners(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, model.CodeInternalError, "failed to list busy runners")
		return
	}
	views := make([]busyRunnerView, 0, len(runners))
	for _, r := range runners {
		views = append(views, busyRunnerView{RunnerID: r.RunnerID})
	}
	c.JSON(http.StatusOK, busyRunnersResponse{Runners: views})
}

// writeError はエラーレスポンスを JSON で返す。
func writeError(c *gin.Context, status int, code, message string) {
	reqID, _ := c.Get(requestIDKey)
	rid, _ := reqID.(string)
	c.JSON(status, model.ErrorResponse{Code: code, Message: message, RequestID: rid})
}
