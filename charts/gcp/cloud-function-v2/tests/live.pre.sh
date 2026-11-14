#!/usr/bin/env bash
# The live case's bundle: a bucket of the run holding fn.zip, a Python
# function that answers "ok" (hack/live-apply.sh runs this before the apply).
tmp="$(mktemp -d)"
printf 'import functions_framework\n\n\n@functions_framework.http\ndef main(request):\n    return "ok"\n' >"${tmp}/main.py"
printf 'functions-framework==3.*\n' >"${tmp}/requirements.txt"
(cd "${tmp}" && python3 -c 'import zipfile; z = zipfile.ZipFile("fn.zip", "w"); z.write("main.py"); z.write("requirements.txt"); z.close()')
gcloud --quiet --project "${PROJECT}" storage buckets create "gs://${PROJECT}-${RUN}-cf" --location "${REGION}" \
  --uniform-bucket-level-access --public-access-prevention --default-storage-class STANDARD
gcloud --quiet --project "${PROJECT}" storage cp "${tmp}/fn.zip" "gs://${PROJECT}-${RUN}-cf/fn.zip"
rm -rf "${tmp}"
