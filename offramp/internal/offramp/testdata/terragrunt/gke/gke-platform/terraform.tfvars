# The inputs Terragrunt passes the gke/cluster unit (root.hcl's and the
# unit's own), as tfvars for offramp synth.
project_id = "ofr-test-project"
region     = "us-central1"
prefix     = "ofr-test"
owner      = "platform"
nodes_cidr = "10.40.0.0/24"
