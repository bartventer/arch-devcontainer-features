### **IMPORTANT NOTE**
- **Ids used to publish this Feature in the past - 'devcontainer-features/aws-cli'**

# AWS CLI (aws-cli)

Installs the AWS CLI along with needed dependencies. Useful for base Dockerfiles that often are missing required install dependencies like gpg.

## Example Usage

```json
"features": {
    "ghcr.io/bartventer/arch-devcontainer-features/aws-cli:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| enableShellCompletion | Enable shell completions for the AWS CLI. This will add the necessary shell completions to your shell profile. | boolean | true |
| installSam | Install the AWS SAM CLI (https://docs.aws.amazon.com/serverless-application-model/) via the specified method. | string | none |
| samVersion | SAM CLI version (https://github.com/aws/aws-sam-cli/releases). Only applicable if `installSam` is set to `standalone`. | string | latest |

## Customizations

### VS Code Extensions

- `AmazonWebServices.aws-toolkit-vscode`

As of version 1.4.1, this feature will always install AWS CLI v1. The option to select AWS CLI v2 has been removed due to AWS CLI v2 being moved to the Arch User Repository (AUR).

## OS Support

This Feature should work on recent versions of Arch Linux distributions with the `pacman` package manager installed.

`bash` is required to execute the `install.sh` script.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bartventer/arch-devcontainer-features/blob/main/src/aws-cli/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
