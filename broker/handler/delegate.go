package handler

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/ogadra/20260327-cli-demo/broker/store"
)

type StackTarget struct {
	Stack string
	URL   string
}

type RemoteResolveResult struct {
	SessionID  string
	RunnerURL  string
	Reassigned bool
}

type ResolveClient interface {
	Resolve(ctx context.Context, target StackTarget, sessionID string, delegated bool) (*RemoteResolveResult, error)
}

type HTTPResolveClient struct {
	client *http.Client
}

func NewHTTPResolveClient(client *http.Client) *HTTPResolveClient {
	if client == nil {
		client = http.DefaultClient
	}
	return &HTTPResolveClient{client: client}
}

func (c *HTTPResolveClient) Resolve(ctx context.Context, target StackTarget, sessionID string, delegated bool) (*RemoteResolveResult, error) {
	endpoint, err := resolveEndpoint(target.URL)
	if err != nil {
		return nil, err
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if delegated {
		req.Header.Set(delegatedResolveHeader, "true")
	}
	// 委譲先は自身の BROKER_STACK で session_id に prefix を付与するため、発行スタックは送らない。
	if sessionID != "" {
		req.AddCookie(&http.Cookie{Name: sessionIDCookie, Value: sessionID})
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("delegate resolve: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusServiceUnavailable {
		return nil, store.ErrNoIdleRunner
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("delegate resolve returned status %d", resp.StatusCode)
	}

	result := &RemoteResolveResult{
		SessionID:  sessionID,
		RunnerURL:  resp.Header.Get("X-Runner-Url"),
		Reassigned: resp.Header.Get("X-Session-Reassigned") == "true",
	}
	if result.RunnerURL == "" {
		return nil, fmt.Errorf("delegate resolve missing X-Runner-Url")
	}
	for _, cookie := range resp.Cookies() {
		if cookie.Name == sessionIDCookie {
			result.SessionID = cookie.Value
		}
	}
	return result, nil
}

func resolveEndpoint(base string) (string, error) {
	u, err := url.Parse(strings.TrimSpace(base))
	if err != nil {
		return "", fmt.Errorf("parse delegate url: %w", err)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return "", fmt.Errorf("delegate url scheme must be http or https")
	}
	if u.Host == "" {
		return "", fmt.Errorf("delegate url host is required")
	}
	u.Path = strings.TrimRight(u.Path, "/") + "/resolve"
	u.RawQuery = ""
	u.Fragment = ""
	return u.String(), nil
}
