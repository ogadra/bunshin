package handler

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ogadra/20260327-cli-demo/broker/store"
)

func TestHTTPResolveClientResolve(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/resolve" || r.Header.Get(delegatedResolveHeader) != "true" {
			t.Fatalf("unexpected request path/header: %s %s", r.URL.Path, r.Header.Get(delegatedResolveHeader))
		}
		if c, err := r.Cookie(sessionIDCookie); err != nil || c.Value != "sess-1" {
			t.Fatalf("session cookie = %v, %v", c, err)
		}
		http.SetCookie(w, &http.Cookie{Name: sessionIDCookie, Value: "apne3-sess-2"})
		w.Header().Set("X-Runner-Url", "http://10.0.3.1:8080")
		w.Header().Set("X-Session-Reassigned", "true")
	}))
	defer srv.Close()

	result, err := NewHTTPResolveClient(srv.Client()).Resolve(context.Background(), StackTarget{Stack: "apne3", URL: srv.URL}, "sess-1", true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if *result != (RemoteResolveResult{SessionID: "apne3-sess-2", RunnerURL: "http://10.0.3.1:8080", Reassigned: true}) {
		t.Fatalf("result = %+v", result)
	}
}

func TestHTTPResolveClientErrors(t *testing.T) {
	t.Parallel()
	closed := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	closedURL := closed.URL
	closed.Close()
	tests := []struct {
		name  string
		url   string
		code  int
		check func(error) bool
	}{
		{"bad url", "ftp://broker", 0, func(err error) bool { return err != nil }},
		{"do error", closedURL, 0, func(err error) bool { return err != nil }},
		{"no idle", "", http.StatusServiceUnavailable, func(err error) bool { return errors.Is(err, store.ErrNoIdleRunner) }},
		{"non ok", "", http.StatusInternalServerError, func(err error) bool { return err != nil }},
		{"missing runner url", "", http.StatusOK, func(err error) bool { return err != nil }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			targetURL := tt.url
			if targetURL == "" {
				srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					w.WriteHeader(tt.code)
				}))
				defer srv.Close()
				targetURL = srv.URL
			}
			_, err := NewHTTPResolveClient(nil).Resolve(context.Background(), StackTarget{URL: targetURL}, "", false)
			if !tt.check(err) {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

func TestResolveEndpoint(t *testing.T) {
	t.Parallel()
	tests := []struct {
		base    string
		want    string
		wantErr bool
	}{
		{"http://broker:8080", "http://broker:8080/resolve", false},
		{"https://broker/base/?x=1#f", "https://broker/base/resolve", false},
		{"http://%zz", "", true},
		{"ftp://broker", "", true},
		{"http:///broker", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.base, func(t *testing.T) {
			t.Parallel()
			got, err := resolveEndpoint(tt.base)
			if (err != nil) != tt.wantErr || got != tt.want {
				t.Fatalf("resolveEndpoint(%q) = %q, %v", tt.base, got, err)
			}
		})
	}
}
