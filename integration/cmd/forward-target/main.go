package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"log"
	"math/big"
	"net/http"
	"sync"
	"time"
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

func selfSignedCert() (tls.Certificate, error) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return tls.Certificate{}, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return tls.Certificate{}, err
	}
	tmpl := x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "forward-target"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		DNSNames:     []string{"ap-northeast-3.internal.test", "forward-target"},
		KeyUsage:     x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, &tmpl, &tmpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}
	return tls.Certificate{
		Certificate: [][]byte{der},
		PrivateKey:  key,
	}, nil
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

	cert, err := selfSignedCert()
	if err != nil {
		log.Fatalf("create certificate: %v", err)
	}
	target := http.NewServeMux()
	target.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		rec.set(req)
		w.WriteHeader(http.StatusNoContent)
	})
	srv := &http.Server{
		Addr:      ":443",
		Handler:   target,
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{cert}},
	}
	if err := srv.ListenAndServeTLS("", ""); err != nil {
		log.Fatalf("https server: %v", err)
	}
}
