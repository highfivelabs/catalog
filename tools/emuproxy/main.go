// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// emuproxy puts AWS Emulator (github.com/aws/aws-emulator) behind one plain
// HTTP endpoint for the AWS charts' fake-AWS run (hack/mock-apply-aws.sh),
// as ack-extensions' pkg/test/awsemulator does for its tests.
//
// The emulator serves HTTPS on loopback with a certificate and a key pair
// of its own. The controllers in the kind cluster keep the fake's plain
// endpoint and fake keys: emuproxy takes each request, moves an S3 bucket
// named in the host (virtual-hosted style) into the path, signs the request
// again (Signature Version 4) with the emulator's keys for the service and
// Region the caller signed for, and forwards it over HTTPS, trusting only
// the emulator's certificate and dialling only the emulator's own loopback
// address.
//
//	emuproxy -listen 0.0.0.0:4567 -upstream https://127.0.0.1:PORT \
//	  -ca CA.pem -credentials emulator_credentials -base emulator.fake-aws.svc
package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"
)

var (
	listen   = flag.String("listen", "0.0.0.0:4567", "address to serve plain HTTP on")
	upstream = flag.String("upstream", "", "the emulator's HTTPS URL (loopback)")
	caFile   = flag.String("ca", "", "the emulator's CA certificate (PEM)")
	credFile = flag.String("credentials", "", "the emulator's credentials file (aws_access_key_id, aws_secret_access_key)")
	base     = flag.String("base", "emulator.fake-aws.svc", "the proxy's own host name: a host <bucket>.<base> names an S3 bucket")
)

var (
	credLine  = regexp.MustCompile(`^\s*(aws_access_key_id|aws_secret_access_key)\s*=\s*(\S+)`)
	credScope = regexp.MustCompile(`Credential=[^/]+/\d{8}/([^/]+)/([^/]+)/aws4_request`)
)

func main() {
	flag.Parse()
	up, err := url.Parse(*upstream)
	if err != nil || up.Scheme != "https" {
		log.Fatalf("emuproxy: -upstream %q: want the emulator's https URL", *upstream)
	}
	if ip := net.ParseIP(up.Hostname()); up.Hostname() != "localhost" && (ip == nil || !ip.IsLoopback()) {
		log.Fatalf("emuproxy: -upstream %q is not loopback: refusing", *upstream)
	}
	ca, err := os.ReadFile(*caFile)
	if err != nil {
		log.Fatal(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		log.Fatalf("emuproxy: no certificate in %s", *caFile)
	}
	akid, secret, err := readCredentials(*credFile)
	if err != nil {
		log.Fatal(err)
	}
	p := &proxy{up: up, akid: akid, secret: secret, client: newClient(up.Host, pool)}
	log.Printf("emuproxy: %s -> %s", *listen, up)
	log.Fatal(http.ListenAndServe(*listen, p))
}

func newClient(addr string, pool *x509.CertPool) *http.Client {
	d := &net.Dialer{Timeout: 10 * time.Second}
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12},
	}
	tr.DialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
		return d.DialContext(ctx, "tcp", addr)
	}
	return &http.Client{
		Timeout:       120 * time.Second,
		Transport:     tr,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
}

func readCredentials(path string) (string, string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", "", err
	}
	var id, secret string
	for _, l := range strings.Split(string(b), "\n") {
		if m := credLine.FindStringSubmatch(l); m != nil {
			if m[1] == "aws_access_key_id" {
				id = m[2]
			} else {
				secret = m[2]
			}
		}
	}
	if id == "" || secret == "" {
		return "", "", fmt.Errorf("%s: no key pair", path)
	}
	return id, secret, nil
}

type proxy struct {
	up           *url.URL
	akid, secret string
	client       *http.Client
}

