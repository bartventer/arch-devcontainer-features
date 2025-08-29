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
