//go:build integration

// Package integration は全サービスを結合した統合テストを提供する。
package integration

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

// httpClient はテスト用の HTTP クライアント。タイムアウトを設定して CI でのハングを防止する。
var httpClient = &http.Client{
	Timeout: 10 * time.Second,
}

// sseEvent は SSE ストリームから受信する単一イベントを表す。
type sseEvent struct {
	Type     string `json:"type"`
	Data     string `json:"data,omitempty"`
	ExitCode *int   `json:"exitCode,omitempty"`
}

// sessionCookies はセッション管理に必要な cookie を保持する。
type sessionCookies struct {
	SessionID string
	ShellID   string
}

// cookieHeader は sessionCookies を Cookie ヘッダ文字列に変換する。
func (c sessionCookies) cookieHeader() string {
	return fmt.Sprintf("session_id=%s; shell_id=%s", c.SessionID, c.ShellID)
}

// nginxBase は nginx の URL。TestMain で初期化される。
var nginxBase string

// brokerBase は broker の内部 URL。TestMain で初期化される。
// テスト間で runner の状態をリセットするために broker の内部 API を直接呼び出す。
var brokerBase string

// forwardTargetBase は cross-region forward 先モックの制御 URL。TestMain で初期化される。
var forwardTargetBase string

// runnerHostnames は全 runner のホスト名。TestMain で初期化される。
// テスト間の runner リセットに使用する。
var runnerHostnames []string

// TestMain はテスト実行前にサービスの起動を待機し、全 runner のホスト名を解決する。
func TestMain(m *testing.M) {
	nginxBase = os.Getenv("NGINX_URL")
	if nginxBase == "" {
		fmt.Fprintln(os.Stderr, "NGINX_URL environment variable is required")
		os.Exit(1)
	}
	brokerBase = os.Getenv("BROKER_URL")
	if brokerBase == "" {
		fmt.Fprintln(os.Stderr, "BROKER_URL environment variable is required")
		os.Exit(1)
	}
	forwardTargetBase = os.Getenv("FORWARD_TARGET_URL")
	if forwardTargetBase == "" {
		fmt.Fprintln(os.Stderr, "FORWARD_TARGET_URL environment variable is required")
		os.Exit(1)
	}

	if !waitForReady(nginxBase + "/health") {
		fmt.Fprintln(os.Stderr, "nginx did not become ready within 60 seconds")
		os.Exit(1)
	}
	if !waitForReady(forwardTargetBase + "/health") {
		fmt.Fprintln(os.Stderr, "forward target did not become ready within 60 seconds")
		os.Exit(1)
	}

	hostnames, err := discoverRunnerHostnames()
	if err != nil {
		fmt.Fprintf(os.Stderr, "discover runners: %v\n", err)
		os.Exit(1)
	}
	runnerHostnames = hostnames

	os.Exit(m.Run())
}

// waitForReady は指定された URL が 200 を返すまでポーリングする。
func waitForReady(url string) bool {
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := httpClient.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return true
			}
		}
		time.Sleep(2 * time.Second)
	}
	return false
}

// discoverRunnerHostnames は broker の GET /resolve を idle runner が尽きる (503) まで繰り返し、
// 全 runner のホスト名を決定的に列挙する。
//
// 各 resolve は idle runner を 1 台 busy にする。セッションを途中で解放すると AcquireIdle の
// rand.Shuffle (broker/store/dynamo.go) と相まって復元抽出となり、同じ runner を引き直して
// 別 runner を取りこぼす (2 台構成で約 50%)。そこで解放せず 503 まで回し切ることで全 distinct
// ホスト名を確実に収集し、ループ後に runner を delete+register でまとめて idle へ戻す。
func discoverRunnerHostnames() ([]string, error) {
	seen := map[string]bool{}
	var hostnames []string

	for {
		resp, err := httpClient.Get(brokerBase + "/resolve")
		if err != nil {
			return nil, fmt.Errorf("GET /resolve: %w", err)
		}
		status := resp.StatusCode
		runnerURL := resp.Header.Get("X-Runner-Url")
		resp.Body.Close()
		if status != http.StatusOK {
			break // idle runner 枯渇 (503) = 全 runner を取得しきった
		}
		if runnerURL == "" {
			return nil, fmt.Errorf("X-Runner-Url header not found")
		}

		hostname := strings.TrimPrefix(runnerURL, "http://")
		hostname = strings.SplitN(hostname, ":", 2)[0]
		if !seen[hostname] {
			seen[hostname] = true
			hostnames = append(hostnames, hostname)
		}
	}

	if len(hostnames) == 0 {
		return nil, fmt.Errorf("no runners discovered")
	}

	// 列挙で busy になった全 runner を idle へ戻す (delete+register は resetRunners と同じ確実な手順)。
	for _, h := range hostnames {
		if err := deleteFromBroker(brokerBase + "/internal/runners/" + h); err != nil {
			return nil, fmt.Errorf("delete runner %s: %w", h, err)
		}
		if err := registerRunnerOnBroker(h); err != nil {
			return nil, fmt.Errorf("register runner %s: %w", h, err)
		}
	}

	return hostnames, nil
}

