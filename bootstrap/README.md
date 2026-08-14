# Bootstrap

This directory has one Terraform module. The module makes the S3 bucket that holds the Terraform state of LinkForge.

Apply this module first. No other module in this repository can work before this bucket exists.

## Why the module started with local state

A Terraform module usually keeps its state in a remote backend. This module could not do this at the start. The backend is the S3 bucket, and the bucket did not exist yet.

Thus the work had two parts:

1. Apply this module with local state. This makes the bucket. ✅
2. Add a `backend "s3"` block. Then move the state into the new bucket. ✅

Both parts are complete. The module now keeps its own state in the bucket that it made, at the key `bootstrap/terraform.tfstate`.

This sequence happens one time only. Every module after this one has a backend from the first day, because the bucket already exists.

## What the module makes

The module has two data sources and six resources.

| Data source | Function |
| --- | --- |
| `aws_caller_identity` | Gives the AWS account ID |
| `aws_iam_policy_document` | Makes the JSON text of the bucket policy |

| Resource | Function |
| --- | --- |
| `aws_s3_bucket` | The bucket. The name includes the account ID |
| `aws_s3_bucket_versioning` | Keeps the old versions of each object |
| `aws_s3_bucket_server_side_encryption_configuration` | Encrypts each object with AES256 |
| `aws_s3_bucket_public_access_block` | Blocks all public access |
| `aws_s3_bucket_lifecycle_configuration` | Removes old object versions after 90 days |
| `aws_s3_bucket_policy` | Denies all requests that do not use TLS |

The bucket name comes from the `aws_caller_identity` data source. Do not write the account ID in the code. A bucket name must be different from all other bucket names in AWS. The account ID makes the name different, and it also lets a second AWS account use the same code.

The five other resources are not arguments of `aws_s3_bucket`. Each one is a different resource, and each one points to the bucket with `bucket = aws_s3_bucket.tfstate.id`. This is the structure of all S3 buckets in this repository.

## Why the module needs each resource

The state file is the record of all infrastructure. A bad apply can make the file incorrect. Old versions let you go back to a good file, thus the module keeps them.

The state file also holds resource IDs and secrets in plain text. Public access and requests without TLS are therefore a risk. The public access block and the bucket policy remove these two risks.

Old versions of the state file increase the cost of the bucket. The lifecycle rule removes a version 90 days after it becomes an old version.

## The bucket policy

The policy has one statement. The statement denies the action `s3:*` when the condition `aws:SecureTransport` is `false`.

Three points in this statement are important:

- The statement gives two resources: the ARN of the bucket, and the same ARN with `/*` at the end. The first ARN is for the actions on the bucket. The second ARN is for the actions on the objects. One ARN alone protects one half only.
- The condition is `Bool` with the value `false`. Do not write the condition as "not true". If the key is not in the request, "not true" denies all access.
- The statement gives `principals` with the type `*`. A deny statement in a resource policy must have a principal. Do not use `not_principals`.

CAUTION: A deny statement is stronger than all allow statements. This includes the policies of the account root user. Read this statement again before you apply the module.

## The outputs

| Output | Function |
| --- | --- |
| `state_bucket_name` | The name of the bucket |
| `state_bucket_arn` | The ARN of the bucket |

A `backend` block cannot read an output. Terraform reads the `backend` block before it calculates the expressions. Thus you must write the bucket name in the `backend` block as plain text.

The output `state_bucket_arn` has a different function. The IAM policies of the GitHub OIDC roles need this ARN. Those roles read the ARN from the state of this module.

## The backend block

The block is in `versions.tf`, inside the `terraform` block. A `backend` block is not a top-level block. It configures Terraform, and not a provider, thus it goes inside `terraform`. A directory accepts one backend block only. This is the reason that one directory has one state file.

| Argument | Value | Function |
| --- | --- | --- |
| `bucket` | `linkforge-tfstate-749000381089` | Plain text. The block cannot read an expression |
| `key` | `bootstrap/terraform.tfstate` | The path of the object in the bucket |
| `region` | `us-east-1` | The region of the bucket, and not the region of the provider |
| `profile` | `dev` | The backend reads its credentials separately from the provider block |
| `use_lockfile` | `true` | S3 gives the lock. This is the reason that the block has no `dynamodb_table` |
| `encrypt` | `true` | Terraform sends the encryption header |

Two arguments need more explanation.

The argument `profile` looks unnecessary, because `providers.tf` already gives the same profile. The backend does not read the provider block. Terraform configures the backend before it starts the provider plugin, thus the two read their credentials separately. Without this argument, `terraform init` uses the default credentials.

The argument `encrypt` also looks unnecessary, because `aws_s3_bucket_server_side_encryption_configuration` already encrypts each object. That resource is correct, and the object is encrypted without this argument. The argument makes the intention visible in the file that the reader examines, and not in a different file.