func (p *proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	region, service := "us-east-1", ""
	if m := credScope.FindStringSubmatch(r.Header.Get("Authorization")); m != nil {
		region, service = m[1], m[2]
	}
	path := r.URL.EscapedPath()
	if path == "" {
		path = "/"
	}
	// <bucket>.<base>[:port]: S3's virtual-hosted style, into the path.
	host := strings.ToLower(r.Host)
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	host = strings.TrimSuffix(strings.TrimSuffix(host, "."), ".cluster.local")
	if b, ok := strings.CutSuffix(host, "."+*base); ok && b != "" {
		path = "/" + b + strings.TrimSuffix(path, "/")
		if path == "/"+b {
			path += "/"
		}
	}
	out, err := http.NewRequestWithContext(r.Context(), r.Method, p.up.Scheme+"://"+p.up.Host+path+query(r.URL.RawQuery), bytes.NewReader(body))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	for k, vs := range r.Header {
		switch strings.ToLower(k) {
		case "authorization", "x-amz-date", "x-amz-security-token", "x-amz-content-sha256", "host", "content-length", "connection", "accept-encoding":
			continue
		}
		out.Header[k] = vs
	}
	out.ContentLength = int64(len(body))
	if service != "" {
		sign(out, body, p.akid, p.secret, region, service, time.Now().UTC())
	}
	resp, err := p.client.Do(out)
	if err != nil {
		log.Printf("emuproxy: %s %s: %v", r.Method, path, err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	for k, vs := range resp.Header {
		w.Header()[k] = vs
	}
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
	log.Printf("emuproxy: %s %s %s %s -> %d", service, region, r.Method, path, resp.StatusCode)
}

func query(raw string) string {
	if raw == "" {
		return ""
	}
	return "?" + raw
}

// sign signs req with Signature Version 4 (header auth, the payload's
// SHA-256 in x-amz-content-sha256).
func sign(req *http.Request, body []byte, akid, secret, region, service string, now time.Time) {
	amzDate := now.Format("20060102T150405Z")
	day := now.Format("20060102")
	sum := sha256.Sum256(body)
	payload := hex.EncodeToString(sum[:])
	req.Header.Set("X-Amz-Date", amzDate)
	req.Header.Set("X-Amz-Content-Sha256", payload)
	req.Host = req.URL.Host

	names := []string{"host"}
	vals := map[string]string{"host": req.URL.Host}
	for k, vs := range req.Header {
		lk := strings.ToLower(k)
		if lk == "content-type" || lk == "content-md5" || strings.HasPrefix(lk, "x-amz-") {
			names = append(names, lk)
			trimmed := make([]string, len(vs))
			for i, v := range vs {
				trimmed[i] = strings.Join(strings.Fields(v), " ")
			}
			vals[lk] = strings.Join(trimmed, ",")
		}
	}
	sort.Strings(names)
	var ch strings.Builder
	for _, n := range names {
		ch.WriteString(n + ":" + vals[n] + "\n")
	}
	signed := strings.Join(names, ";")

	uri := req.URL.EscapedPath()
	if uri == "" {
		uri = "/"
	}
	if service != "s3" {
		// Every other service's canonical URI is encoded twice.
		uri = strings.ReplaceAll(uri, "%", "%25")
	}
	canonical := strings.Join([]string{req.Method, uri, canonicalQuery(req.URL.Query()), ch.String(), signed, payload}, "\n")
	cs := sha256.Sum256([]byte(canonical))
	scope := day + "/" + region + "/" + service + "/aws4_request"
	toSign := "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" + hex.EncodeToString(cs[:])
	k := hmacSHA256([]byte("AWS4"+secret), day)
	k = hmacSHA256(k, region)
	k = hmacSHA256(k, service)
	k = hmacSHA256(k, "aws4_request")
	sig := hex.EncodeToString(hmacSHA256(k, toSign))
	req.Header.Set("Authorization", "AWS4-HMAC-SHA256 Credential="+akid+"/"+scope+", SignedHeaders="+signed+", Signature="+sig)
}

func canonicalQuery(q url.Values) string {
	var parts []string
	for k, vs := range q {
		for _, v := range vs {
			parts = append(parts, awsEscape(k)+"="+awsEscape(v))
		}
	}
	sort.Strings(parts)
	return strings.Join(parts, "&")
}

// awsEscape is RFC 3986 percent-encoding: everything but A-Z a-z 0-9 - _ . ~.
func awsEscape(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == '~' {
			b.WriteByte(c)
		} else {
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}

func hmacSHA256(key []byte, s string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(s))
	return h.Sum(nil)
}
