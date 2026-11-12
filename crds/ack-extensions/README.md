# ack-extensions CRDs

The CRDs of ack-extensions kinds the AWS charts render, copied from that
repository so the render tests (`hack/test.sh`) validate them with
`kubeconform -strict`, as they validate ACK's own kinds against the CRDs
of the controllers pinned in `UPSTREAM.md` ("ACK controllers").
ack-extensions' kinds are outside ACK's releases, so a chart renders them
only with `allow_alpha: true` (`docs/design.md`, "Alpha kinds";
`lib/_ack.tpl`, `ack.alpha`).

| File | Kind | Copied from |
| --- | --- | --- |
| `ec2.aws.hfl.dev_customergateways.yaml` | `CustomerGateway` (`ec2.aws.hfl.dev/v1alpha1`) | `config/crds/bases/` at `52556a276e902db1c835e2f7cd3b3d034f0465e8` (2026-11-12) |
| `kms.aws.hfl.dev_replicakeys.yaml` | `ReplicaKey` (`kms.aws.hfl.dev/v1alpha1`) | `config/crds/bases/` at `52556a276e902db1c835e2f7cd3b3d034f0465e8` (2026-11-12) |
| `rds.aws.hfl.dev_optiongroups.yaml` | `OptionGroup` (`rds.aws.hfl.dev/v1alpha1`) | `config/crds/bases/` at `52556a276e902db1c835e2f7cd3b3d034f0465e8` (2026-11-12) |
| `rds.aws.hfl.dev_dbroleassociations.yaml` | `DBRoleAssociation` (`rds.aws.hfl.dev/v1alpha1`) | `config/crds/bases/` at `52556a276e902db1c835e2f7cd3b3d034f0465e8` (2026-11-12) |