// deleteFromBroker は broker のエンドポイントに DELETE リクエストを送信する。
func deleteFromBroker(url string) error {
	req, err := http.NewRequest(http.MethodDelete, url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	resp.Body.Close()
	// 削除は冪等として扱う: 既に存在しない (404) 場合は成功とみなす。
	if resp.StatusCode == http.StatusNotFound {
		return nil
	}
	if resp.StatusCode >= 300 {
		return fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	return nil
}

// registerRunnerOnBroker は runner を broker に登録する。
func registerRunnerOnBroker(hostname string) error {
	body := fmt.Sprintf(`{"runnerId":%q,"privateUrl":"http://%s:3000"}`, hostname, hostname)
	req, err := http.NewRequest(http.MethodPost, brokerBase+"/internal/runners/register", strings.NewReader(body))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	return nil
}

// resetRunners は全 runner を broker から削除し再登録することで idle 状態に戻す
func resetRunners(t *testing.T, sessionID string) {
	t.Helper()
	if sessionID != "" {
		if err := deleteFromBroker(brokerBase + "/sessions/" + sessionID); err != nil {
			t.Logf("resetRunners: close session %s: %v", sessionID, err)
		}
	}
	for _, h := range runnerHostnames {
		if err := deleteFromBroker(brokerBase + "/internal/runners/" + h); err != nil {
			t.Errorf("delete runner %s: %v", h, err)
		}
		if err := registerRunnerOnBroker(h); err != nil {
			t.Errorf("register runner %s: %v", h, err)
		}
	}
}

// setupSession はセッションを作成し、テスト終了時に runner を idle に戻す cleanup を登録する。
func setupSession(t *testing.T) sessionCookies {
	t.Helper()
	cookies := createSession(t)
	t.Cleanup(func() { resetRunners(t, cookies.SessionID) })
	return cookies
}

// createSession は POST /api/shell を nginx 経由で呼び出しセッションを作成する。
func createSession(t *testing.T) sessionCookies {
	t.Helper()
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/shell", "", "")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("POST /api/shell: want 204, got %d", resp.StatusCode)
	}
	var cookies sessionCookies
	for _, c := range resp.Cookies() {
		switch c.Name {
		case "session_id":
			cookies.SessionID = c.Value
		case "shell_id":
			cookies.ShellID = c.Value
		}
	}
	if cookies.SessionID == "" {
		t.Fatal("session_id cookie not found in response")
	}
	if cookies.ShellID == "" {
		t.Fatal("shell_id cookie not found in response")
	}
	return cookies
}

// doRequest は HTTP リクエストを送信しレスポンスを返す。
func doRequest(t *testing.T, method, url, bodyStr, cookie string) *http.Response {
	t.Helper()
	return doRequestWithHeaders(t, method, url, bodyStr, cookie, nil)
}

// doRequestWithHeaders は HTTP リクエストを送信し追加ヘッダを設定する。
func doRequestWithHeaders(t *testing.T, method, url, bodyStr, cookie string, headers map[string]string) *http.Response {
	t.Helper()
	var body io.Reader
	if bodyStr != "" {
		body = strings.NewReader(bodyStr)
	}
	req, err := http.NewRequest(method, url, body)
	if err != nil {
		t.Fatalf("create request: %v", err)
	}
	if bodyStr != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, url, err)
	}
	return resp
}

type forwardedRequest struct {
	Method string              `json:"method"`
	Path   string              `json:"path"`
	Host   string              `json:"host"`
	Header map[string][]string `json:"header"`
}

