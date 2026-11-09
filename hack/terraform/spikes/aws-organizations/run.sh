#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Spike: the crossplane-contrib Upjet AWS Organizations family provider in a
# kind cluster, pointed at moto (no AWS credentials exist). Creates an SCP,
# updates it, deletes it, and records what happened and what it cost.
#
#   ../offload/offload run --machine c3d-standard-8 --hours 1 -- \
#     hack/terraform/spikes/aws-organizations/run.sh
#
# Writes offload-artifacts/spike-aws/: log.txt, timings.csv, stats.txt, dumps.
set -uo pipefail

CROSSPLANE_VERSION=${CROSSPLANE_VERSION:-2.4.3}
PROVIDER=${PROVIDER:-xpkg.crossplane.io/crossplane-contrib/provider-aws-organizations:v2.9.0}
MOTO_IMAGE=${MOTO_IMAGE:-motoserver/moto:5.2.5}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
out=$root/offload-artifacts/spike-aws
mkdir -p "$out"
exec > >(tee "$out/log.txt") 2>&1
command -v bc >/dev/null || { printf '#!/bin/sh\npython3 -c "print(round(eval(input()),2))"\n' > /usr/local/bin/bc; chmod +x /usr/local/bin/bc; }
now() { date +%s.%N; }
say() { echo "=== $(date -u +%H:%M:%S) $*"; }
snap() { # name: container stats of the cluster at this moment
  { echo "--- $1 $(date -u +%H:%M:%S)"; docker exec spike-control-plane crictl stats -a 2>/dev/null ; } >> "$out/stats.txt"
}

say "versions"
kind version; kubectl version --client | head -1; helm version --short

say "kind cluster"
t0=$(now)
kind create cluster --name spike --image kindest/node:v1.32.2 --wait 120s
echo "kind create: $(echo "$(now) - $t0" | bc) s"

say "moto"
python3 -m venv /tmp/venv && /tmp/venv/bin/pip -q install boto3 >/dev/null
# moto runs as a container on kind's Docker network (kind load of a multi-platform image fails)
docker run -d --name moto --network kind -p 15000:5000 "$MOTO_IMAGE" >/dev/null
MOTO_IP=$(docker inspect -f '{{ (index .NetworkSettings.Networks "kind").IPAddress }}' moto)
echo "moto at $MOTO_IP"
for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:15000/moto-api/ && break; sleep 1; done
docker logs moto 2>&1 | tail -3
cat > /tmp/moto.py <<'PY'
import boto3, json, sys
c = boto3.client("organizations", endpoint_url="http://127.0.0.1:15000", region_name="us-east-1",
                 aws_access_key_id="test", aws_secret_access_key="test")
cmd = sys.argv[1]
if cmd == "seed":
    c.create_organization(FeatureSet="ALL")
    root = c.list_roots()["Roots"][0]
    c.enable_policy_type(RootId=root["Id"], PolicyType="SERVICE_CONTROL_POLICY")
    print(json.dumps(c.describe_organization()["Organization"], default=str))
elif cmd == "policies":
    ps = c.list_policies(Filter="SERVICE_CONTROL_POLICY")["Policies"]
    out = []
    for p in ps:
        d = c.describe_policy(PolicyId=p["Id"])["Policy"]
        out.append({"name": p["Name"], "id": p["Id"], "aws_managed": p.get("AwsManaged"),
                    "content": d.get("Content")})
    print(json.dumps(out, default=str))
PY
/tmp/venv/bin/python /tmp/moto.py seed

say "crossplane $CROSSPLANE_VERSION"
t0=$(now)
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null
helm install crossplane crossplane-stable/crossplane --namespace crossplane-system --create-namespace \
  --version "$CROSSPLANE_VERSION" --wait --timeout 5m
echo "crossplane install: $(echo "$(now) - $t0" | bc) s"
snap "crossplane only"

say "provider $PROVIDER"
t0=$(now)
kubectl apply -f - <<YAML
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata: {name: fast-poll}
spec:
  deploymentTemplate:
    spec:
      selector: {}
      template:
        spec:
          containers:
          - name: package-runtime
            args: ["--poll=20s", "--debug"]
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata: {name: provider-aws-organizations}
spec:
  package: $PROVIDER
  runtimeConfigRef: {name: fast-poll}
YAML
for i in $(seq 1 90); do
  h=$(kubectl get provider.pkg provider-aws-organizations -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null)
  [ "$h" = True ] && break; sleep 5
