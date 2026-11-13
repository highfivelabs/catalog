{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from cloud-foundation-fabric modules/dataplex-datascan/factory.tf
(v60.0.0), Copyright 2023 Google LLC, Apache-2.0.
*/ -}}
{{/* dataplexDatascan.pick: the value of a factory file's key, in the API's
camelCase or fabric's snake_case, as fabric's try(f.camel, f.snake, null)
reads it; as JSON ({"v": value}). */}}
{{- define "dataplexDatascan.pick" -}}
{{- $m := index . 0 | default dict -}}{{- $camel := index . 1 -}}{{- $snake := index . 2 -}}
{{- $out := dict "v" nil -}}
{{- if and (kindIs "map" $m) (hasKey $m $camel) -}}{{- $_ := set $out "v" (get $m $camel) -}}
{{- else if and (kindIs "map" $m) (hasKey $m $snake) -}}{{- $_ := set $out "v" (get $m $snake) -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/* dataplexDatascan.factory: fabric's local.factory_data, the factory
file normalised to the variable's snake_case shape, as JSON. */}}
{{- define "dataplexDatascan.factory" -}}
{{- $f := . | default dict -}}
{{- $p := "dataplexDatascan.pick" -}}
{{- $rules := list -}}
{{- range $r := ((include $p (list $f "rules" "rules") | fromJson).v | default list) -}}
{{- $o := dict "column" $r.column "dimension" $r.dimension "threshold" $r.threshold -}}
{{- $_ := set $o "ignore_null" (include $p (list $r "ignoreNull" "ignore_null") | fromJson).v -}}
{{- $_ := set $o "non_null_expectation" (include $p (list $r "nonNullExpectation" "non_null_expectation") | fromJson).v -}}
{{- $_ := set $o "uniqueness_expectation" (include $p (list $r "uniquenessExpectation" "uniqueness_expectation") | fromJson).v -}}
{{- range $e := list (list "rangeExpectation" "range_expectation") (list "statisticRangeExpectation" "statistic_range_expectation") -}}
{{- $x := (include $p (list $r (index $e 0) (index $e 1)) | fromJson).v -}}
{{- if not (kindIs "invalid" $x) -}}
{{- $n := dict -}}
{{- range $k := list (list "minValue" "min_value") (list "maxValue" "max_value") (list "strictMinEnabled" "strict_min_enabled") (list "strictMaxEnabled" "strict_max_enabled") (list "statistic" "statistic") -}}
{{- $_ := set $n (index $k 1) (include $p (list $x (index $k 0) (index $k 1)) | fromJson).v -}}
{{- end -}}
{{- if eq (index $e 0) "rangeExpectation" }}{{ $_ := unset $n "statistic" }}{{ end -}}
{{- $_ := set $o (index $e 1) $n -}}
{{- end -}}
{{- end -}}
{{- range $e := list (list "regexExpectation" "regex_expectation" "regex" "regex") (list "setExpectation" "set_expectation" "values" "values") (list "rowConditionExpectation" "row_condition_expectation" "sqlExpression" "sql_expression") (list "tableConditionExpectation" "table_condition_expectation" "sqlExpression" "sql_expression") (list "sqlAssertion" "sql_assertion" "sqlStatement" "sql_statement") -}}
{{- $x := (include $p (list $r (index $e 0) (index $e 1)) | fromJson).v -}}
{{- if not (kindIs "invalid" $x) -}}
{{- $_ := set $o (index $e 1) (dict (index $e 3) (include $p (list $x (index $e 2) (index $e 3)) | fromJson).v) -}}
{{- end -}}
{{- end -}}
{{- $rules = append $rules $o -}}
{{- end -}}
{{- $out := dict "rules" $rules -}}
{{- $_ := set $out "post_scan_actions" (include $p (list $f "postScanActions" "post_scan_actions") | fromJson).v -}}
{{- $_ := set $out "row_filter" (include $p (list $f "rowFilter" "row_filter") | fromJson).v -}}
{{- $_ := set $out "sampling_percent" (include $p (list $f "samplingPercent" "sampling_percent") | fromJson).v -}}
{{- toJson $out -}}
{{- end -}}

{{/* dataplexDatascan.bigqueryExport: a factory file's post scan actions
may be camelCase (bigqueryExport.resultsTable) or snake_case. */}}
{{- define "dataplexDatascan.resultsTable" -}}
{{- $psa := . | default dict -}}
{{- $be := (include "dataplexDatascan.pick" (list $psa "bigqueryExport" "bigquery_export") | fromJson).v -}}
{{- toJson (dict "set" (not (kindIs "invalid" $be)) "v" (include "dataplexDatascan.pick" (list $be "resultsTable" "results_table") | fromJson).v) -}}
{{- end -}}
