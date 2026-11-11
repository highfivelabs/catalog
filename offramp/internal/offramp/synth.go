// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Synthesizing a state offline: for a root module that cannot be applied
// (its permissions are missing), Terraform itself plans it with no cloud
// behind it, and the plan's values become a state. Terraform evaluates the
// modules, so every value a module computes from its inputs is Terraform's;
// only what the cloud would assign (a folder's number, a service account's
// unique ID, a self link) is made up, deterministically, by the rules
// below. Planning again with that state makes the values that depended on
// those (a subfolder's parent) known, until nothing is left to create.
//
// The result is a synthetic state: what an apply would record, less the
// server-side defaults a real state also holds. It is labelled so in every
// report it reaches.

// SynthOptions steer Synthesize.
type SynthOptions struct {
	Root      string   // the root module's directory
	Tfvars    []string // its variables
	Terraform string   // the terraform binary (default: terraform on PATH)
	// Project fills a resource's project when the plan leaves it unknown
	// (taken from the provider's default project).
	Project string
	// Work is a scratch directory (default: a new temporary one).
	Work string
	Log  func(string)
}

// Synthesize plans the root module offline, repeatedly, and returns a
// synthetic state (format 4) holding every resource the plan creates.
func Synthesize(opt SynthOptions) (*State, []byte, error) {
	if opt.Terraform == "" {
		opt.Terraform = "terraform"
	}
	if opt.Log == nil {
		opt.Log = func(string) {}
	}
	work := opt.Work
	if work == "" {
		d, err := os.MkdirTemp("", "offramp-synth-")
		if err != nil {
			return nil, nil, err
		}
		work = d
	}
	files, _ := filepath.Glob(filepath.Join(opt.Root, "*.tf"))
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return nil, nil, err
		}
		if err := os.WriteFile(filepath.Join(work, filepath.Base(f)), b, 0o644); err != nil {
			return nil, nil, err
		}
	}
	var varArgs []string
	for i, tv := range opt.Tfvars {
		b, err := os.ReadFile(tv)
		if err != nil {
			return nil, nil, err
		}
		name := fmt.Sprintf("synth-%d.tfvars", i)
		if err := os.WriteFile(filepath.Join(work, name), b, 0o644); err != nil {
			return nil, nil, err
		}
		varArgs = append(varArgs, "-var-file="+name)
	}
	// A fake Google API for the few reads a plan makes (GKE's versions),
	// and the providers pointed at it with a token that is not one.
	srv, url, err := fakeAPI()
	if err != nil {
		return nil, nil, err
	}
	defer srv.Close()
	providers := detectProviders(work)
	var ov strings.Builder
	for _, p := range providers {
		fmt.Fprintf(&ov, "provider %q {\n  access_token = \"offramp-synthetic\"\n  container_custom_endpoint = %q\n}\n\n", p, url+"/container/")
	}
	if err := os.WriteFile(filepath.Join(work, "offramp_synth_override.tf"), []byte(ov.String()), 0o644); err != nil {
		return nil, nil, err
	}
	tf := func(args ...string) ([]byte, error) {
		cmd := exec.Command(opt.Terraform, append([]string{"-chdir=" + work}, args...)...)
		cmd.Env = append(os.Environ(), "TF_IN_AUTOMATION=1", "GOOGLE_OAUTH_ACCESS_TOKEN=offramp-synthetic")
		var out bytes.Buffer
		cmd.Stdout, cmd.Stderr = &out, &out
		err := cmd.Run()
		return out.Bytes(), err
	}
	if out, err := tf("init", "-input=false", "-no-color"); err != nil {
		return nil, nil, fmt.Errorf("terraform init: %s", tail(out))
	}
	schemaOut, err := tf("providers", "schema", "-json")
	if err != nil {
		return nil, nil, fmt.Errorf("terraform providers schema: %s", tail(schemaOut))
	}
	versions := schemaVersions(schemaOut)
	verOut, _ := tf("version", "-json")
	var ver struct {
		TerraformVersion string `json:"terraform_version"`
	}
	_ = json.Unmarshal(verOut, &ver)

	state := map[string]any{"version": 4, "terraform_version": ver.TerraformVersion, "serial": 1,
		"lineage": "offramp-synthetic", "outputs": map[string]any{}, "resources": []any{}}
	byKey := map[string]map[string]any{}
	var targets []string
	for round := 1; round <= 12; round++ {
		b, _ := json.MarshalIndent(state, "", "  ")
		if err := os.WriteFile(filepath.Join(work, "terraform.tfstate"), b, 0o644); err != nil {
			return nil, nil, err
		}
		args := append([]string{"plan", "-refresh=false", "-input=false", "-no-color", "-lock=false", "-out=synth.plan"}, varArgs...)
		for _, t := range targets {
			args = append(args, "-target="+t)
		}
		out, err := tf(args...)
		if err != nil {
			// A for_each or count over values known only after apply:
			// plan everything else first, as `-target` would by hand.
			bad := unknownKeyModules(out)
			if len(bad) == 0 || len(targets) > 0 {
				return nil, nil, fmt.Errorf("terraform plan (round %d): %s", round, tail(out))
			}
			targets = rootCallsExcept(work, bad)
			opt.Log(fmt.Sprintf("round %d: %s need values known after apply; planning the rest first", round, strings.Join(bad, ", ")))
			continue
		}
		show, err := tf("show", "-json", "synth.plan")
		if err != nil {
			return nil, nil, fmt.Errorf("terraform show: %s", tail(show))
		}
		var plan struct {
			ResourceChanges []struct {
				Address       string `json:"address"`
				ModuleAddress string `json:"module_address"`
				Mode          string `json:"mode"`
				Type          string `json:"type"`
				Name          string `json:"name"`
				Index         any    `json:"index"`
				ProviderName  string `json:"provider_name"`
				Change        struct {
					Actions      []string       `json:"actions"`
					After        map[string]any `json:"after"`
					AfterUnknown map[string]any `json:"after_unknown"`
				} `json:"change"`
			} `json:"resource_changes"`
		}
		if err := json.Unmarshal(show, &plan); err != nil {
			return nil, nil, err
		}
		created := 0
		for _, rc := range plan.ResourceChanges {
			acts := strings.Join(rc.Change.Actions, ",")
			if rc.Mode != "managed" || (acts != "create" && acts != "update" && acts != "delete,create" && acts != "create,delete") {
				continue
			}
			attrs := rc.Change.After
			if attrs == nil {
				attrs = map[string]any{}
			}
			fillUnknown(rc.Type, rc.Address, attrs, rc.Change.AfterUnknown, opt.Project)
			key := rc.ModuleAddress + "|" + rc.Type + "|" + rc.Name
			res := byKey[key]
			if res == nil {
				res = map[string]any{"mode": "managed", "type": rc.Type, "name": rc.Name,
					"provider": `provider["` + rc.ProviderName + `"]`, "instances": []any{}}
				if rc.ModuleAddress != "" {
					res["module"] = rc.ModuleAddress
				}
				byKey[key] = res
				state["resources"] = append(state["resources"].([]any), res)
			}
			in := map[string]any{"schema_version": versions[rc.ProviderName+"|"+rc.Type], "attributes": attrs,
				"sensitive_attributes": []any{}, "private": "bnVsbA=="}
			if rc.Index != nil {
				in["index_key"] = rc.Index
			}
			// An update or a replacement is a resource synthesized in an
			// earlier round: fill in the attributes that were not known
			// then. A resource the provider always shows a diff for (a
			// computed default) changes nothing and does not count.
			var prev map[string]any
			for _, x := range res["instances"].([]any) {
				if fmt.Sprint(x.(map[string]any)["index_key"]) == fmt.Sprint(in["index_key"]) {
					prev = x.(map[string]any)
				}
			}
			if prev == nil {
				res["instances"] = append(res["instances"].([]any), in)
				created++
				continue
			}
			pa := prev["attributes"].(map[string]any)
			changed := false
			for k, v := range attrs {
				if v != nil && (pa[k] == nil || strings.HasPrefix(str(pa[k]), "synthetic/")) {
					pa[k] = v
					changed = true
				}
			}
			if changed {
				created++
			}
		}
		opt.Log(fmt.Sprintf("round %d: %d resources planned or completed", round, created))
		if created == 0 {
			if len(targets) > 0 {
				targets = nil
				continue
			}
			break
		}
	}
	b, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return nil, nil, err
	}
	var st State
	if err := json.Unmarshal(b, &st); err != nil {
		return nil, nil, err
	}
	return &st, b, nil
}

