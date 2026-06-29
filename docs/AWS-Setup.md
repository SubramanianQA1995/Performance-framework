# AWS Configuration Guide (for RedLine13 Distributed Load)

RedLine13 launches load-generator EC2 instances **in your own AWS account**
using IAM credentials you provide. This guide covers the minimum, least-
privilege setup. You stated AWS is not configured yet — do these steps when
you are ready to run distributed (cloud) tests. Local execution needs none of
this.

---

## 1. AWS Account Setup

1. Create/identify the AWS account that will host load generators (ideally a
   **dedicated non-prod account** so load-test EC2 cost and blast radius are
   isolated).
2. Pick your primary region (e.g. `us-east-1`) and the additional regions you
   intend to load from (see multi-region table in `RedLine13-Guide.md`).
3. Confirm **EC2 vCPU service quotas** in each region are high enough for your
   largest test. 50k VUs ≈ 25 × `c5.2xlarge` = 200 vCPUs — request a quota
   increase **in advance** (On-Demand Standard instances quota), as new
   accounts default low.

---

## 2. IAM Permissions (least privilege)

Create a dedicated IAM user `redline13-loadgen` with **programmatic access**
(access key + secret). Attach a policy granting only what RedLine13 needs to
launch/terminate generators:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RedLine13LoadGenerators",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeImages",
        "ec2:DescribeKeyPairs",
        "ec2:CreateKeyPair",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeRegions",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    }
  ]
}
```

> Tighten further in production by constraining `Resource`/conditions to
> specific regions, instance types, and a tag (e.g. `Project=ITS-Perf`). Rotate
> the access key regularly and store it only in the RedLine13 account settings.

Add the access key + secret under **RedLine13 → Account → AWS Settings**.

---

## 3. EC2 Requirements

- **AMI:** RedLine13 supplies its own agent AMI per region — you don't build one.
- **Instance types:** see scaling table (`t3.medium` → `c5.2xlarge`). Compute-
  optimised `c5`/`c6i` give the best threads-per-dollar for CPU-bound load gen.
- **Key pair:** RedLine13 can create one; keep it if you want SSH access to a
  generator for debugging.
- **EBS:** default volume is sufficient; load generators are stateless.
- **Lifecycle:** generators are **ephemeral** — launched at test start,
  terminated at test end. Verify termination after each run to avoid cost leaks.
- **Spot (optional):** for large, non-time-critical runs, Spot instances cut
  cost substantially; tolerate occasional generator loss.

---

## 4. Security Groups

Two directions matter:

**A. Generator → SUT (egress / SUT ingress).** The SUT (ITS) must accept
inbound traffic from the generators' public IPs on the app ports (443/80).
- For public endpoints: usually already open.
- For private/internal ITS: whitelist the generator Elastic IPs, or place
  generators in a VPC/subnet peered to the SUT, or use a VPN. Coordinate with
  the network team **before** the test window.

**B. Controller → Generator (management).** RedLine13 needs to reach each
generator. Its launch flow creates/uses a security group allowing the agent's
management port and SSH (22) from RedLine13. Allow this in the IAM policy
(above) so the SG can be created automatically.

```
[RedLine13 Controller] --(mgmt/SSH 22)--> [Generator SG] --(443)--> [ITS SUT SG]
```

> Restrict generator inbound SSH to RedLine13/your office CIDR, not 0.0.0.0/0.

---

## 5. Cost Considerations

You pay AWS directly for generator EC2 time (RedLine13 charges its own
subscription separately). Rough On-Demand estimates (us-east-1, Linux):

| Instance | ~vCPU | ~Approx $/hr | Use |
|---|---:|---:|---|
| `t3.medium`  | 2 | ~$0.04 | small Load/Smoke |
| `c5.large`   | 2 | ~$0.085 | ~1k VUs |
| `c5.xlarge`  | 4 | ~$0.17 | ~5–10k VUs |
| `c5.2xlarge` | 8 | ~$0.34 | 50k VUs tier |

Example: 50k-VU run = 25 × `c5.2xlarge` × 1 hr ≈ **~$8.50 of EC2** for the hour
(prices vary by region/time; verify current pricing). Cost controls:
- Terminate generators promptly; confirm zero running instances post-run.
- Tag everything `Project=ITS-Perf` and set an AWS **Budget + alarm**.
- Prefer fewer, larger generators over many tiny ones for big runs.
- Use Spot for exploratory large runs.
- Keep soak tests on the **smallest** instance count that sustains the target
  rate (long duration multiplies cost).
