<!-- markdownlint-disable MD024 -->

# Dev Container Features

[![Release](https://img.shields.io/github/release/bartventer/arch-devcontainer-features.svg)](https://github.com/bartventer/arch-devcontainer-features/releases/latest)
[![Test Workflow](https://github.com/bartventer/arch-devcontainer-features/actions/workflows/test.yaml/badge.svg)](https://github.com/bartventer/arch-devcontainer-features/actions/workflows/test.yaml)
[![License](https://img.shields.io/github/license/bartventer/arch-devcontainer-features.svg)](LICENSE)

<!-- markdownlint-disable MD033 -->
<table style="width: 100%; border-style: none;">
    <tr>
        <td style="width: 140px; text-align: center;">
            <a href="https://github.com/JotaRandom/archlinux-artwork">
                <img width="128px" src="https://raw.githubusercontent.com/JotaRandom/archlinux-artwork/a9029989166ef42e10251f9d0f0fd09e60be2f31/icons/archlinux-icon-crystal-256.svg" alt="Arch Linux logo"/>
            </a>
        </td>
        <td>
            <strong>Development Container 'Features'</strong><br />
            <i>A set of simple and reusable Features for Arch Linux development containers.</i><br />
        </td>
    </tr>
</table>
<!-- markdownlint-enable MD033 -->

This repository contains a _collection_ of features curated by [@bartventer](https://github.com/bartventer). While most of these features are built for Arch Linux, please refer to the "OS Support" section of each feature for specific operating system compatibility.

## Collected Features

| Feature                                                            | Description                                                                                             |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| [aws-cli](src/aws-cli/README.md)                                   | Installs the AWS CLI along with needed dependencies.                                                    |
| [azure-cli](src/azure-cli/README.md)                               | Installs the Azure CLI along with needed dependencies.                                                  |
| [common-utils](src/common-utils/README.md)                         | Installs a set of common command line utilities, Oh My Zsh!, and sets up a non-root user on Arch Linux. |
| [docker-in-docker](src/docker-in-docker/README.md)                 | Installs Docker and Docker Compose in a Docker container.                                               |
| [docker-outside-of-docker](src/docker-outside-of-docker/README.md) | Re-uses the host docker socket, adding the Docker CLI to a container.                                   |
| [gcloud-cli](src/gcloud-cli/README.md)                             | Installs the Google Cloud CLI along with needed dependencies.                                           |
| [go](src/go/README.md)                                             | Installs the Go programming language and common Go utilities.                                           |
| [terraform](src/terraform/README.md)                               | Installs the Terraform CLI and optionally Terragrunt and TFLint.                                        |

> [!NOTE]
> A base image is not provided in this repository, but [bartventer/devcontainer-images](https://github.com/bartventer/devcontainer-images) provides a [base-archlinux](https://github.com/bartventer/devcontainer-images/blob/master/src/base-archlinux/README.md) image which has been configured according to [these](https://gitlab.archlinux.org/archlinux/archlinux-docker/blob/master/README.md) guidelines.

## Contributing

All contributions are welcome! Open a pull request to request a feature or submit a bug report.

## License

This project is licensed under the [MIT License](LICENSE).

## Trademarks

The Arch Linux logo is a recognized trademark of Arch Linux. See the [Arch Linux website](https://archlinux.org/) for acceptable use and restrictions. The logo used in this README.md is sourced from [this repository](https://github.com/JotaRandom/archlinux-artwork) and is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License](https://creativecommons.org/licenses/by-nc-sa/3.0/).
