{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

The vpc chart's own helpers: the module's locals (main.tf), computed once
as JSON so every template renders from the same plan.
*/}}

{{/*
vpc.base: the base every derived Name tag starts with: names.vpc in full,
else the module's name with the namePrefix in front.
*/}}
{{- define "vpc.base" -}}
{{- include "ack.resourceName" (list $ "vpc" "VPC Name tag" .Values.name 256) -}}
{{- end -}}

{{/*
vpc.element: Terraform's element(list, i): the item at i modulo the
list's length. Fails on an empty list, as Terraform does.
  {{ include "vpc.element" (list $list $i "azs") }}
*/}}
{{- define "vpc.element" -}}
{{- $l := index . 0 -}}{{- $i := int (index . 1) -}}
{{- if eq (len $l) 0 -}}
{{- fail (printf "vpc: %s is empty, and a resource needs its item %d (Terraform: element() of an empty list)" (index . 2) $i) -}}
{{- end -}}
{{- index $l (mod $i (len $l)) -}}
{{- end -}}

{{/*
vpc.plan: the module's locals and counts, as JSON:
  create            create_vpc && putin_khuylo
  base              vpc.base
  subnets.<type>    [{i, cidr, az, azField, name, k8s}] for public, private,
                    database, elasticache and intra
  rts.<type>        [{i, name, k8s}] the route tables of each type
  natCount          local.nat_gateway_count
  maxSubnetLength   local.max_subnet_length
*/}}
{{- define "vpc.plan" -}}
{{- $v := .Values -}}
{{- $base := include "vpc.base" . -}}
{{- $p := dict "create" (and $v.create_vpc $v.putin_khuylo) "base" $base -}}
{{- $azs := $v.azs | default list -}}
{{- $subnets := dict -}}
{{- range $t := list "public" "private" "database" "elasticache" "intra" -}}
{{- $cidrs := index $v (printf "%s_subnets" $t) | default list -}}
{{- $names := index $v (printf "%s_subnet_names" $t) | default list -}}
{{- $suffix := index $v (printf "%s_subnet_suffix" $t) -}}
{{- $list := list -}}
{{- range $i, $cidr := $cidrs -}}
{{- $az := include "vpc.element" (list $azs $i "azs") -}}
{{- $name := "" -}}
{{- if lt $i (len $names) -}}
{{- $name = include "ack.cloudName" (list $ "subnet" (index $names $i) 256) -}}
{{- else -}}
{{- $name = include "ack.fit" (list $ "subnet" (printf "%s-%s-%s" $base $suffix $az) 256) -}}
{{- end -}}
{{- $azField := ternary "availabilityZone" "availabilityZoneID" (regexMatch "^[a-z]+-" $az) -}}
{{- $list = append $list (dict "i" $i "cidr" $cidr "az" $az "azField" $azField "name" $name "k8s" (include "ack.name" (list $.Release.Name $t (toString $i)))) -}}
{{- end -}}
{{- $_ := set $subnets $t $list -}}
{{- end -}}
{{- /* The module creates no public subnet when one NAT gateway per AZ has
fewer public subnets than AZs, and then fails associating them. */ -}}
{{- if and $v.one_nat_gateway_per_az (gt (len $subnets.public) 0) (lt (len $subnets.public) (len $azs)) -}}
{{- fail (printf "vpc: one_nat_gateway_per_az needs a public subnet in every AZ: %d public_subnets for %d azs" (len $subnets.public) (len $azs)) -}}
{{- end -}}
{{- $_ := set $p "subnets" $subnets -}}
{{- $lenPublic := len ($v.public_subnets | default list) -}}
{{- $lenPrivate := len $subnets.private -}}
{{- $max := max $lenPublic $lenPrivate (len $subnets.database) (len $subnets.elasticache) -}}
{{- $nat := $max -}}
{{- if $v.single_nat_gateway }}{{ $nat = 1 }}{{ else if $v.one_nat_gateway_per_az }}{{ $nat = len $azs }}{{ end -}}
{{- $_ := set $p "maxSubnetLength" $max -}}
{{- $_ := set $p "natCount" $nat -}}
{{- $rts := dict -}}
{{- /* public: one, or one per subnet */ -}}
{{- $l := list -}}
{{- if gt $lenPublic 0 -}}
{{- $n := ternary $lenPublic 1 $v.create_multiple_public_route_tables -}}
{{- range $i := until (int $n) -}}
{{- $name := printf "%s-%s" $base $v.public_subnet_suffix -}}
{{- if $v.create_multiple_public_route_tables }}{{ $name = printf "%s-%s-%s" $base $v.public_subnet_suffix (include "vpc.element" (list $azs $i "azs")) }}{{ end -}}
{{- $l = append $l (dict "i" $i "name" $name "k8s" (include "ack.name" (list $.Release.Name "public-rt" (toString $i)))) -}}
{{- end -}}
{{- end -}}
{{- $_ := set $rts "public" $l -}}
{{- /* private: as many as NAT gateways */ -}}
{{- $l = list -}}
{{- if and (gt $lenPrivate 0) (gt $max 0) -}}
{{- range $i := until (int $nat) -}}
{{- $name := printf "%s-%s" $base $v.private_subnet_suffix -}}
{{- if not $v.single_nat_gateway }}{{ $name = printf "%s-%s-%s" $base $v.private_subnet_suffix (include "vpc.element" (list $azs $i "azs")) }}{{ end -}}
{{- $l = append $l (dict "i" $i "name" $name "k8s" (include "ack.name" (list $.Release.Name "private-rt" (toString $i)))) -}}
{{- end -}}
{{- end -}}
{{- $_ := set $rts "private" $l -}}
{{- /* database: with create_database_subnet_route_table */ -}}
{{- $l = list -}}
{{- if and (gt (len $subnets.database) 0) $v.create_database_subnet_route_table -}}
{{- $one := or $v.single_nat_gateway $v.create_database_internet_gateway_route -}}
{{- $n := ternary 1 (len $subnets.database) $one -}}
{{- range $i := until (int $n) -}}
{{- $name := printf "%s-%s" $base $v.database_subnet_suffix -}}
{{- if not $one }}{{ $name = printf "%s-%s-%s" $base $v.database_subnet_suffix (include "vpc.element" (list $azs $i "azs")) }}{{ end -}}
{{- $l = append $l (dict "i" $i "name" $name "k8s" (include "ack.name" (list $.Release.Name "database-rt" (toString $i)))) -}}
{{- end -}}
{{- end -}}
{{- $_ := set $rts "database" $l -}}
{{- /* elasticache: one, with create_elasticache_subnet_route_table */ -}}
{{- $l = list -}}
{{- if and (gt (len $subnets.elasticache) 0) $v.create_elasticache_subnet_route_table -}}
{{- $l = append $l (dict "i" 0 "name" (printf "%s-%s" $base $v.elasticache_subnet_suffix) "k8s" (include "ack.name" (list $.Release.Name "elasticache-rt" "0"))) -}}
{{- end -}}
{{- $_ := set $rts "elasticache" $l -}}
{{- /* intra: one, or one per subnet */ -}}
{{- $l = list -}}
{{- if gt (len $subnets.intra) 0 -}}
{{- $n := ternary (len $subnets.intra) 1 $v.create_multiple_intra_route_tables -}}
{{- range $i := until (int $n) -}}
{{- $name := printf "%s-%s" $base $v.intra_subnet_suffix -}}
{{- if $v.create_multiple_intra_route_tables }}{{ $name = printf "%s-%s-%s" $base $v.intra_subnet_suffix (include "vpc.element" (list $azs $i "azs")) }}{{ end -}}
{{- $l = append $l (dict "i" $i "name" $name "k8s" (include "ack.name" (list $.Release.Name "intra-rt" (toString $i)))) -}}
{{- end -}}
{{- end -}}
{{- $_ := set $rts "intra" $l -}}
{{- $_ := set $p "rts" $rts -}}
{{- toJson $p -}}
{{- end -}}

