
# Go (go)

Installs Go and common Go utilities.

## Example Usage

```json
"features": {
    "ghcr.io/bartventer/arch-devcontainer-features/go:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| goVersion | Version of Go to install (https://go.dev/dl/, https://github.com/golang/go/tags). | string | latest |
| golangciLintVersion | Version of golangci-lint to install (https://github.com/golangci/golangci-lint/releases). | string | latest |
| installGoReleaser | Whether to install GoReleaser (https://goreleaser.com/). | boolean | false |
| installGox | Whether to install gox, a tool for Go cross compilation that parallelizes builds for multiple platforms (https://github.com/mitchellh/gox). | boolean | false |
| installKo | Whether to install ko, a container image builder for Go applications (https://github.com/ko-build/ko). | boolean | false |
| installYaegi | Whether to install Yaegi, a Go interpreter that includes the yaegi command-line interpreter/REPL (https://github.com/traefik/yaegi). | boolean | false |
| installAir | Whether to install Air, a live reload tool for Go applications (https://github.com/cosmtrek/air). | boolean | false |
| installCobraCli | Whether to install Cobra CLI, a library for creating powerful modern CLI applications (https://github.com/spf13/cobra-cli/blob/main/README.md). | boolean | false |

## Customizations

### VS Code Extensions

- `golang.Go`
- `766b.go-outliner`
- `jinliming2.vscode-go-template`
- `premparihar.gotestexplorer`

## OS Support

This Feature should work on recent versions of Arch Linux.

## Available User Scripts

The following scripts are available for managing Go installations and tools:

- **go-install.sh**  
    Located in `/usr/local/bin/go-install.sh`.  
    Use this script to upgrade or install a specific version of Go.  
    Example usage:

    ```sh
    # run the following command as root or with sudo
    go-install.sh go1.25.0
    ```

- **go-tools-install.sh**  
    Located in `/usr/local/bin/go-tools-install.sh`.  
    Use this script to install or upgrade the Go tools listed in `/usr/local/share/go-tools.txt`.  
    Example usage:

    ```sh
    # run the following command as root or with sudo
    go-tools-install.sh
    ```

    >*You can edit `/usr/local/share/go-tools.txt` to customize which Go tools are installed.*


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/bartventer/arch-devcontainer-features/blob/main/src/go/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
