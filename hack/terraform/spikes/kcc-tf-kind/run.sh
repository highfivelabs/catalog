#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Spike: add one Terraform-based kind to Config Connector at the pin of
# config-connector-extensions (UPSTREAM.md), the way Config Connector does it:
# a service mapping entry, the CRD generated from the Terraform provider's
# schema, a line in the static controller table. Then build the manager,
# run it against a kind cluster with a real project (SPIKE_PROJECT; it ran
# in hfl-dev-514205 on 2026-11-09), and
# set the project's default network tier through the kind.
#
#   ../offload/offload run --machine n2-standard-16 --hours 2 \
#     --sa cce-live-tests@our-chassis-514316-r0.iam.gserviceaccount.com -- \
#     hack/terraform/spikes/kcc-tf-kind/run.sh
#
# Live GCP only in SPIKE_PROJECT; the tier is read first and put back.
set -uo pipefail

KCC_COMMIT=${KCC_COMMIT:-672414b8191fc2d2c12fff53f6faccf5ae291eef}
PROJECT="${SPIKE_PROJECT:-our-chassis-514316-r0}"
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
out=$root/offload-artifacts/spike-kcc
mkdir -p "$out"
exec > >(tee "$out/log.txt") 2>&1
say() { echo "=== $(date -u +%H:%M:%S) $*"; }
secs() { python3 -c "import time;print(round(time.time()-$1,1))"; }

say "versions"; go version; free -g | head -2; nproc
say "fetch Config Connector $KCC_COMMIT"
t0=$(date +%s); kcc=/tmp/kcc; rm -rf $kcc; mkdir $kcc; cd $kcc
git init -q . && git remote add origin https://github.com/GoogleCloudPlatform/k8s-config-connector.git
git fetch -q --depth 1 origin "$KCC_COMMIT" && git checkout -q FETCH_HEAD
echo "fetched in $(secs $t0) s; checkout $(du -sh . | cut -f1); provider fork $(du -sh third_party/github.com/hashicorp/terraform-provider-google-beta | cut -f1)"
head -3 third_party/github.com/hashicorp/terraform-provider-google-beta/CHANGELOG.md | tee "$out/fork-version.txt"
grep -c '^\s*"google_' third_party/github.com/hashicorp/terraform-provider-google-beta/google-beta/provider/provider.go | sed 's/^/resources registered in the fork: /' | tee -a "$out/fork-version.txt"
for r in google_compute_project_default_network_tier google_project_default_service_accounts google_organization_iam_custom_role google_folder_service_identity google_organization_service_identity; do
  printf '%s in the fork: ' $r; grep -c "\"$r\"" third_party/github.com/hashicorp/terraform-provider-google-beta/google-beta/provider/provider.go
done | tee -a "$out/fork-version.txt"

say "patch: service mapping and static table"
python3 - <<'PY'
import re
p = "config/servicemappings/compute.yaml"
s = open(p).read()
entry = '''    - name: google_compute_project_default_network_tier
      kind: ComputeProjectDefaultNetworkTier
      idTemplate: "{{project}}"
      idTemplateCanBeUsedToMatchResourceName: false
      resourceAvailableInAssetInventory: false
      containers:
        - type: project
          tfField: project
'''
marker = "    - name: google_compute_project_metadata\n"
assert marker in s
open(p, "w").write(s.replace(marker, entry + marker, 1))
p = "pkg/controller/resourceconfig/static_config.go"
s = open(p).read()
line = '\t{Group: "compute.cnrm.cloud.google.com", Kind: "ComputeProjectMetadata"}:'
i = s.index(line)
new = '\t{Group: "compute.cnrm.cloud.google.com", Kind: "ComputeProjectDefaultNetworkTier"}: {DefaultController: k8s.ReconcilerTypeTerraform, SupportedControllers: []k8s.ReconcilerType{k8s.ReconcilerTypeTerraform}},\n'
open(p, "w").write(s[:i] + new + s[i:])
PY
git diff --stat | tee "$out/patch.stat"; git diff > "$out/patch.diff"

