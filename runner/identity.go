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

func generateRunnerID(randRead func([]byte) (int, error)) (string, error) {
	var buf [16]byte
	// randRead follows the io.Reader convention where n < len(b) with nil err
	// is legal, so err alone is not enough to reject a partial read that would
	// silently leave the tail zero-filled.
	n, err := randRead(buf[:])
	if err != nil {
		return "", fmt.Errorf("generate runner id: %w", err)
	}
	if n != len(buf) {
		return "", fmt.Errorf("generate runner id: short read %d/%d", n, len(buf))
	}
	return hex.EncodeToString(buf[:]), nil
}

func resolvePrivateURL(ctx context.Context, deps identityDeps) (string, error) {
	if ecsURI := deps.getenv("ECS_CONTAINER_METADATA_URI_V4"); ecsURI != "" {
		return privateURLFromECS(ctx, deps, ecsURI)
	}
	return privateURLFromHostname(deps)
}

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
