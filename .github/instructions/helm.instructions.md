---
applyTo: "helm_charts/**"
description: "Helm chart conventions for CARE application Kubernetes deployments"
---

# Helm Chart Conventions

## Chart Structure

Each chart under `helm_charts/` contains:

| File | Purpose |
|------|---------|
| `Chart.yaml` | Chart metadata |
| `values.yaml` | Default values (overridden by Terraform-generated values) |
| `templates/_helpers.tpl` | Shared naming and label helpers |
| `templates/*.yaml` | Workload, service, and routing templates |

Current charts: `gateway`, `redis`, `metabase`, `care_be`, `care_fe`, `dcm4chee`, `care_metrics_exporter`.

## Common Helpers

All charts implement an identical set of helper templates in `_helpers.tpl`:

| Helper | Purpose |
|--------|---------|
| `CHART.name` | Chart name; respects `nameOverride`; truncated to 63 characters |
| `CHART.fullname` | Includes release name; respects `fullnameOverride` |
| `CHART.chart` | `{Chart.Name}-{Chart.Version}` with `+` replaced by `_` |
| `CHART.labels` | Standard Kubernetes labels (chart, selector, version, managed-by) |
| `CHART.selectorLabels` | `app.kubernetes.io/name` and `app.kubernetes.io/instance` |
| `CHART.serviceAccountName` | Conditional on `serviceAccount.create`; falls back to `default` |

When creating a new chart, copy `_helpers.tpl` from an existing chart and update the template name prefix.

## Deployment Patterns

- Use checksum annotations for ConfigMap/Secret-driven rolling updates:
  ```yaml
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  ```
- Define resource requests and limits explicitly in `values.yaml`.
- Define liveness and readiness probes explicitly.
- Exporter charts collected by Google Managed Service for Prometheus use `monitoring.googleapis.com/v1` `PodMonitoring`, not Prometheus Operator `ServiceMonitor`.

## Global Values Contract

Terraform injects a `global` block via `common_helm_values` in `deploy/locals.tf`:

```yaml
global:
  cloudProvider: gcp
  namespace: <namespace>
  gateway:
    name: care-regional-gateway
    namespace: <namespace>
    gatewayClassName: gke-l7-regional-external-managed
  backendPolicy:
    enabled: true
    securityPolicy: <cloud-armor-policy-name>
  httpRoute:
    enabled: true
```

All charts should reference `global.*` for gateway routing and backend policy configuration.

## Value Injection from Terraform

- Chart-specific values are defined as locals in `deploy/helm-values.tf` and passed directly to `helm_release` resources via `yamlencode()`. File-based generation under `deploy/generated_values/` is currently disabled.
- Image configuration originates from `var.helm_config.<chart_key>` with `repository` and `tag` keys.
- Domain hostnames for HTTPRoute come from `var.web_domain_name`, `var.api_domain_name`, etc.
- Secret references use `envFromSecret` pointing to Kubernetes secrets created in `deploy/secrets.tf`.

## Routing

- Gateway API resources (HTTPRoute, Gateway) are the default routing mechanism.
- Legacy GCE Ingress is optional, controlled by the `enable_legacy_ingress` feature flag in Terraform.
- Each chart with external access includes `httproute.yaml` and `backend-policy.yaml` templates.

## Adding a New Chart

1. Create `helm_charts/<name>/` with `Chart.yaml`, `values.yaml`, and `templates/`.
2. Copy `_helpers.tpl` from an existing chart and update the template name prefix.
3. Define chart-specific values as a local in `deploy/helm-values.tf`.
4. Add a `helm_release` resource in `deploy/helm.tf`, merging `common_helm_values` via `yamlencode()`.
5. Add image configuration to the `helm_config` variable and `environments/sample.tfvars`.
