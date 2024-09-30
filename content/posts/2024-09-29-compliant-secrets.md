---
layout: post
title: "Implementing Compliant Secrets with AWS Secrets Manager"
date: 2024-09-30
draft: false
author: Oleksandr Kuzminskyi
---

I had a conversation with a colleague other day, and he asked who has access to a specific password.
We use [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html) to store 
secret data and [AWS Identity and Access Management](https://aws.amazon.com/iam/) to control access to it.
Seemingly simple question, it was difficult to answer. I started off with describing how an IAM role can 
have particular permissions on a particular secret, etc. Pretty soon, I realized, that to answer what roles 
can read a secret, one would need to parse every available IAM policy.

The policy might include actions `"secretsmanager:GetSecretValue"` like in an example below:  
```json
{
    "Statement": [
        {
            "Action": "secretsmanager:GetSecretValue",
            "Effect": "Allow",
            "Resource": [
                "arn:aws:secretsmanager:us-west-1:493370826424:secret:packager-passphrase-focal-gzxQPq",
                "arn:aws:secretsmanager:us-west-1:493370826424:secret:packager-key-focal-XrTWrP"
            ]
        },
    ],
    "Version": "2012-10-17"
}
```
It also might include wildcards both in the action - `"secretsmanager:Get*"` - as well as 
in a resource - `"arn:aws:secretsmanager:us-west-1:493370826424:secret:packager-*`. My head was already spinning 
when I thought about cross-account access. There had to be a way to answers that question.

Besides, every security-related certification I had to deal with, required to have a secrets data protection policy
with defined access limitations. An auditor then would ask periodically for a proof of enforcing the policy. Who requested access,
who approved it and when.


## How IAM decides who has permissions

Greatly simplifying [Policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html),
there are two entities.

* IAM Identity. Can be a user or role
* Secret

Both of them have a permission policy. The identity policy tells what the identity may do (say, `secretsmanager:GetSecretValue` of the `packager-key-focal-XrTWrP` secret).
The resource policy (the secret's permission policy) tells what identities can do what operation on the resource.

![Identity-Resource permissions](/images/iam-resource-policy.png)

{{< rawhtml >}}
<table>
<tr>
<th>Identity policy</th><th>Resource policy</th>
</tr>
<tr>
<td>
<div style="width:350px;overflow:auto">
<pre>
{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": [
        "arn:aws:secretsmanager:us-west-1:493370826424:secret:packager-key-focal-XrTWrP"
    ]
}
</pre>
</div>
</td>
<td>
<div style="width:350px;overflow:auto">
<pre>
{
    "Effect" : "Allow",
    "Principal" : {
        "AWS" : [
            "arn:aws:iam::493370826424:role/infrahouse-com-github" ]
        },
    "Action" : [ "secretsmanager:GetSecretValue" ],
    "Resource" : "*"
}
</pre>
</div>
</td>
</tr>
</table>
{{< /rawhtml >}}

See it? The identity policy can allow all permissions in the world, but the role will be able to read the secret 
if and only if the resource policy allows `secretsmanager:GetSecretValue` for 
the role `arn:aws:iam::493370826424:role/infrahouse-com-github`.

## What Resource Policy Do We Want

We established that to control access to a secret, we need to prepare a resource policy that implements controls we need.
Most security standards require access based on a user’s need to know and denying all other access. 

Even though there are about 18 various permissions for the `secretsmanager:*` service, I believe we can categorize them
into three access levels for the sake of simplicity:

* Read permissions:
  * `secretsmanager:BatchGetSecretValue`
  * `secretsmanager:ListSecrets`
  * `secretsmanager:DescribeSecret`
  * `secretsmanager:GetSecretValue`
  * `secretsmanager:GetRandomPassword`
  * `secretsmanager:ListSecretVersionIds`
  * `secretsmanager:GetResourcePolicy`
* Write permissions. All above plus:
  * `secretsmanager:PutSecretValue`
  * `secretsmanager:CancelRotateSecret`
  * `secretsmanager:UpdateSecret`
  * `secretsmanager:RestoreSecret`
  * `secretsmanager:RotateSecret`
  * `secretsmanager:UpdateSecretVersionStage`
* Admin permissions. All above plus:
  * `secretsmanager:CreateSecret`
  * `secretsmanager:DeleteSecret`
  * `secretsmanager:StopReplicationToReplica`
  * `secretsmanager:ReplicateSecretToRegions`
  * `secretsmanager:RemoveRegionsFromReplication`
  * `secretsmanager:DeleteResourcePolicy`
  * `secretsmanager:PutResourcePolicy`
  * `secretsmanager:ValidateResourcePolicy`
  * `secretsmanager:TagResource`
  * `secretsmanager:UntagResource`

So now we know what inputs we need to build the resource policy. That would be a list of IAM roles with access levels for each.     
Or equivalent but more convenient to process - a list of readers, writers, and admins.

There is one more requirement from AWS Secrets Manager and common sense - the role that creates the secret 
and sets its permissions policy must also be admin.

Any other ARN must have no permissions whatsoever.

## Building Resource Policy

Let's take a sample use-case and create a policy for it. Suppose, we have three roles:

* `arn:aws:iam::493370826424:role/ih-tf-aws-control-493370826424-admin` - creates the secret, must be admin.
* `arn:aws:iam::493370826424:role/aws-reserved/sso.amazonaws.com/us-west-1/AWSReservedSSO_AWSAdministratorAccess_a84a03e62f490b50` - writer.
* `arn:aws:iam::493370826424:role/openvpn-portal-20240705183912930900000008` - reader.

Now, when we specify a principal (the IAM role), we need to have a statement for `Allow` actions and for `Deny` actions.
Keep that in mind.

### Rules for Admin

There is only one rule for admin and it's simple - allow all.
```json
{
    "Effect" : "Allow",
    "Principal" : {
      "AWS" : "arn:aws:iam::493370826424:role/ih-tf-aws-control-493370826424-admin"
    },
    "Action" : "*",
    "Resource" : "*"
}
```

### Rules for Writer

For the writer, we need to specify what actions are allowed and deny the rest.
```json
{
    "Effect" : "Allow",
    "Principal" : {
      "AWS" : "arn:aws:iam::493370826424:role/aws-reserved/sso.amazonaws.com/us-west-1/AWSReservedSSO_AWSAdministratorAccess_a84a03e62f490b50"
    },
    "Action" : [
      "secretsmanager:UpdateSecretVersionStage", 
      "secretsmanager:UpdateSecret", 
      "secretsmanager:RotateSecret", 
      "secretsmanager:RestoreSecret", 
      "secretsmanager:PutSecretValue", 
      "secretsmanager:ListSecrets", 
      "secretsmanager:ListSecretVersionIds", 
      "secretsmanager:GetSecretValue", 
      "secretsmanager:GetResourcePolicy", 
      "secretsmanager:GetRandomPassword", 
      "secretsmanager:DescribeSecret", 
      "secretsmanager:CancelRotateSecret", 
      "secretsmanager:BatchGetSecretValue" 
    ],
    "Resource" : "*"
}, 
{
    "Effect" : "Deny",
    "Principal" : {
      "AWS" : "arn:aws:iam::493370826424:role/aws-reserved/sso.amazonaws.com/us-west-1/AWSReservedSSO_AWSAdministratorAccess_a84a03e62f490b50"
    },
    "Action" : [ 
      "secretsmanager:ValidateResourcePolicy", 
      "secretsmanager:UntagResource", 
      "secretsmanager:TagResource", 
      "secretsmanager:StopReplicationToReplica", 
      "secretsmanager:ReplicateSecretToRegions", 
      "secretsmanager:RemoveRegionsFromReplication", 
      "secretsmanager:PutResourcePolicy", 
      "secretsmanager:DeleteSecret", 
      "secretsmanager:DeleteResourcePolicy", 
      "secretsmanager:CreateSecret" 
    ],
    "Resource" : "*"
}
```
### Rules for Reader

Next, we need to create the rules for the reader. There are also two - one `Allow` effect and one - `Deny`.

```json
{
    "Effect" : "Allow",
    "Principal" : {
      "AWS" : "arn:aws:iam::493370826424:role/openvpn-portal-20240705183912930900000008"
    },
    "Action" : [ 
      "secretsmanager:ListSecretVersionIds", 
      "secretsmanager:GetSecretValue", 
      "secretsmanager:GetResourcePolicy", 
      "secretsmanager:GetRandomPassword", 
      "secretsmanager:DescribeSecret" 
    ],
    "Resource" : "*"
}, 
{
    "Effect" : "Deny",
    "Principal" : {
      "AWS" : "arn:aws:iam::493370826424:role/openvpn-portal-20240705183912930900000008"
    },
    "Action" : [ 
      "secretsmanager:ValidateResourcePolicy", 
      "secretsmanager:UpdateSecretVersionStage", 
      "secretsmanager:UpdateSecret", 
      "secretsmanager:UntagResource", 
      "secretsmanager:TagResource", 
      "secretsmanager:StopReplicationToReplica", 
      "secretsmanager:RotateSecret", 
      "secretsmanager:RestoreSecret", 
      "secretsmanager:ReplicateSecretToRegions", 
      "secretsmanager:RemoveRegionsFromReplication", 
      "secretsmanager:PutSecretValue", 
      "secretsmanager:PutResourcePolicy", 
      "secretsmanager:ListSecrets", 
      "secretsmanager:DeleteSecret", 
      "secretsmanager:DeleteResourcePolicy", 
      "secretsmanager:CreateSecret", 
      "secretsmanager:CancelRotateSecret", 
      "secretsmanager:BatchGetSecretValue" 
    ],
    "Resource" : "*"
}
```
### Rules for Every Other Roles

Finally, we need a rule that would deny any access for any other role. The statement reads, 
that if you ain't either of these three roles, all actions are denied.

```json
{
    "Effect" : "Deny",
    "Principal" : {
      "AWS" : "*"
    },
    "Action" : "*",
    "Resource" : "*",
    "Condition" : {
      "StringNotLike" : {
        "aws:PrincipalArn" : [ 
          "arn:aws:iam::493370826424:role/ih-tf-aws-control-493370826424-admin", 
          "arn:aws:iam::493370826424:role/aws-reserved/sso.amazonaws.com/us-west-1/AWSReservedSSO_AWSAdministratorAccess_a84a03e62f490b50", 
          "arn:aws:iam::493370826424:role/openvpn-portal-20240705183912930900000008" 
        ]
      }
    }
  }
```

Here we go. If we concatenate all policy statements above, we'll have a policy that grants different access levels to 
three IAM roles. Any other role won't have any access to the secret.

A tad verbose, isn't it?

## Introducing terraform-aws-secret

Maintaining the resource permission policy statements is error-prone if done directly. The policy logic would get deployed
without tests. Besides, we can't really answer the original question - what roles have access? We still need to 
parse the policy.

The [terraform-aws-secret](https://registry.terraform.io/modules/infrahouse/secret/aws/latest) module puts together
creating the secret, setting its value and permissions policy. It's user and security-compliance friendly.
You can easily tell what role has what access to the secret. Together with GitOps, you can tell who requested the change,
whe approved it, and when it happened.

```hcl
module "api_key" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "~> 0.6"
  secret_description = "API token to some service."
  secret_name        = "API_KEY"
  secret_value       = random_id.api_key.hex
  readers = [
    data.aws_iam_role.sso["Developers"].arn,
    aws_iam_role.ecs_task.arn,
  ]
  writers = [
    data.aws_iam_role.sso["AWSAdministratorAccess"].arn,
  ]
}
```
The module generates dynamically the secret's permission policy from the given roles in the `readers`, `writers`, or
`admins` lists. The generation logic is covered 
with [Terraform unit tests](https://github.com/infrahouse/terraform-aws-secret/blob/main/tests/test_module.py), 
but that's a story for another time.

Meanwhile, give it a star :) on [GitHub](https://github.com/infrahouse/terraform-aws-secret) and let's chat if you have questions.
{{< rawhtml >}}
<!-- Calendly inline widget begin -->
<div class="calendly-inline-widget" data-url="https://calendly.com/akuzminsky" style="min-width:320px;height:700px;"></div>
<script type="text/javascript" src="https://assets.calendly.com/assets/external/widget.js" async></script>
<!-- Calendly inline widget end -->
{{< /rawhtml >}}
