Installs the Aegis workspace-connector Helm release from the values the `byoc-gcp` module computes. Use it with `byoc-gcp`; the example in [`../byoc-gcp/README.md`](../byoc-gcp/README.md) shows both modules together.

```hcl
module "byoc_release" {
  source = "github.com/aegis-public/terraform-modules.git//byoc-gcp-release?ref=v0.5.00"

  name          = module.byoc_aegis.helm_release_name
  namespace     = "aegis-byoc"
  chart_version = module.byoc_aegis.helm_chart_version
  values        = module.byoc_aegis.helm_values

  depends_on = [module.byoc_aegis]
}
```