func tail(b []byte) string {
	s := strings.TrimSpace(string(b))
	if i := strings.Index(s, "Error:"); i >= 0 {
		s = s[i:]
	}
	if len(s) > 1200 {
		s = s[:1200]
	}
	return s
}

var providerReq = regexp.MustCompile(`(?m)^\s*(google|google-beta)\s*=\s*\{`)

func detectProviders(dir string) []string {
	seen := map[string]bool{"google": true}
	files, _ := filepath.Glob(filepath.Join(dir, "*.tf"))
	for _, f := range files {
		b, _ := os.ReadFile(f)
		for _, m := range providerReq.FindAllStringSubmatch(string(b), -1) {
			seen[m[1]] = true
		}
	}
	var out []string
	for p := range seen {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

func schemaVersions(b []byte) map[string]any {
	var s struct {
		ProviderSchemas map[string]struct {
			ResourceSchemas map[string]struct {
				Version int `json:"version"`
			} `json:"resource_schemas"`
		} `json:"provider_schemas"`
	}
	out := map[string]any{}
	if json.Unmarshal(b, &s) != nil {
		return out
	}
	for p, ps := range s.ProviderSchemas {
		for t, rs := range ps.ResourceSchemas {
			out[p+"|"+t] = rs.Version
		}
	}
	return out
}

var badModule = regexp.MustCompile(`on \.terraform/modules/([A-Za-z0-9_-]+)/`)

func unknownKeyModules(out []byte) []string {
	if !bytes.Contains(out, []byte("Invalid for_each argument")) && !bytes.Contains(out, []byte("Invalid count argument")) {
		return nil
	}
	seen := map[string]bool{}
	var mods []string
	for _, m := range badModule.FindAllStringSubmatch(string(out), -1) {
		if !seen[m[1]] {
			seen[m[1]] = true
			mods = append(mods, m[1])
		}
	}
	return mods
}

var moduleBlock = regexp.MustCompile(`(?m)^module\s+"([^"]+)"`)

func rootCallsExcept(dir string, bad []string) []string {
	skip := map[string]bool{}
	for _, b := range bad {
		skip[b] = true
	}
	var out []string
	files, _ := filepath.Glob(filepath.Join(dir, "*.tf"))
	for _, f := range files {
		b, _ := os.ReadFile(f)
		for _, m := range moduleBlock.FindAllStringSubmatch(string(b), -1) {
			if !skip[m[1]] {
				out = append(out, "module."+m[1])
			}
		}
	}
	sort.Strings(out)
	return out
}

// fakeAPI answers the reads a plan makes: GKE's server config (the
// versions a cluster may run). Anything else is a 404.
func fakeAPI() (*http.Server, string, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, "", err
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/serverConfig") {
			w.Header().Set("Content-Type", "application/json")
			v := "1.33.5-gke.1000000"
			fmt.Fprintf(w, `{"defaultClusterVersion":%q,"validMasterVersions":[%q],"validNodeVersions":[%q],"defaultImageType":"COS_CONTAINERD",
"channels":[{"channel":"RAPID","defaultVersion":%q,"validVersions":[%q]},{"channel":"REGULAR","defaultVersion":%q,"validVersions":[%q]},{"channel":"STABLE","defaultVersion":%q,"validVersions":[%q]}]}`,
				v, v, v, v, v, v, v, v, v)
			return
		}
		http.Error(w, `{"error":{"code":404,"message":"offramp synth: no fake for `+r.URL.Path+`"}}`, http.StatusNotFound)
	})
	srv := &http.Server{Handler: mux}
	go srv.Serve(ln)
	return srv, "http://" + ln.Addr().String(), nil
}