func resetForwardTarget(t *testing.T) {
	t.Helper()
	resp, err := httpClient.Get(forwardTargetBase + "/__reset")
	if err != nil {
		t.Fatalf("reset forward target: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("reset forward target: want 204, got %d", resp.StatusCode)
	}
}

func lastForwardedRequest(t *testing.T) forwardedRequest {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := httpClient.Get(forwardTargetBase + "/__last")
		if err != nil {
			t.Fatalf("get forwarded request: %v", err)
		}
		if resp.StatusCode == http.StatusNotFound {
			resp.Body.Close()
			time.Sleep(100 * time.Millisecond)
			continue
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("get forwarded request: want 200, got %d", resp.StatusCode)
		}
		var got forwardedRequest
		if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
			t.Fatalf("decode forwarded request: %v", err)
		}
		return got
	}
	t.Fatal("forward target did not receive a request")
	return forwardedRequest{}
}

// executeCommand は POST /api/execute を呼び出し SSE イベントをパースして返す。
func executeCommand(t *testing.T, cookies sessionCookies, command string) []sseEvent {
	t.Helper()
	payload := struct {
		Command string `json:"command"`
	}{Command: command}
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal request body: %v", err)
	}
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/execute", string(bodyBytes), cookies.cookieHeader())
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("POST /api/execute: want 200, got %d", resp.StatusCode)
	}
	return parseSSEEvents(t, resp)
}

// parseSSEEvents は HTTP レスポンスから SSE イベントを読み取りパースする。
func parseSSEEvents(t *testing.T, resp *http.Response) []sseEvent {
	t.Helper()
	var events []sseEvent
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		data := strings.TrimPrefix(line, "data: ")
		var event sseEvent
		if err := json.Unmarshal([]byte(data), &event); err != nil {
			t.Fatalf("parse SSE event %q: %v", data, err)
		}
		events = append(events, event)
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("read SSE stream: %v", err)
	}
	return events
}

// --- 正常系テスト ---

// TestHealthCheck は nginx のヘルスチェックエンドポイントが正常に応答することを検証する。
func TestHealthCheck(t *testing.T) {
	resp, err := httpClient.Get(nginxBase + "/health")
	if err != nil {
		t.Fatalf("GET /health: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET /health: want 200, got %d", resp.StatusCode)
	}
}

// TestCreateShellAndExecute はセッション作成からコマンド実行までの正常系フローを検証する。
func TestCreateShellAndExecute(t *testing.T) {
	cookies := setupSession(t)

	events := executeCommand(t, cookies, "pwd")

	var stdout string
	var hasComplete bool
	for _, e := range events {
		if e.Type == "stdout" {
			stdout += e.Data
		}
		if e.Type == "complete" && e.ExitCode != nil && *e.ExitCode == 0 {
			hasComplete = true
		}
	}
	if got := strings.TrimSpace(stdout); !strings.HasPrefix(got, "/") {
		t.Errorf("pwd output: want a path starting with %q, got %q (events: %+v)", "/", got, events)
	}
	if !hasComplete {
		t.Errorf("complete event with exitCode=0 not found in events: %+v", events)
	}
}

// TestForeignSessionForward は自 stack 以外の session_id prefix を所属 stack へ転送し、
// client 由来の fallback 制御ヘッダを下流へ渡さないことを検証する。
func TestForeignSessionForward(t *testing.T) {
	resetForwardTarget(t)

	headers := map[string]string{
		"X-Fallback-Stack":     "client-stack",
		"X-Fallback-Remaining": "client-remaining",
	}
	resp := doRequestWithHeaders(
		t,
		http.MethodPost,
		nginxBase+"/api/execute",
		`{"command":"pwd"}`,
		"session_id=ap-northeast-3_deadbeef; shell_id=shell-x",
		headers,
	)
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("POST /api/execute foreign session: want 204 from forward target, got %d", resp.StatusCode)
	}

	got := lastForwardedRequest(t)
	if got.Method != http.MethodPost {
		t.Errorf("forwarded method: want POST, got %s", got.Method)
	}
	if got.Path != "/api/execute" {
		t.Errorf("forwarded path: want /api/execute, got %s", got.Path)
	}
	if got.Host != "ap-northeast-3.internal.test" {
		t.Errorf("forwarded Host: want ap-northeast-3.internal.test, got %s", got.Host)
	}
	if values := got.Header["X-Fallback-Stack"]; len(values) > 0 {
		t.Errorf("X-Fallback-Stack should be stripped, got %q", values)
	}
	if values := got.Header["X-Fallback-Remaining"]; len(values) > 0 {
		t.Errorf("X-Fallback-Remaining should be stripped, got %q", values)
	}
}

// TestDeleteShell はセッション削除が 204 を返すことを検証する。
func TestDeleteShell(t *testing.T) {
	cookies := setupSession(t)

	resp := doRequest(t, http.MethodDelete, nginxBase+"/api/shell", "", cookies.cookieHeader())
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Errorf("DELETE /api/shell: want 204, got %d", resp.StatusCode)
	}
}