{{/*
vpc.subnetRT: the Kubernetes name of the route table subnet i of a type is
associated with, or "" for none (the VPC's main route table), as the
module's aws_route_table_association resources pick it.
  {{ include "vpc.subnetRT" (list $ $plan "database" $i) }}
*/}}
{{- define "vpc.subnetRT" -}}
{{- $root := index . 0 -}}{{- $p := index . 1 -}}{{- $t := index . 2 -}}{{- $i := int (index . 3) -}}
{{- $v := $root.Values -}}
{{- $rts := index $p.rts $t -}}
{{- $private := $p.rts.private -}}
{{- if eq $t "public" -}}
{{- (index $rts (mod (ternary $i 0 $v.create_multiple_public_route_tables) (len $rts))).k8s -}}
{{- else if eq $t "intra" -}}
{{- (index $rts (mod (ternary $i 0 $v.create_multiple_intra_route_tables) (len $rts))).k8s -}}
{{- else if eq $t "private" -}}
{{- if gt (len $rts) 0 -}}
{{- (index $rts (mod (ternary 0 $i $v.single_nat_gateway) (len $rts))).k8s -}}
{{- end -}}
{{- else if eq $t "database" -}}
{{- $l := ternary $rts $private (gt (len $rts) 0) -}}
{{- if gt (len $l) 0 -}}
{{- $idx := $i -}}
{{- if and $v.create_database_subnet_route_table (or $v.single_nat_gateway $v.create_database_internet_gateway_route) }}{{ $idx = 0 }}{{ end -}}
{{- (index $l (mod $idx (len $l))).k8s -}}
{{- end -}}
{{- else if eq $t "elasticache" -}}
{{- $l := ternary $rts $private (gt (len $rts) 0) -}}
{{- if gt (len $l) 0 -}}
{{- $idx := ternary 0 $i (or $v.single_nat_gateway $v.create_elasticache_subnet_route_table) -}}
{{- (index $l (mod $idx (len $l))).k8s -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
vpc.ref: an ACK reference to an object of this release by its Kubernetes name.
*/}}
{{- define "vpc.ref" -}}
from:
  name: {{ . }}
{{- end -}}