done
echo "provider healthy after: $(echo "$(now) - $t0" | bc) s (Healthy=$h)"
kubectl get providers.pkg,providerrevisions.pkg,functions.pkg 2>&1 | tee "$out/packages.txt"
kubectl get pods -A -o wide | tee -a "$out/packages.txt"
kubectl get crd -o name | grep -c 'aws' | sed 's/^/aws CRDs: /'
kubectl get crd -o name | grep -E 'organizations' | tee "$out/crds.txt"
kubectl get crd | grep -E 'providerconfig' | tee -a "$out/crds.txt"
# wait for the CRDs of the family to be established
sleep 20
snap "provider idle"

say "ProviderConfig to moto"
kubectl create secret generic aws-creds -n crossplane-system \
  --from-literal=credentials=$'[default]\naws_access_key_id = test\naws_secret_access_key = test'
sed "s#MOTO_URL#http://$MOTO_IP:5000#" "$here/providerconfig.yaml" | kubectl apply -f - 2>&1 | tee "$out/providerconfig-apply.txt"

say "create SCP"
t_create=$(now)
kubectl get providerconfig.aws.upbound.io default -o yaml > "$out/providerconfig-stored.yaml"
kubectl apply -f "$here/policy.yaml"
ready=""
for i in $(seq 1 120); do
  ready=$(kubectl get policy.organizations.aws.upbound.io spike-deny-leave -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$ready" = True ] && break; sleep 0.5
done
t_ready=$(now)
echo "create: Ready=$ready after $(echo "$t_ready - $t_create" | bc) s"
echo "create,$(echo "$t_ready - $t_create" | bc),$ready" >> "$out/timings.csv"
kubectl get policy.organizations.aws.upbound.io spike-deny-leave -o yaml > "$out/policy-after-create.yaml"
/tmp/venv/bin/python /tmp/moto.py policies | tee "$out/moto-after-create.json"
snap "after create"

say "update SCP (content and description)"
t_upd=$(now)
kubectl apply -f "$here/policy-v2.yaml"
done=""
for i in $(seq 1 120); do
  if /tmp/venv/bin/python /tmp/moto.py policies | grep -q 'organizations:LeaveOrganization.*iam:DeleteUser\|iam:DeleteUser.*organizations:LeaveOrganization'; then done=yes; break; fi
  sleep 0.5
done
t_done=$(now)
echo "update: visible in moto=$done after $(echo "$t_done - $t_upd" | bc) s"
echo "update,$(echo "$t_done - $t_upd" | bc),$done" >> "$out/timings.csv"
sleep 5
kubectl get policy.organizations.aws.upbound.io spike-deny-leave -o yaml > "$out/policy-after-update.yaml"
/tmp/venv/bin/python /tmp/moto.py policies | tee "$out/moto-after-update.json"

say "drift: change the SCP out of band, see whether it is put back"
/tmp/venv/bin/python - <<'PY' | tee "$out/drift.txt"
import boto3, json, time
c = boto3.client("organizations", endpoint_url="http://127.0.0.1:15000", region_name="us-east-1",
                 aws_access_key_id="test", aws_secret_access_key="test")
p = [p for p in c.list_policies(Filter="SERVICE_CONTROL_POLICY")["Policies"] if p["Name"] == "spike-deny-leave"][0]
c.update_policy(PolicyId=p["Id"], Description="changed out of band")
t0 = time.time()
while time.time() - t0 < 120:
    d = c.describe_policy(PolicyId=p["Id"])["Policy"]["PolicySummary"]["Description"]
    if d != "changed out of band":
        print("corrected after %.1f s: %s" % (time.time() - t0, d)); break
    time.sleep(2)
else:
    print("not corrected in 120 s")
PY

say "delete SCP"
t_del=$(now)
kubectl delete -f "$here/policy-v2.yaml" --wait=true --timeout=120s
t_gone=$(now)
echo "delete: object gone after $(echo "$t_gone - $t_del" | bc) s"
echo "delete,$(echo "$t_gone - $t_del" | bc),gone" >> "$out/timings.csv"
/tmp/venv/bin/python /tmp/moto.py policies | tee "$out/moto-after-delete.json"
snap "after delete"

say "provider logs (tail)"
for p in $(kubectl -n crossplane-system get pods -o name | grep provider); do
  kubectl -n crossplane-system logs "$p" --tail=80 > "$out/provider.log" 2>&1
done
tail -40 "$out/provider.log"
kubectl -n crossplane-system get pods -o json | python3 -c "
import json,sys
for p in json.load(sys.stdin)['items']:
    for c in p['spec']['containers']:
        print(p['metadata']['name'], c['name'], c['image'], c.get('resources'))" | tee "$out/pod-resources.txt"
docker exec spike-control-plane crictl images 2>/dev/null | grep -E "provider|crossplane" | tee "$out/images.txt"
docker logs moto > "$out/moto.log" 2>&1
say "done"