// --- 異常系テスト ---

// TestExpiredShellCookie は正規の session_id cookie と不正な shell_id cookie で
// コマンド実行した場合に runner が 404 を返すことを検証する。
func TestExpiredShellCookie(t *testing.T) {
	cookies := setupSession(t)

	badCookies := sessionCookies{SessionID: cookies.SessionID, ShellID: "invalid-shell-id"}
	body := `{"command":"pwd"}`
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/execute", body, badCookies.cookieHeader())
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("expected 404 for invalid shell_id, got %d", resp.StatusCode)
	}
}

// TestInvalidSessionCookie は存在しない session_id cookie でリクエストした場合の挙動を検証する。
// broker の resolve-or-create が session_id のセッションを見つけられず、idle runner を新規割り当てする。
// 別の runner に転送されるため、元の shell_id はその runner に存在せず 404 が返る。
// compose 環境では runner を2台起動して本シナリオを成立させる。
func TestInvalidSessionCookie(t *testing.T) {
	// nginx 経由でセッションを作成。runner-1 か runner-2 のどちらかが割り当てられる。
	cookies := createSession(t)
	// もう1台の runner は idle のまま残る。
	// テスト終了時に全 runner をリセットする。
	t.Cleanup(func() { resetRunners(t, cookies.SessionID) })

	// session_id を偽の値に差し替える。shell_id は正規のまま。
	// broker は session_id のセッションを見つけられず、idle の別 runner を新規割り当てする。
	// 別 runner に転送されるが、shell_id はその runner に存在しないため 404。
	fakeCookies := sessionCookies{SessionID: "nonexistent-session-id", ShellID: cookies.ShellID}
	body := `{"command":"pwd"}`
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/execute", body, fakeCookies.cookieHeader())
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("expected 404 for invalid session_id, got %d", resp.StatusCode)
	}
}

// TestInvalidBothCookies は session_id と shell_id の両方が不正な場合の挙動を検証する。
// broker の resolve-or-create が idle runner を新規割り当てするが、
// shell_id もその runner に存在しないため 404 が返る。
func TestInvalidBothCookies(t *testing.T) {
	cookies := createSession(t)
	t.Cleanup(func() { resetRunners(t, cookies.SessionID) })

	fakeCookies := sessionCookies{SessionID: "nonexistent-session-id", ShellID: "nonexistent-shell-id"}
	body := `{"command":"pwd"}`
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/execute", body, fakeCookies.cookieHeader())
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("expected 404 for invalid both cookies, got %d", resp.StatusCode)
	}
}

// TestMissingShellCookie は正規の session_id cookie があるが shell_id cookie がない場合の挙動を検証する。
// broker は session_id のセッションを正常に解決し runner に転送するが、
// runner は shell_id cookie が欠落しているため 400 を返す。
func TestMissingShellCookie(t *testing.T) {
	cookies := setupSession(t)

	// shell_id を空にして session_id のみ送信
	cookie := fmt.Sprintf("session_id=%s", cookies.SessionID)
	body := `{"command":"pwd"}`
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/execute", body, cookie)
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400 for missing shell_id cookie, got %d", resp.StatusCode)
	}
}

// TestExecuteAfterShellDelete は runner の bash シェル削除後に同じ cookie で
// execute した場合に runner が 404 を返すことを検証する。
func TestExecuteAfterShellDelete(t *testing.T) {
	cookies := setupSession(t)

	// runner の bash シェルを削除
	resp := doRequest(t, http.MethodDelete, nginxBase+"/api/shell", "", cookies.cookieHeader())
	resp.Body.Close()

	// 同じ cookie で実行を試みる → runner が shell_id を見つけられず 404
	body := `{"command":"pwd"}`
	resp = doRequest(t, http.MethodPost, nginxBase+"/api/execute", body, cookies.cookieHeader())
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("expected 404 after shell deletion, got %d", resp.StatusCode)
	}
}

// TestExecuteWithoutCookies は Cookie なしで /api/execute を呼び出した場合の挙動を検証する。
// broker の resolve-or-create が新規セッションを作成して runner に転送するが、
// shell_id cookie が欠落しているため runner が 400 を返す。
func TestExecuteWithoutCookies(t *testing.T) {
	body := `{"command":"pwd"}`
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/execute", body, "")
	defer resp.Body.Close()

	// resolve-or-create で作成されたセッションをクリーンアップする
	// nginx の error_page では Set-Cookie が返らないため、レスポンスからは取得できない
	// resetRunners で全 runner を削除・再登録することでセッションを無効化する
	t.Cleanup(func() { resetRunners(t, "") })

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400 for execute without cookies, got %d", resp.StatusCode)
	}
}

