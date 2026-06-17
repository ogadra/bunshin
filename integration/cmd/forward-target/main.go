package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sync"
)

type recordedRequest struct {
	Method string              `json:"method"`
	Path   string              `json:"path"`
	Host   string              `json:"host"`
	Header map[string][]string `json:"header"`
}

type recorder struct {
	mu  sync.Mutex
	req *recordedRequest
}

func requireEnv(name string) string {
	value := os.Getenv(name)
	if value == "" {
		log.Fatalf("%s environment variable is required", name)
	}
	return value
}

func (r *recorder) set(req *http.Request) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.req = &recordedRequest{
		Method: req.Method,
		Path:   req.URL.RequestURI(),
		Host:   req.Host,
		Header: req.Header.Clone(),
	}
}

func (r *recorder) reset(w http.ResponseWriter, _ *http.Request) {
	r.mu.Lock()
	r.req = nil
	r.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

func (r *recorder) last(w http.ResponseWriter, _ *http.Request) {
	r.mu.Lock()
	req := r.req
	r.mu.Unlock()
	if req == nil {
		http.NotFound(w, nil)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(req); err != nil {
		log.Printf("encode last request: %v", err)
	}
}

func main() {
	rec := &recorder{}

	control := http.NewServeMux()
	control.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	control.HandleFunc("/__reset", rec.reset)
	control.HandleFunc("/__last", rec.last)
	go func() {
		if err := http.ListenAndServe(":8080", control); err != nil {
			log.Fatalf("control server: %v", err)
		}
	}()

	certFile := requireEnv("FORWARD_TARGET_CERT_FILE")
	keyFile := requireEnv("FORWARD_TARGET_KEY_FILE")
	target := http.NewServeMux()
	target.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		rec.set(req)
		w.WriteHeader(http.StatusNoContent)
	})
	srv := &http.Server{
		Addr:    ":443",
		Handler: target,
	}
	if err := srv.ListenAndServeTLS(certFile, keyFile); err != nil {
		log.Fatalf("https server: %v", err)
	}
}
