
# Terraform, tflint, and TFGrunt (terraform)

Installs the Terraform CLI and optionally Terragrunt and TFLint. Auto-detects latest version and installs needed dependencies.

## Example Usage

```json
"features": {
    "ghcr.io/bartventer/arch-devcontainer-features/terraform:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| enableShellCompletion | Enable shell completions for the Terraform CLI. This will add the necessary shell completions to your shell profile. | boolean | true |
| installTerragrunt | Install Terragrunt, a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules (https://github.com/gruntwork-io/terragrunt) | boolean | true |
| tflint | Tflint version (https://github.com/terraform-linters/tflint/releases) | string | latest |
| installSentinel | Install sentinel, a language and framework for policy built to be embedded in existing software to enable fine-grained, logic-based policy decisions (https://developer.hashicorp.com/sentinel) | boolean | false |
| installTFsec | Install tfsec, a tool to spot potential misconfigurations for your terraform code (https://github.com/aquasecurity/tfsec) | boolean | false |
| installTerraformDocs | Install terraform-docs, a utility to generate documentation from Terraform modules (https://github.com/terraform-docs/terraform-docs) | boolean | false |
| httpProxy | Connect to a keyserver using a proxy by configuring this option | string | - |

## Customizations

### VS Code Extensions

- `HashiCorp.terraform`
- `ms-azuretools.vscode-azureterraform`



## Licensing

On August 10, 2023, HashiCorp announced a change of license for its products, including Terraform. After ~9 years of Terraform being open source under the MPL v2 license, it was to move under a non-open source BSL v1.1 license, starting from the next (1.6) version. See https://github.com/hashicorp/terraform/blob/main/LICENSE

## OS Support

This Feature should work on recent versions of Arch Linux-based distributions with the `pacman` package manager installed.

`bash` is required to execute the `install.sh` script.

## Acknowledgments

This project makes use of code from the [devcontainers/features](https://github.com/devcontainers/features/tree/main/src/terraform) project. We thank the authors of devcontainers/features for their work and for making their code available for reuse.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bartventer/arch-devcontainer-features/blob/main/src/terraform/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
