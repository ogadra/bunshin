package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// Identity holds the runner registration parameters resolved at startup.
type Identity struct {
	// RunnerID is the unique identifier for this runner.
	RunnerID string
	// PrivateURL is the URL that the broker uses to reach this runner.
	PrivateURL string
}

// identityDeps holds injectable dependencies for identity resolution.
type identityDeps struct {
	getenv   func(string) string
	hostname func() (string, error)
	httpGet  func(ctx context.Context, url string) ([]byte, error)
	randRead func([]byte) (int, error)
	port     string
}

// ecsNetwork represents a single network attachment in ECS container metadata.
type ecsNetwork struct {
	// IPv4Addresses holds the IPv4 addresses assigned to the container.
	IPv4Addresses []string `json:"IPv4Addresses"`
}

// ecsContainerMeta is the subset of fields from GET $ECS_CONTAINER_METADATA_URI_V4.
type ecsContainerMeta struct {
	// Networks holds the network attachments for the container.
	Networks []ecsNetwork `json:"Networks"`
}

// resolveIdentity generates a runnerID via crypto/rand and resolves the
// privateURL from ECS container metadata (when ECS_CONTAINER_METADATA_URI_V4
// is set) or from the container hostname.
func resolveIdentity(ctx context.Context, deps identityDeps) (Identity, error) {
	runnerID, err := generateRunnerID(deps.randRead)
	if err != nil {
		return Identity{}, err
	}
	privateURL, err := resolvePrivateURL(ctx, deps)
	if err != nil {
		return Identity{}, err
	}
	return Identity{RunnerID: runnerID, PrivateURL: privateURL}, nil
}

// generateRunnerID reads 16 random bytes and returns them as a 32-char hex string.
// A short read is treated as an error to avoid a zero-padded runnerID when the
// injected randRead follows the io.Reader convention of returning n < len(b)
// without an error.
func generateRunnerID(randRead func([]byte) (int, error)) (string, error) {
	var buf [16]byte
	n, err := randRead(buf[:])
	if err != nil {
		return "", fmt.Errorf("generate runner id: %w", err)
	}
	if n != len(buf) {
		return "", fmt.Errorf("generate runner id: short read %d/%d", n, len(buf))
	}
	return hex.EncodeToString(buf[:]), nil
}

// resolvePrivateURL determines the privateURL using ECS container metadata
// when available, otherwise falling back to the container hostname.
func resolvePrivateURL(ctx context.Context, deps identityDeps) (string, error) {
	if ecsURI := deps.getenv("ECS_CONTAINER_METADATA_URI_V4"); ecsURI != "" {
		return privateURLFromECS(ctx, deps, ecsURI)
	}
	return privateURLFromHostname(deps)
}

// privateURLFromECS reads the container IPv4 address from ECS container metadata.
func privateURLFromECS(ctx context.Context, deps identityDeps, ecsURI string) (string, error) {
	body, err := deps.httpGet(ctx, ecsURI)
	if err != nil {
		return "", fmt.Errorf("fetch ECS container metadata: %w", err)
	}
	var container ecsContainerMeta
	if err := json.Unmarshal(body, &container); err != nil {
		return "", fmt.Errorf("parse ECS container metadata: %w", err)
	}
	if len(container.Networks) == 0 || len(container.Networks[0].IPv4Addresses) == 0 {
		return "", fmt.Errorf("no IPv4 address in ECS container metadata")
	}
	return "http://" + container.Networks[0].IPv4Addresses[0] + ":" + deps.port, nil
}

// privateURLFromHostname builds the privateURL from os.Hostname.
func privateURLFromHostname(deps identityDeps) (string, error) {
	host, err := deps.hostname()
	if err != nil {
		return "", fmt.Errorf("get hostname: %w", err)
	}
	return "http://" + host + ":" + deps.port, nil
}

// defaultHTTPGet performs an HTTP GET request and returns the response body.
// It is used for fetching ECS metadata from the local endpoint.
func defaultHTTPGet(ctx context.Context, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("metadata endpoint returned %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}