The value of `key` is a choice for the future. Terragrunt makes this argument from `path_relative_to_include()`. A module at `live/dev/network` thus gets the key `dev/network/terraform.tfstate`. The value `bootstrap/terraform.tfstate` has the same shape.

WARNING: Two modules must never use one key. The key is the identity of a state file. Two modules with one key each delete the resources of the other module.

## The files

```
bootstrap/
├── versions.tf   # The terraform block. Terraform 1.10 or later, AWS provider 6.x, the S3 backend
├── providers.tf  # The provider block. The region and the default tags
├── main.tf       # The two data sources and the six resources
├── outputs.tf    # The name and the ARN of the bucket
└── README.md     # This file
```

Terraform reads all `.tf` files in the directory together. The division into four files is a convention for the reader. Terraform does not use the name of the file or the sequence of the blocks.

## How to apply the module

The module is applied, and its state is in the bucket. Thus you do not repeat this sequence. It is here because it is the sequence that made the bucket, and because no later module can repeat it.

A new copy of this repository does not need these steps. There `terraform init` reads the backend block, finds the state in S3, and the module is ready.

Do the steps in this sequence. Run all commands in the `bootstrap` directory.

1. Start Terraform:

   ```bash
   terraform init
   ```

2. Make the plan file:

   ```bash
   terraform plan -out=bootstrap.tfplan
   ```

3. Read the plan. Terraform must show 6 resources to add.

4. Apply the plan file:

   ```bash
   terraform apply bootstrap.tfplan
   ```

CAUTION: The plan file holds all values of the state in plain text. Do not commit this file to Git. The `.gitignore` file of the repository blocks it.

## How to check the result

Run these commands after the apply.

```bash
B=linkforge-tfstate-749000381089

aws s3api get-bucket-versioning              --bucket $B   # Enabled
aws s3api get-public-access-block            --bucket $B   # 4 values true
aws s3api get-bucket-encryption              --bucket $B   # AES256
aws s3api get-bucket-lifecycle-configuration --bucket $B   # 90 days
```

The bucket policy needs a different test. A normal AWS CLI command always uses TLS, thus it cannot show the deny. Send a request without TLS. AWS must answer with `AccessDenied`:

```bash
aws s3api list-objects-v2 --bucket $B --endpoint-url http://s3.us-east-1.amazonaws.com
```

Then make sure that Git is clean:

```bash
git status   # terraform.tfstate, .terraform/ and *.tfplan must not be in the list
```

## How to check the backend

Run these commands after `terraform init -migrate-state`.

```bash
aws s3api list-objects-v2 --bucket linkforge-tfstate-749000381089   # one object at the key
terraform plan                                                     # "No changes"
terraform state list                                               # the 8 items, now from S3
```

The plan is the important check. A state file that is not complete still gives a result for `terraform state list`. A plan with no changes is the proof that the move lost nothing.

The lock is not in this list, because you cannot see it after the event. Terraform makes the object `bootstrap/terraform.tfstate.tflock` at the start of an operation, and removes it at the end. To see the lock, list the bucket from a second terminal during an apply. The line `Releasing state lock` at the end of a plan is the simpler proof.

## Warning about deletion

The `aws_s3_bucket` resource has the argument `prevent_destroy = true`.

WARNING: A `terraform destroy` command on this module destroys the state of all other modules. The argument `prevent_destroy` stops this command.

The argument also stops all changes that replace the bucket. An example is a change of the bucket name. To make such a change, first remove the argument. Do this only if you accept the result.

## What this module does not do

| Not in this module | Milestone | Why |
| --- | --- | --- |
| A KMS customer key | `v4-state` | AES256 is sufficient for the state file. The module that needs a key makes the key |
| A DynamoDB table for the lock | `v4-state` | S3 gives the lock function with `use_lockfile = true`. The DynamoDB argument is obsolete from Terraform 1.11 |
| The GitHub OIDC provider | `v0-bootstrap`, step 4 | It is a different part of the same milestone |

## Next step

This module is complete. The next step of `v0-bootstrap` is the GitHub OIDC provider, and it is not in this directory.

That step reads `state_bucket_arn` from the state of this module. The plan role and the apply role need write access to the state, thus their policies need the ARN of the bucket and the same ARN with `/*` at the end. This is the same division of the bucket plane and the object plane as the bucket policy above.

One known fault waits in that step. The file `providers.tf` gives `profile = "dev"`, and the backend block gives the same value. GitHub Actions has no profile. A job there receives its credentials from the role that it assumes, in the environment. Both values must become conditional before a workflow can run this module. This fault is the same class as the absent `region` argument earlier: the code works on one machine, because that machine has configuration that the code does not state.
