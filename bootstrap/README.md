# Bootstrap

This directory has one Terraform module. The module makes the S3 bucket that holds the Terraform state of LinkForge.

Apply this module first. No other module in this repository can work before this bucket exists.

## Why the module starts with local state

A Terraform module usually keeps its state in a remote backend. This module cannot do this at the start. The backend is the S3 bucket, and the bucket does not exist yet.

Thus the work has two parts:

1. Apply this module with local state. This makes the bucket.
2. Add a `backend "s3"` block. Then move the state into the new bucket.

After part 2, the module keeps its own state in the bucket that it made.

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

## The files

```
bootstrap/
├── versions.tf   # The terraform block. Terraform 1.10 or later, AWS provider 6.x
├── providers.tf  # The provider block. The region and the default tags
├── main.tf       # The two data sources and the six resources
├── outputs.tf    # The name and the ARN of the bucket
└── README.md     # This file
```

Terraform reads all `.tf` files in the directory together. The division into four files is a convention for the reader. Terraform does not use the name of the file or the sequence of the blocks.

## How to apply the module

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

Add a `backend "s3"` block to this module. Give the block the bucket name, the key `bootstrap/terraform.tfstate`, the region, and `use_lockfile = true`. Then move the state:

```bash
terraform init -migrate-state
```

After this command, the module holds its own state in the bucket that it made.