say "build generate-crds"
t0=$(date +%s)
go build -o bin/generate-crds ./scripts/generate-crds 2>&1 | tail -20
echo "generate-crds build: $(secs $t0) s ($(ls -l bin/generate-crds | awk '{print $5}') bytes)"
say "generate CRDs from the Terraform schema"
t0=$(date +%s)
./bin/generate-crds -output-dir=/tmp/crds 2>&1 | tail -5
echo "generate-crds run: $(secs $t0) s; $(ls /tmp/crds | wc -l) CRD files"
ls /tmp/crds | grep -i defaultnetworktier | tee "$out/new-crd-name.txt"
f=$(ls /tmp/crds/*computeprojectdefaultnetworktier* 2>/dev/null | head -1)
[ -n "$f" ] && cp "$f" "$out/crd.yaml" && wc -l "$f" && sed -n '/openAPIV3Schema/,$p' "$f" | head -70
# the CRDs of the pin differ from a fresh generation only by kustomize's preserveUnknownFields patch
[ -n "$f" ] && sed -i 's/^spec:/spec:\n  preserveUnknownFields: false/' "$f"

say "build the manager"
t0=$(date +%s)
go build -o bin/manager ./cmd/manager 2>&1 | tail -20
echo "manager build: $(secs $t0) s ($(ls -l bin/manager | awk '{print $5}') bytes)"
ls -l bin/manager | tee "$out/manager-size.txt"

say "kind cluster"
kind create cluster --name kcc --image kindest/node:v1.32.2 --wait 120s >/dev/null 2>&1 && echo up
kubectl create ns cnrm-system
kubectl create ns spike
kubectl annotate ns spike cnrm.cloud.google.com/project-id=$PROJECT
kubectl apply -f "$f" 2>&1 | tail -2
# the CRDs the manager needs to start: try the ones for IAM and the registration/ServiceMapping types first
for g in iampolicies iampartialpolicies iampolicymembers iamauditconfigs; do
  kubectl apply -f config/crds/resources/*customresourcedefinition_${g}.iam.cnrm.cloud.google.com.yaml 2>&1 | tail -1
done

# the manager reads the operator's ConfigConnector object at start (absent is fine, an unknown kind is not)
kubectl apply -f operator/config/crd/bases/core.cnrm.cloud.google.com_configconnectors.yaml 2>&1 | tail -1
kubectl apply -f operator/config/crd/bases/core.cnrm.cloud.google.com_configconnectorcontexts.yaml 2>&1 | tail -1

say "tier before"
orig=$(gcloud compute project-info describe --project $PROJECT --format='value(defaultNetworkTier)' 2>&1)
echo "default network tier before: $orig"
echo "$orig" > "$out/tier-before.txt"

say "run the manager (host process, ADC of the VM's service account)"
mkdir -p /tmp/run && export KUBECONFIG=$HOME/.kube/config POD_NAMESPACE=cnrm-system
./bin/manager --prometheus-scrape-endpoint :8888 > "$out/manager.log" 2>&1 &
mpid=$!
sleep 45
echo "manager alive: $(kill -0 $mpid 2>/dev/null && echo yes || echo no)"
tail -30 "$out/manager.log"
grep -i "registered controller\|defaultnetworktier" "$out/manager.log" | head

say "create the kind (STANDARD)"
cat > /tmp/tier.yaml <<YAML
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeProjectDefaultNetworkTier
metadata:
  name: default
  namespace: spike
  annotations:
    # Config Connector's webhook (not installed here) copies the namespace's annotation onto the object
    cnrm.cloud.google.com/project-id: $PROJECT
spec:
  networkTier: STANDARD
YAML
cp /tmp/tier.yaml "$out/tier.yaml"
t0=$(date +%s.%N)
kubectl apply -f /tmp/tier.yaml
for i in $(seq 1 120); do
  st=$(kubectl -n spike get computeprojectdefaultnetworktier default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$st" = True ] && break; sleep 1
done
echo "create: Ready=$st after $(secs ${t0%.*}) s"
kubectl -n spike get computeprojectdefaultnetworktier default -o yaml > "$out/after-create.yaml"
tail -5 "$out/after-create.yaml"
echo "tier in GCP: $(gcloud compute project-info describe --project $PROJECT --format='value(defaultNetworkTier)')"
ps -o rss,vsz,cmd -p $mpid | tee "$out/manager-rss.txt"

say "put the tier back (PREMIUM), then delete the object"
sed -i 's/STANDARD/PREMIUM/' /tmp/tier.yaml && kubectl apply -f /tmp/tier.yaml
sleep 20
echo "tier in GCP after update: $(gcloud compute project-info describe --project $PROJECT --format='value(defaultNetworkTier)')"
kubectl -n spike delete computeprojectdefaultnetworktier default --timeout=60s 2>&1 | tail -2
echo "tier in GCP after delete: $(gcloud compute project-info describe --project $PROJECT --format='value(defaultNetworkTier)')"
# whatever happened, leave the project as found
now=$(gcloud compute project-info describe --project $PROJECT --format='value(defaultNetworkTier)')
if [ "$now" != "$orig" ] && [ -n "$orig" ]; then
  echo "restoring $orig"; gcloud compute projects set-default-network-tier --project $PROJECT --network-tier "$orig"
fi
echo "tier at the end: $(gcloud compute project-info describe --project $PROJECT --format='value(defaultNetworkTier)')"
ps -o rss -p $mpid | tail -1 | sed 's/^/manager RSS at the end (KiB): /' | tee -a "$out/manager-rss.txt"
tail -40 "$out/manager.log" > "$out/manager-tail.log"
kill $mpid 2>/dev/null
say "done"
exit 0
