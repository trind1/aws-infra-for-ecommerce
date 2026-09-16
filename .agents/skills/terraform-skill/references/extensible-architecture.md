# Extensible Terraform Architecture

Use this reference when a Terraform change may add Availability Zones, subnet tiers, route modes, shared services, or new module consumers. The goal is controlled evolution: preserve the selected topology today while keeping likely future changes local, reviewable, and state-safe.

## Contents

- [Design boundary](#design-boundary)
- [Model topology as data](#model-topology-as-data)
- [Stable resource identity](#stable-resource-identity)
- [Tier and route-table design](#tier-and-route-table-design)
- [Module API compatibility](#module-api-compatibility)
- [Validation](#validation)
- [Expansion workflow](#expansion-workflow)
- [Transition test matrix](#transition-test-matrix)

## Design boundary

First record the current topology and the intended change. Extensibility is not a reason to add application subnets, NAT gateways, IPv6, endpoints, or optional flags that the current architecture does not use.

Classify the change:

| Change | Usually local | Usually crosses modules |
|---|---|---|
| Add a subnet in an existing tier | Network module and environment inputs | Consumers only if they assume a fixed count |
| Add an AZ | Network inputs, validations, outputs, capacity assumptions | ALB/ASG/RDS and monitoring may need review |
| Add an application tier | Network, security, compute wiring, database rules | Yes |
| Move compute public → private | Network, compute, bootstrap, egress, security | Yes |
| Add NAT or VPC endpoints | Network, route policy, cost/security review | Often |

Do not claim a topology change is isolated to the network module when its outputs are consumed by compute, load balancers, databases, security groups, or monitoring.

## Model topology as data

Prefer a typed map keyed by a stable role or location when instances have distinct values:

```hcl
variable "public_subnets" {
  description = "Public subnets keyed by Availability Zone."
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
}
```

Avoid APIs made of parallel lists such as `availability_zones`, `public_subnet_cidrs`, and `database_subnet_cidrs` when the module is expected to grow. Parallel lists require positional alignment and make reordering difficult to review.

If an existing public API uses lists, normalize them into objects in a local as an incremental step. Do not change resource keys in the same change unless the state migration is explicitly planned.

For a small fixed architecture, explicit `public_subnets` and `database_subnets` maps are preferable to a single universal `subnet_groups` object. Generalize to a tier map only after at least two tiers genuinely share the same lifecycle and routing model.

## Stable resource identity

Use keys that describe the object and remain stable when input order changes:

- Good: `"us-east-1a"`, `"us-east-1b"`, `"web"`, `"database"`.
- Risky: `"1"`, `"2"` generated from list indexes.
- Invalid for planning: keys derived from resource IDs or other apply-time values.

When moving from `count` to `for_each`, or changing `for_each` keys, classify it as a state migration. Add `moved` blocks where addresses have a deterministic one-to-one mapping and inspect the plan for `moved` operations instead of destroy/create. If the mapping is not safe, stop and prepare an explicit state migration procedure.

Do not use `sort(keys(...))` as a substitute for semantic identity. Sorting makes output deterministic, but it does not make resource addresses stable. If consumers need ordered lists, derive order from an explicit ordered input or expose a map output as the primary contract.

## Tier and route-table design

Keep routing intent visible in the resource model:

- Public tier: route `0.0.0.0/0` to an Internet Gateway and enable public IP assignment only when required by the architecture.
- Private application tier: route egress to NAT or approved endpoints; choose shared or per-AZ route tables deliberately.
- Isolated database tier: omit internet default routes unless a specific requirement justifies them.

Use separate route-table resources for tiers whose lifecycle or route target differs. A route table per AZ is appropriate when each private subnet must use a same-AZ NAT Gateway; one shared table is appropriate for an isolated tier with identical routes. Record the cost, availability, and cross-AZ tradeoff.

For a route model likely to gain multiple routes, prefer separate `aws_route` resources and do not mix them with inline `route` blocks for the same route table. Keep subnet associations derived from the subnet resource collection so the dependency follows the data model.

## Module API compatibility

Treat variables and outputs as public interfaces:

1. Add typed inputs with descriptions and validation.
2. Keep old inputs while consumers migrate, or provide a deliberate breaking-change plan.
3. Add role-based outputs such as `application_subnet_ids` without removing existing `public_subnet_ids` until all consumers are updated.
4. Update the environment composition and every consumer in the same reviewed change when a new tier is enabled.
5. Update README examples and output descriptions to match the actual topology.

Do not expose whole provider objects as outputs. Prefer stable IDs, ARNs, names, and role-based collections.

## Validation

At minimum validate:

- Each collection has the required minimum size for the availability target.
- AZ keys/values are unique and all expected subnet collections cover the same AZ set.
- Every CIDR is syntactically valid.
- Subnet CIDRs are inside the VPC CIDR and do not overlap across tiers.
- Optional features have coherent combinations, such as a private application tier requiring an egress strategy.

Use variable validation for single-input rules. Use cross-variable validation available in the declared Terraform version, `check` blocks, or resource preconditions for relationships between inputs. Never silently truncate lists with `slice` or let an index error be the only validation.

## Expansion workflow

For every architecture expansion:

1. Capture the current topology, module API, consumers, and state addresses.
2. Choose stable keys and decide whether the input API is additive or breaking.
3. Build or update locals that normalize inputs into typed objects.
4. Add resources and associations by role/tier, preserving implicit dependencies.
5. Add or preserve outputs and update all consumers.
6. Add `moved` blocks before changing existing addresses, when required.
7. Run formatting, validation, static security checks, and a saved plan.
8. Review the plan specifically for unintended replacements, cross-AZ routes, public IP exposure, NAT cost, and output ordering.

Do not apply a topology migration directly to production. Retain the reviewed plan artifact and state backup/locking evidence.

## Transition test matrix

Test the current and expected transitions, not only the default happy path:

| Scenario | Expected result |
|---|---|
| Current two-AZ input | No unexpected changes |
| Add one AZ | Only new AZ resources and intended consumer capacity changes |
| Reorder input entries | No subnet replacement when keys are semantic |
| Remove one AZ | Only explicitly removed resources are destroyed |
| Add a new tier | New resources plus deliberate consumer/security changes |
| Disable optional egress | Private resources fail validation rather than silently losing connectivity |
| Rename a resource label | `moved` operation, not destroy/create |

For every transition, inspect both resource addresses and network behavior. A successful `terraform validate` does not prove that the topology or state migration is safe.