// number is a made-up, deterministic 12-digit number for an address.
func number(seed string) string {
	h := sha256.Sum256([]byte(seed))
	return fmt.Sprintf("%d", 100000000000+binary.BigEndian.Uint64(h[:8])%899999999999)
}

const computeBase = "https://www.googleapis.com/compute/v1/"

// fillUnknown gives each top-level attribute the plan leaves unknown the
// value the cloud would have assigned, for the kinds the fixtures use;
// anything else unknown stays null (absent), as the converter treats it.
func fillUnknown(typ, addr string, a map[string]any, unknown map[string]any, project string) {
	unk := func(k string) bool { v, _ := unknown[k].(bool); return v }
	set := func(k string, v any) {
		if unk(k) || a[k] == nil {
			a[k] = v
		}
	}
	s := func(k string) string { return str(a[k]) }
	if unk("project") || (a["project"] == nil && project != "" && strings.HasPrefix(typ, "google_compute")) {
		a["project"] = project
	}
	n := number(addr)
	switch typ {
	case "google_folder":
		set("folder_id", n)
		set("name", "folders/"+n)
		set("id", "folders/"+n)
		set("lifecycle_state", "ACTIVE")
	case "google_project":
		set("number", n)
		set("id", "projects/"+s("project_id"))
	case "google_service_account":
		email := s("account_id") + "@" + s("project") + ".iam.gserviceaccount.com"
		set("email", email)
		set("member", "serviceAccount:"+email)
		set("name", "projects/"+s("project")+"/serviceAccounts/"+email)
		set("id", "projects/"+s("project")+"/serviceAccounts/"+email)
		set("unique_id", "1"+n+"0000000")
	case "google_storage_bucket":
		set("id", s("name"))
		set("self_link", "https://www.googleapis.com/storage/v1/b/"+s("name"))
		set("url", "gs://"+s("name"))
	case "google_secret_manager_secret":
		set("id", "projects/"+s("project")+"/secrets/"+s("secret_id"))
		set("name", "projects/"+number(s("project"))+"/secrets/"+s("secret_id"))
	case "google_compute_network":
		id := "projects/" + s("project") + "/global/networks/" + s("name")
		set("id", id)
		set("self_link", computeBase+id)
		set("network_id", n)
		set("numeric_id", n)
	case "google_compute_subnetwork":
		id := "projects/" + s("project") + "/regions/" + s("region") + "/subnetworks/" + s("name")
		set("id", id)
		set("self_link", computeBase+id)
		set("subnetwork_id", n)
	case "google_compute_route":
		id := "projects/" + s("project") + "/global/routes/" + s("name")
		set("id", id)
		set("self_link", computeBase+id)
	case "google_compute_firewall":
		id := "projects/" + s("project") + "/global/firewalls/" + s("name")
		set("id", id)
		set("self_link", computeBase+id)
	case "google_compute_network_firewall_policy":
		id := "projects/" + s("project") + "/global/firewallPolicies/" + s("name")
		set("id", id)
		set("self_link", computeBase+id)
		set("network_firewall_policy_id", n)
	case "google_compute_network_firewall_policy_association":
		set("id", "projects/"+s("project")+"/global/firewallPolicies/"+s("firewall_policy")+"/associations/"+s("name"))
	case "google_compute_network_firewall_policy_rule":
		set("id", fmt.Sprintf("projects/%s/global/firewallPolicies/%s/rules/%s", s("project"), s("firewall_policy"), scalarString(a["priority"])))
	case "google_compute_firewall_policy":
		set("name", n)
		set("firewall_policy_id", n)
		set("id", "locations/global/firewallPolicies/"+n)
		set("self_link", computeBase+"locations/global/firewallPolicies/"+n)
	case "google_compute_firewall_policy_rule":
		set("id", fmt.Sprintf("locations/global/firewallPolicies/%s/rules/%s", s("firewall_policy"), scalarString(a["priority"])))
	case "google_compute_firewall_policy_association":
		set("id", fmt.Sprintf("locations/global/firewallPolicies/%s/associations/%s", s("firewall_policy"), s("name")))
		set("short_name", s("name"))
	case "google_container_cluster":
		id := "projects/" + s("project") + "/locations/" + s("location") + "/clusters/" + s("name")
		set("id", id)
		set("self_link", "https://container.googleapis.com/v1/"+id)
		set("endpoint", "172.16.0.2")
	case "google_container_node_pool":
		set("id", "projects/"+s("project")+"/locations/"+s("location")+"/clusters/"+s("cluster")+"/nodePools/"+s("name"))
	}
	if a["id"] == nil {
		a["id"] = "synthetic/" + addr
	}
}
