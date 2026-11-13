{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

The step-functions chart's own helpers: the names, the module's IAM policy
documents built as Terraform's aws_iam_policy_document builds them (the
statement helper is the sqs chart's, renamed), and the module's map of
service integration policies (locals.tf, aws_service_policies).
*/}}

{{/*
sfn.names: the AWS names, as main.tf derives them, with the namePrefix, or
names.<key> in full. Returns JSON {stateMachine, role, logGroup}.
*/}}
{{- define "sfn.names" -}}
{{- $v := .Values -}}
{{- $sm := include "ack.resourceName" (list $ "stateMachine" "state machine" $v.name 80) -}}
{{- $role := "" -}}
{{- if and $v.create $v.create_role (not $v.use_existing_role) -}}
{{- $role = include "ack.resourceName" (list $ "role" "IAM role" ($v.role_name | default $v.name | default "") 64) -}}
{{- end -}}
{{- $lg := "" -}}
{{- if index ($v.names | default dict) "logGroup" -}}
{{- $lg = include "ack.resourceName" (list $ "logGroup" "log group" "" 512) -}}
{{- else if $v.cloudwatch_log_group_name -}}
{{- $lg = include "ack.cloudName" (list $ "log group" $v.cloudwatch_log_group_name 512) -}}
{{- else -}}
{{- $lg = printf "/aws/vendedlogs/states/%s" $sm -}}
{{- end -}}
{{- toJson (dict "stateMachine" $sm "role" $role "logGroup" $lg) -}}
{{- end -}}

