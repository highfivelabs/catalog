#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Make the Kubernetes Secrets a test case's values reference, with
# throwaway material generated now, in a directory removed on exit. Nothing
# here is committed, logged or printed: the catalog never holds secret
# values (docs/secrets.md), test ones included. In use a Secret comes from
# External Secrets Operator; a test makes its own.
#
#   hack/test-secret.sh NAMESPACE VALUES_FILE   every "# secret: NAME KIND" line
#   hack/test-secret.sh --delete NAMESPACE VALUES_FILE
#
# KIND:
#   pfx     a self-signed certificate (CN catalog.test, RSA 2048, 2 days) as
#           a password-protected PKCS#12, under the keys pfx (its base64, as
#           Application Gateway's sslCertificates data takes it and as
#           External Secrets Operator writes a Key Vault certificate's
#           secret), password, and cer (the certificate's DER base64, as a
#           gateway's trusted root or authentication certificate takes it).
#           3DES PBE and a SHA-1 MAC: what Azure's PFX readers accept.
#   random  32 random bytes as hex under the key value (an API key,
#           a connection string or a SAS URL for the fake cloud, which keeps
#           what it is sent).
# Each Secret is labelled catalog-test=true.
set -o errexit -o nounset -o pipefail
delete=
if [[ "${1:-}" == --delete ]]; then delete=1; shift; fi
[[ $# -eq 2 ]] || { echo "usage: hack/test-secret.sh [--delete] NAMESPACE VALUES_FILE" >&2; exit 2; }
ns="$1" values="$2"
mapfile -t lines < <(sed -n 's/^# secret: *//p' "${values}")
(( ${#lines[@]} > 0 )) || exit 0
for t in kubectl openssl; do
  command -v "$t" >/dev/null || { echo "test-secret: $t is not installed" >&2; exit 2; }
done
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
chmod 700 "${tmp}"
for line in "${lines[@]}"; do
  read -r name kind _ <<<"${line}"
  [[ -n "${name}" && -n "${kind:-}" ]] || { echo "test-secret: ${values}: '# secret: ${line}' is not NAME KIND" >&2; exit 2; }
  if [[ -n "${delete}" ]]; then
    kubectl delete secret -n "${ns}" "${name}" --ignore-not-found >/dev/null
    continue
  fi
  d="${tmp}/${name}"; mkdir -p "${d}"
  case "${kind}" in
    pfx)
      openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=catalog.test" \
        -addext "subjectAltName=DNS:catalog.test" -keyout "${d}/key.pem" -out "${d}/cert.pem" 2>/dev/null
      openssl rand -hex 16 | tr -d '\n' >"${d}/password"
      openssl pkcs12 -export -inkey "${d}/key.pem" -in "${d}/cert.pem" -name catalog-test \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -passout "file:${d}/password" -out "${d}/cert.pfx"
      openssl base64 -A -in "${d}/cert.pfx" >"${d}/pfx"
      openssl x509 -in "${d}/cert.pem" -outform der | openssl base64 -A >"${d}/cer"
      kubectl create secret generic "${name}" -n "${ns}" \
        --from-file=pfx="${d}/pfx" --from-file=password="${d}/password" --from-file=cer="${d}/cer" \
        --dry-run=client -o yaml | kubectl label --local -f - catalog-test=true -o yaml | kubectl apply -f - >/dev/null
      ;;
    random)
      openssl rand -hex 32 | tr -d '\n' >"${d}/value"
      kubectl create secret generic "${name}" -n "${ns}" --from-file=value="${d}/value" \
        --dry-run=client -o yaml | kubectl label --local -f - catalog-test=true -o yaml | kubectl apply -f - >/dev/null
      ;;
    *) echo "test-secret: ${values}: unknown kind ${kind} (pfx, random)" >&2; exit 2 ;;
  esac
  rm -rf "${d}"
  echo "test-secret: made Secret ${ns}/${name} (${kind})"
done
