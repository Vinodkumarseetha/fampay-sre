package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "hodor_requests_total",
		Help: "Total number of requests to hodor",
	}, []string{"method", "path", "status"})

	requestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "hodor_request_duration_seconds",
		Help:    "Duration of HTTP requests",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "path"})
)

type Response struct {
	Service   string    `json:"service"`
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	Host      string    `json:"host"`
	Version   string    `json:"version"`
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		lrw := &loggingResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(lrw, r)
		duration := time.Since(start)

		log.Printf(`{"time":"%s","method":"%s","path":"%s","status":%d,"duration_ms":%d,"remote_addr":"%s"}`,
			time.Now().Format(time.RFC3339),
			r.Method,
			r.URL.Path,
			lrw.statusCode,
			duration.Milliseconds(),
			r.RemoteAddr,
		)

		requestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", lrw.statusCode)).Inc()
		requestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration.Seconds())
	})
}

type loggingResponseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (lrw *loggingResponseWriter) WriteHeader(code int) {
	lrw.statusCode = code
	lrw.ResponseWriter.WriteHeader(code)
}

func hodorHandler(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()
	appEnv := os.Getenv("APP_ENV")
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "1.0.0"
	}

	resp := Response{
		Service:   "hodor",
		Message:   fmt.Sprintf("Hodor! (env: %s)", appEnv),
		Timestamp: time.Now(),
		Host:      hostname,
		Version:   version,
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Service", "hodor")
	json.NewEncoder(w).Encode(resp)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy", "service": "hodor"})
}

func readyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ready", "service": "hodor"})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/hodor/", hodorHandler)
	mux.HandleFunc("/hodor/health", healthHandler)
	mux.HandleFunc("/hodor/ready", readyHandler)
	mux.Handle("/metrics", promhttp.Handler())

	handler := loggingMiddleware(mux)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf(`{"time":"%s","level":"INFO","message":"Hodor service starting on port %s"}`,
		time.Now().Format(time.RFC3339), port)

	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
