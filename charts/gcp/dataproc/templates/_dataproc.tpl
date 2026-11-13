{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* dataproc.instanceGroup: a master, worker or secondary (fabric's
preemptible) worker group's fields. */}}
{{- define "dataproc.instanceGroup" -}}
numInstances: {{ .num_instances }}
{{- with .machine_type }}
machineType: {{ . | quote }}
{{- end }}
{{- with .min_cpu_platform }}
minCpuPlatform: {{ . | quote }}
{{- end }}
{{- with .preemptibility }}
preemptibility: {{ . | quote }}
{{- end }}
{{- with .image_uri }}
imageRef:
  external: {{ . | quote }}
{{- end }}
{{- with .disk_config }}
diskConfig:
  bootDiskType: {{ .boot_disk_type | quote }}
  bootDiskSizeGb: {{ .boot_disk_size_gb }}
  numLocalSsds: {{ .num_local_ssds }}
{{- end }}
{{- with .accelerators }}
accelerators:
  - acceleratorType: {{ .accelerator_type | quote }}
    acceleratorCount: {{ .accelerator_count }}
{{- end }}
{{- end -}}
