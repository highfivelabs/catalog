// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// vaultroute is the Key Vault data plane of the Azure charts' fake-cloud
// run (hack/azure-mock.sh): every <vault>.vault.azure.net in the kind
// cluster. aso-extensions serves a vault's keys from its fake Resource
// Manager (cmd/fakearm, which holds them as ARM resources) and its secrets
// and certificates from a separate fake vault (cmd/fakevault), so one host
// needs both. vaultroute serves TLS on the host's name and forwards each
// request by its path: keys (/keys, /deletedkeys) to -keys, everything else
// to -secrets, over TLS trusting only -ca, keeping the request's Host (the
// fake Resource Manager reads the vault's name from it).
//
//	vaultroute -listen :443 -cert tls.crt -key tls.key -ca ca.crt \
//	  -keys https://fakearm.fake-cloud.svc -secrets https://fakevault.fake-cloud.svc
package main

import (
	"crypto/tls"
	"crypto/x509"
	"flag"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

func main() {
	listen := flag.String("listen", ":8443", "address to serve TLS on")
	cert := flag.String("cert", "/tls/tls.crt", "server certificate (it must carry *.vault.azure.net)")
	key := flag.String("key", "/tls/tls.key", "server key")
	caFile := flag.String("ca", "", "the CA the upstreams' certificates come from (PEM)")
	keys := flag.String("keys", "", "where keys go (https URL)")
	secrets := flag.String("secrets", "", "where everything else goes (https URL)")
	flag.Parse()

	ca, err := os.ReadFile(*caFile)
	if err != nil {
		log.Fatal(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		log.Fatalf("vaultroute: no certificate in %s", *caFile)
	}
	k, s := mustURL(*keys), mustURL(*secrets)
	tr := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}}
	p := &httputil.ReverseProxy{
		Transport: tr,
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(route(r.In.URL.Path, k, s))
			r.Out.Host = r.In.Host
		},
	}
	logged := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("request %s %s%s -> %s", r.Method, r.Host, r.URL.Path, route(r.URL.Path, k, s).Host)
		p.ServeHTTP(w, r)
	})
	log.Printf("vaultroute on %s: keys to %s, the rest to %s", *listen, k, s)
	log.Fatal(http.ListenAndServeTLS(*listen, *cert, *key, logged))
}

func mustURL(v string) *url.URL {
	u, err := url.Parse(v)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		log.Fatalf("vaultroute: %q: want an https URL", v)
	}
	return u
}

// route is the upstream for a data-plane path: keys for a key's
// operations, secrets for the rest.
func route(path string, keys, secrets *url.URL) *url.URL {
	first, _, _ := strings.Cut(strings.TrimPrefix(path, "/"), "/")
	switch strings.ToLower(first) {
	case "keys", "deletedkeys":
		return keys
	}
	return secrets
}