// TestNoIdleRunnerExecuteFallbackForward は全ての runner が busy の状態で broker が返す
// fallback headers を nginx が下流 stack へ中継することを検証する。
func TestNoIdleRunnerExecuteFallbackForward(t *testing.T) {
	resetForwardTarget(t)
	cookies1 := createSession(t)
	cookies2 := createSession(t)
	t.Cleanup(func() {
		resetRunners(t, cookies1.SessionID)
		resetRunners(t, cookies2.SessionID)
	})

	fakeCookies := sessionCookies{SessionID: "nonexistent", ShellID: "nonexistent"}
	body := `{"command":"pwd"}`
	resp := doRequest(t, http.MethodPost, nginxBase+"/api/execute", body, fakeCookies.cookieHeader())
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("POST /api/execute no idle runner: want 204 from forward target, got %d", resp.StatusCode)
	}

	got := lastForwardedRequest(t)
	if got.Method != http.MethodPost {
		t.Errorf("forwarded method: want POST, got %s", got.Method)
	}
	if got.Path != "/api/execute" {
		t.Errorf("forwarded path: want /api/execute, got %s", got.Path)
	}
	if got.Host != "ap-northeast-3.internal.test" {
		t.Errorf("forwarded Host: want ap-northeast-3.internal.test, got %s", got.Host)
	}
	if values := got.Header["X-Fallback-Stack"]; len(values) != 1 || values[0] != "ap-northeast-3" {
		t.Errorf("X-Fallback-Stack = %q, want [ap-northeast-3]", values)
	}
	if values := got.Header["X-Fallback-Remaining"]; len(values) > 0 {
		t.Errorf("X-Fallback-Remaining should be empty, got %q", values)
	}
}

// TestDeleteWithExpiredShellCookie は正規の session_id cookie と不正な shell_id cookie で
// DELETE /api/shell を呼び出した場合に runner が 404 を返すことを検証する。
func TestDeleteWithExpiredShellCookie(t *testing.T) {
	cookies := setupSession(t)

	badCookies := sessionCookies{SessionID: cookies.SessionID, ShellID: "invalid-shell-id"}
	resp := doRequest(t, http.MethodDelete, nginxBase+"/api/shell", "", badCookies.cookieHeader())
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("expected 404 for delete with invalid shell_id, got %d", resp.StatusCode)
	}
}

// TestDeleteWithMissingShellCookie は正規の session_id cookie があるが shell_id cookie がない状態で
// DELETE /api/shell を呼び出した場合に runner が 400 を返すことを検証する。
func TestDeleteWithMissingShellCookie(t *testing.T) {
	cookies := setupSession(t)

	cookie := fmt.Sprintf("session_id=%s", cookies.SessionID)
	resp := doRequest(t, http.MethodDelete, nginxBase+"/api/shell", "", cookie)
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400 for delete without shell_id cookie, got %d", resp.StatusCode)
	}
}

// TestNoIdleRunner は全ての runner が busy の状態で broker が返す fallback headers を、
// セッション作成時にも nginx が下流 stack へ中継することを検証する。
func TestNoIdleRunner(t *testing.T) {
	resetForwardTarget(t)
	cookies1 := createSession(t)
	cookies2 := createSession(t)
	t.Cleanup(func() {
		resetRunners(t, cookies1.SessionID)
		resetRunners(t, cookies2.SessionID)
	})

	resp := doRequest(t, http.MethodPost, nginxBase+"/api/shell", "", "")
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("POST /api/shell no idle runner: want 204 from forward target, got %d", resp.StatusCode)
	}

	got := lastForwardedRequest(t)
	if got.Method != http.MethodPost {
		t.Errorf("forwarded method: want POST, got %s", got.Method)
	}
	if got.Path != "/api/shell" {
		t.Errorf("forwarded path: want /api/shell, got %s", got.Path)
	}
	if got.Host != "ap-northeast-3.internal.test" {
		t.Errorf("forwarded Host: want ap-northeast-3.internal.test, got %s", got.Host)
	}
	if values := got.Header["X-Fallback-Stack"]; len(values) != 1 || values[0] != "ap-northeast-3" {
		t.Errorf("X-Fallback-Stack = %q, want [ap-northeast-3]", values)
	}
	if values := got.Header["X-Fallback-Remaining"]; len(values) > 0 {
		t.Errorf("X-Fallback-Remaining should be empty, got %q", values)
	}
}