{{/*
sfn.need: a value a chart cannot look up (account_id, region), or fail.
  (list $ "account_id" "why")
*/}}
{{- define "sfn.need" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}
{{- if not (index $root.Values $what) -}}
{{- fail (printf "step-functions: %s is required for %s: the chart cannot look it up (values.yaml)" $what (index . 2)) -}}
{{- end -}}
{{- end -}}

{{/*
sfn.statement: one IAM policy statement as aws_iam_policy_document writes
it, from a dict in the module's shape. Returns JSON.
*/}}
{{- define "sfn.statement" -}}
{{- $s := . -}}
{{- $o := dict "Effect" ($s.effect | default "Allow") -}}
{{- with $s.sid }}{{ $_ := set $o "Sid" . }}{{ end -}}
{{- with $s.actions }}{{ $_ := set $o "Action" . }}{{ end -}}
{{- with $s.not_actions }}{{ $_ := set $o "NotAction" . }}{{ end -}}
{{- with $s.resources }}{{ $_ := set $o "Resource" . }}{{ end -}}
{{- with $s.not_resources }}{{ $_ := set $o "NotResource" . }}{{ end -}}
{{- range $f := list (list "principals" "Principal") (list "not_principals" "NotPrincipal") -}}
{{- $ps := index $s (index $f 0) | default list -}}
{{- if $ps -}}
{{- $m := dict -}}
{{- range $p := $ps -}}
{{- $_ := set $m $p.type (concat (get $m $p.type | default list) $p.identifiers) -}}
{{- end -}}
{{- $_ := set $o (index $f 1) $m -}}
{{- end -}}
{{- end -}}
{{- $conds := $s.condition | default list -}}
{{- if $conds -}}
{{- $c := dict -}}
{{- range $x := $conds -}}
{{- $t := get $c $x.test | default dict -}}
{{- $vals := list -}}
{{- range $x.values }}{{ $vals = append $vals (toString .) }}{{ end -}}
{{- $_ := set $t $x.variable (concat (get $t $x.variable | default list) $vals | uniq) -}}
{{- $_ := set $c $x.test $t -}}
{{- end -}}
{{- $_ := set $o "Condition" $c -}}
{{- end -}}
{{- toJson $o -}}
{{- end -}}

{{/*
sfn.servicePolicies: locals.tf's aws_service_policies at v5.1.1 as JSON,
converted from the module's HCL (keys sorted), with @REGION@ standing for
local.aws_region and @ACCOUNT@ for the caller's account.
*/}}
{{- define "sfn.servicePolicies" -}}
{
 "apigateway": {
  "apigateway": {
   "actions": [
    "execute-api:Invoke"
   ]
  }
 },
 "athena_GetQueryExecution": {
  "athena": {
   "actions": [
    "athena:stopQueryExecution"
   ]
  }
 },
 "athena_GetQueryResults": {
  "athena": {
   "actions": [
    "athena:getQueryResults"
   ]
  },
  "s3": {
   "actions": [
    "s3:GetObject"
   ],
   "default_resources": [
    "arn:aws:s3:::*"
   ]
  }
 },
 "athena_StartQueryExecution": {
  "athena": {
   "actions": [
    "athena:startQueryExecution",
    "athena:getDataCatalog"
   ]
  },
  "glue": {
   "actions": [
    "glue:CreateDatabase",
    "glue:GetDatabase",
    "glue:GetDatabases",
    "glue:UpdateDatabase",
    "glue:DeleteDatabase",
    "glue:CreateTable",
    "glue:UpdateTable",
    "glue:GetTable",
    "glue:GetTables",
    "glue:DeleteTable",
    "glue:BatchDeleteTable",
    "glue:BatchCreatePartition",
    "glue:CreatePartition",
    "glue:UpdatePartition",
    "glue:GetPartition",
    "glue:GetPartitions",
    "glue:BatchGetPartition",
    "glue:DeletePartition",
    "glue:BatchDeletePartition"
   ]
  },
  "lakeformation": {
   "actions": [
    "lakeformation:GetDataAccess"
   ],
   "default_resources": [
    "*"
   ]
  },
  "s3": {
   "actions": [
    "s3:GetBucketLocation",
    "s3:GetObject",
    "s3:ListBucket",
    "s3:ListBucketMultipartUploads",
    "s3:ListMultipartUploadParts",
    "s3:AbortMultipartUpload",
    "s3:CreateBucket",
    "s3:PutObject"
   ],
   "default_resources": [
    "arn:aws:s3:::*"
   ]
  }
 },
 "athena_StartQueryExecution_Sync": {
  "athena": {
   "actions": [
    "athena:startQueryExecution",
    "athena:stopQueryExecution",
    "athena:getQueryExecution",
    "athena:getDataCatalog"
   ]
  },
  "glue": {
   "actions": [
    "glue:CreateDatabase",
    "glue:GetDatabase",
    "glue:GetDatabases",
    "glue:UpdateDatabase",
    "glue:DeleteDatabase",
    "glue:CreateTable",
    "glue:UpdateTable",
    "glue:GetTable",
    "glue:GetTables",
    "glue:DeleteTable",
    "glue:BatchDeleteTable",
    "glue:BatchCreatePartition",
    "glue:CreatePartition",
    "glue:UpdatePartition",
    "glue:GetPartition",
    "glue:GetPartitions",
    "glue:BatchGetPartition",
    "glue:DeletePartition",
    "glue:BatchDeletePartition"
   ]
  },
  "lakeformation": {
   "actions": [
    "lakeformation:GetDataAccess"
   ],
   "default_resources": [
    "*"
   ]
  },
  "s3": {
   "actions": [
    "s3:GetBucketLocation",
    "s3:GetObject",
    "s3:ListBucket",
    "s3:ListBucketMultipartUploads",
    "s3:ListMultipartUploadParts",
    "s3:AbortMultipartUpload",
    "s3:CreateBucket",
    "s3:PutObject"
   ],
   "default_resources": [
    "arn:aws:s3:::*"
   ]
  }
 },
 "athena_StopQueryExecution": {
  "athena": {
   "actions": [
    "athena:stopQueryExecution"
   ]
  }
 },
 "batch_Sync": {
  "batch": {
   "actions": [
    "batch:SubmitJob",
    "batch:DescribeJobs",
    "batch:TerminateJob"
   ],
   "default_resources": [
    "*"
   ]
  },
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ],
   "default_resources": [
    "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventsForBatchJobsRule"
   ]
  }
 },
 "batch_WaitForTaskToken": {
  "batch": {
   "actions": [
    "batch:SubmitJob"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "codebuild_BatchDeleteBuilds": {
  "codebuild": {
   "actions": [
    "codebuild:BatchDeleteBuilds"
   ]
  }
 },
 "codebuild_BatchGetReports": {
  "codebuild": {
   "actions": [
    "codebuild:BatchGetReports"
   ]
  }
 },
 "codebuild_StartBuild": {
  "codebuild": {
   "actions": [
    "codebuild:StartBuild",
    "codebuild:StopBuild",
    "codebuild:BatchGetBuilds"
   ]
  }
 },
 "codebuild_StartBuild_Sync": {
  "codebuild": {
   "actions": [
    "codebuild:StartBuild",
    "codebuild:StopBuild",
    "codebuild:BatchGetBuilds"
   ]
  },
  "default_resources": [
   "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventForCodeBuildStartBuildRule"
  ],
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ]
  }
 },
 "codebuild_StopBuild": {
  "codebuild": {
   "actions": [
    "codebuild:StopBuild"
   ]
  }
 },
 "dynamodb": {
  "dynamodb": {
   "actions": [
    "dynamodb:GetItem",
    "dynamodb:PutItem",
    "dynamodb:UpdateItem",
    "dynamodb:DeleteItem"
   ]
  }
 },
 "ecs_Sync": {
  "ecs": {
   "actions": [
    "ecs:RunTask"
   ]
  },
  "ecs_Wildcard": {
   "actions": [
    "ecs:StopTask",
    "ecs:DescribeTasks"
   ],
   "default_resources": [
    "*"
   ]
  },
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ],
   "default_resources": [
    "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventsForECSTaskRule"
   ]
  },
  "iam_PassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "ecs-tasks.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  }
 },
 "ecs_WaitForTaskToken": {
  "ecs": {
   "actions": [
    "ecs:RunTask"
   ]
  },
  "iam_PassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "ecs-tasks.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  }
 },
 "eks_CreateCluster": {
  "eks": {
   "actions": [
    "eks:CreateCluster"
   ],
   "default_resources": [
    "*"
   ]
  },
  "eks_IamPassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "eks.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  },
  "eks_Wildcard": {
   "actions": [
    "eks:DescribeCluster",
    "eks:DeleteCluster"
   ]
  }
 },
 "eks_CreateNodeGroup": {
  "eks": {
   "actions": [
    "ec2:DescribeSubnets",
    "eks:CreateNodegroup"
   ],
   "default_resources": [
    "*"
   ]
  },
  "eks_IamPassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "eks.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  },
  "eks_Wildcard": {
   "actions": [
    "eks:DescribeNodegroup",
    "eks:DeleteNodegroup"
   ]
  },
  "iam_Role": {
   "actions": [
    "iam:GetRole",
    "iam:ListAttachedRolePolicies"
   ]
  }
 },
 "eks_DeleteCluster": {
  "eks": {
   "actions": [
    "eks:DeleteCluster",
    "eks:DescribeCluster"
   ]
  }
 },
 "eks_DeleteNodegroup": {
  "eks": {
   "actions": [
    "eks:DeleteNodegroup",
    "eks:DescribeNodegroup"
   ]
  }
 },
 "emr_AddStep": {
  "emr": {
   "actions": [
    "elasticmapreduce:AddJobFlowSteps",
    "elasticmapreduce:DescribeStep",
    "elasticmapreduce:CancelSteps"
   ]
  },
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ],
   "default_resources": [
    "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventForEMRAddJobFlowStepsRule"
   ]
  }
 },
 "emr_CancelStep": {
  "emr": {
   "actions": [
    "elasticmapreduce:CancelSteps"
   ]
  }
 },
 "emr_CreateCluster": {
  "emr": {
   "actions": [
    "elasticmapreduce:RunJobFlow",
    "elasticmapreduce:DescribeCluster",
    "elasticmapreduce:TerminateJobFlows"
   ],
   "default_resources": [
    "*"
   ]
  },
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ],
   "default_resources": [
    "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventForEMRRunJobFlowRule"
   ]
  },
  "iam_PassRole": {
   "actions": [
    "iam:PassRole"
   ]
  }
 },
 "emr_ModifyInstanceFleetByName": {
  "emr": {
   "actions": [
    "elasticmapreduce:ModifyInstanceFleet",
    "elasticmapreduce:ListInstanceFleets"
   ]
  }
 },
 "emr_ModifyInstanceGroupByName": {
  "emr": {
   "actions": [
    "elasticmapreduce:ModifyInstanceGroups",
    "elasticmapreduce:ListInstanceGroups"
   ]
  }
 },
 "emr_SetClusterTerminationProtection": {
  "emr": {
   "actions": [
    "elasticmapreduce:SetTerminationProtection"
   ]
  }
 },
 "emr_TerminateCluster": {
  "default_resources": [
   "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventForEMRTerminateJobFlowsRule"
  ],
  "emr": {
   "actions": [
    "elasticmapreduce:TerminateJobFlows",
    "elasticmapreduce:DescribeCluster"
   ]
  },
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ]
  }
 },
 "eventbridge": {
  "eventbridge": {
   "actions": [
    "events:PutEvents"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "glue_Sync": {
  "glue": {
   "actions": [
    "glue:StartJobRun",
    "glue:GetJobRun",
    "glue:GetJobRuns",
    "glue:BatchStopJobRun"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "glue_WaitForTaskToken": {
  "glue": {
   "actions": [
    "glue:StartJobRun"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "lambda": {
  "lambda": {
   "actions": [
    "lambda:InvokeFunction"
   ]
  }
 },
 "no_tasks": {
  "deny_all": {
   "actions": [
    "*"
   ],
   "default_resources": [
    "*"
   ],
   "effect": "Deny"
  }
 },
 "sagemaker_CreateTrainingJob_Sync": {
  "default_resources": [
   "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventsForSageMakerTrainingJobsRule"
  ],
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ]
  },
  "sagemaker": {
   "actions": [
    "sagemaker:CreateTrainingJob",
    "sagemaker:DescribeTrainingJob",
    "sagemaker:StopTrainingJob"
   ]
  },
  "sagemaker_IamPassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "sagemaker.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  },
  "sagemaker_Wildcard": {
   "actions": [
    "sagemaker:ListTags"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "sagemaker_CreateTrainingJob_WaitForTaskToken": {
  "sagemaker": {
   "actions": [
    "sagemaker:CreateTrainingJob"
   ]
  },
  "sagemaker_IamPassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "sagemaker.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  },
  "sagemaker_Wildcard": {
   "actions": [
    "sagemaker:ListTags"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "sagemaker_CreateTransformJob_Sync": {
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ],
   "default_resources": [
    "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventsForSageMakerTransformJobsRule"
   ]
  },
  "sagemaker": {
   "actions": [
    "sagemaker:CreateTransformJob",
    "sagemaker:DescribeTransformJob",
    "sagemaker:StopTransformJob"
   ]
  },
  "sagemaker_IamPassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "sagemaker.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  },
  "sagemaker_Wildcard": {
   "actions": [
    "sagemaker:ListTags"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "sagemaker_CreateTransformJob_WaitForTaskToken": {
  "sagemaker": {
   "actions": [
    "sagemaker:CreateTransformJob"
   ]
  },
  "sagemaker_IamPassRole": {
   "actions": [
    "iam:PassRole"
   ],
   "condition": [
    {
     "test": "StringEquals",
     "values": [
      "sagemaker.amazonaws.com"
     ],
     "variable": "iam:PassedToService"
    }
   ]
  },
  "sagemaker_Wildcard": {
   "actions": [
    "sagemaker:ListTags"
   ],
   "default_resources": [
    "*"
   ]
  }
 },
 "sns": {
  "sns": {
   "actions": [
    "sns:Publish"
   ]
  }
 },
 "sqs": {
  "sqs": {
   "actions": [
    "sqs:SendMessage"
   ]
  }
 },
 "stepfunction": {
  "stepfunction": {
   "actions": [
    "states:StartExecution"
   ]
  }
 },
 "stepfunction_Sync": {
  "events": {
   "actions": [
    "events:PutTargets",
    "events:PutRule",
    "events:DescribeRule"
   ],
   "default_resources": [
    "arn:aws:events:@REGION@:@ACCOUNT@:rule/StepFunctionsGetEventsForStepFunctionsExecutionRule"
   ]
  },
  "stepfunction": {
   "actions": [
    "states:StartSyncExecution"
   ]
  },
  "stepfunction_Wildcard": {
   "actions": [
    "states:DescribeExecution",
    "states:StopExecution"
   ]
  }
 },
 "xray": {
  "xray": {
   "actions": [
    "xray:PutTraceSegments",
    "xray:PutTelemetryRecords",
    "xray:GetSamplingRules",
    "xray:GetSamplingTargets"
   ],
   "default_resources": [
    "*"
   ]
  }
 }
}
{{- end -}}
