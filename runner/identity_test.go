package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

// stubRandRead returns a randRead function that fills the destination with
// the given byte, or returns err when non-nil.
func stubRandRead(fill byte, err error) func([]byte) (int, error) {
	return func(b []byte) (int, error) {
		if err != nil {
			return 0, err
		}
		for i := range b {
			b[i] = fill
		}
		return len(b), nil
	}
}

// TestResolveIdentityECS verifies that resolveIdentity generates a random
// runnerID and reads privateURL from ECS container metadata when
// ECS_CONTAINER_METADATA_URI_V4 is set.
func TestResolveIdentityECS(t *testing.T) {
	containerJSON := `{"Networks":[{"IPv4Addresses":["10.0.1.5"]}]}`

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/task" {
			t.Errorf("unexpected request to /task")
		}
		w.Write([]byte(containerJSON))
	}))
	defer ts.Close()

	deps := identityDeps{
		getenv:   func(k string) string { return ts.URL },
		hostname: func() (string, error) { return "", errors.New("should not be called") },
		httpGet:  defaultHTTPGet,
		randRead: stubRandRead(0xab, nil),
		port:     "3000",
	}

	id, err := resolveIdentity(context.Background(), deps)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := "abababababababababababababababab"
	if id.RunnerID != want {
		t.Errorf("RunnerID = %q, want %q", id.RunnerID, want)
	}
	if id.PrivateURL != "http://10.0.1.5:3000" {
		t.Errorf("PrivateURL = %q, want %q", id.PrivateURL, "http://10.0.1.5:3000")
	}
}

// TestResolveIdentityRandReadError verifies that resolveIdentity returns an
// error when the random source fails.
func TestResolveIdentityRandReadError(t *testing.T) {
	deps := identityDeps{
		getenv:   func(k string) string { return "" },
		hostname: func() (string, error) { return "host", nil },
		randRead: stubRandRead(0, errors.New("no entropy")),
		port:     "3000",
	}

	_, err := resolveIdentity(context.Background(), deps)
	if err == nil {
		t.Fatal("expected error when randRead fails")
	}
}

// TestResolveIdentityECSContainerFetchError verifies that resolveIdentity
// returns an error when fetching ECS container metadata fails.
func TestResolveIdentityECSContainerFetchError(t *testing.T) {
	deps := identityDeps{
		getenv: func(k string) string { return "http://169.254.170.2/v4" },
		httpGet: func(ctx context.Context, url string) ([]byte, error) {
			return nil, errors.New("connection refused")
		},
		randRead: stubRandRead(0x01, nil),
		port:     "3000",
	}

	_, err := resolveIdentity(context.Background(), deps)
	if err == nil {
		t.Fatal("expected error when container metadata fetch fails")
	}
}

// TestResolveIdentityECSContainerInvalidJSON verifies that resolveIdentity
// returns an error when ECS container metadata contains invalid JSON.
func TestResolveIdentityECSContainerInvalidJSON(t *testing.T) {
	deps := identityDeps{
		getenv: func(k string) string { return "http://169.254.170.2/v4" },
		httpGet: func(ctx context.Context, url string) ([]byte, error) {
			return []byte("{bad"), nil
		},
		randRead: stubRandRead(0x01, nil),
		port:     "3000",
	}

	_, err := resolveIdentity(context.Background(), deps)
	if err == nil {
		t.Fatal("expected error when container metadata is invalid JSON")
	}
}

// TestResolveIdentityECSEmptyNetworks verifies that resolveIdentity returns
// an error when ECS container metadata has no networks.
func TestResolveIdentityECSEmptyNetworks(t *testing.T) {
	deps := identityDeps{
		getenv: func(k string) string { return "http://169.254.170.2/v4" },
		httpGet: func(ctx context.Context, url string) ([]byte, error) {
			return []byte(`{"Networks":[]}`), nil
		},
		randRead: stubRandRead(0x01, nil),
		port:     "3000",
	}

	_, err := resolveIdentity(context.Background(), deps)
	if err == nil {
		t.Fatal("expected error when Networks is empty")
	}
}

// TestResolveIdentityECSEmptyIPv4 verifies that resolveIdentity returns an
// error when ECS container metadata has a network with no IPv4 addresses.
func TestResolveIdentityECSEmptyIPv4(t *testing.T) {
	deps := identityDeps{
		getenv: func(k string) string { return "http://169.254.170.2/v4" },
		httpGet: func(ctx context.Context, url string) ([]byte, error) {
			return []byte(`{"Networks":[{"IPv4Addresses":[]}]}`), nil
		},
		randRead: stubRandRead(0x01, nil),
		port:     "3000",
	}

	_, err := resolveIdentity(context.Background(), deps)
	if err == nil {
		t.Fatal("expected error when IPv4Addresses is empty")
	}
}

// TestResolveIdentityHostnameFallback verifies that resolveIdentity uses the
// container hostname for privateURL when ECS metadata is not available.
func TestResolveIdentityHostnameFallback(t *testing.T) {
	deps := identityDeps{
		getenv:   func(k string) string { return "" },
		hostname: func() (string, error) { return "runner-host", nil },
		httpGet: func(ctx context.Context, url string) ([]byte, error) {
			return nil, errors.New("should not be called")
		},
		randRead: stubRandRead(0xcd, nil),
		port:     "3000",
	}

	id, err := resolveIdentity(context.Background(), deps)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	wantID := "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
	if id.RunnerID != wantID {
		t.Errorf("RunnerID = %q, want %q", id.RunnerID, wantID)
	}
	if id.PrivateURL != "http://runner-host:3000" {
		t.Errorf("PrivateURL = %q, want %q", id.PrivateURL, "http://runner-host:3000")
	}
}

// TestResolveIdentityHostnameError verifies that resolveIdentity returns an
// error when hostname lookup fails.
func TestResolveIdentityHostnameError(t *testing.T) {
	deps := identityDeps{
		getenv:   func(k string) string { return "" },
		hostname: func() (string, error) { return "", errors.New("no hostname") },
		randRead: stubRandRead(0x01, nil),
		port:     "3000",
	}

	_, err := resolveIdentity(context.Background(), deps)
	if err == nil {
		t.Fatal("expected error when hostname fails")
	}
}

// TestDefaultHTTPGetSuccess verifies that defaultHTTPGet returns the body of
// a successful HTTP response.
func TestDefaultHTTPGetSuccess(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	}))
	defer ts.Close()

	body, err := defaultHTTPGet(context.Background(), ts.URL)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(body) != "ok" {
		t.Errorf("body = %q, want %q", string(body), "ok")
	}
}

// TestDefaultHTTPGetNon200 verifies that defaultHTTPGet returns an error when
// the server responds with a non-200 status code.
func TestDefaultHTTPGetNon200(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer ts.Close()

	_, err := defaultHTTPGet(context.Background(), ts.URL)
	if err == nil {
		t.Fatal("expected error for non-200 response")
	}
}

// TestDefaultHTTPGetCanceledContext verifies that defaultHTTPGet returns an
// error when the context is already canceled.
func TestDefaultHTTPGetCanceledContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := defaultHTTPGet(ctx, "http://127.0.0.1:1/unreachable")
	if err == nil {
		t.Fatal("expected error for canceled context")
	}
}

// TestDefaultHTTPGetInvalidURL verifies that defaultHTTPGet returns an error
// when the URL is malformed and cannot be parsed into a request.
func TestDefaultHTTPGetInvalidURL(t *testing.T) {
	_, err := defaultHTTPGet(context.Background(), "://bad-url")
	if err == nil {
		t.Fatal("expected error for invalid URL")
	}
}
