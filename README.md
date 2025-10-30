# Xen Orchestra Inventory Export Script

`xen-orchestra-inventory.sh` is designed to export **Xen Orchestra (XO)** inventory data directly via the **REST API**. It collects information about **Hosts**, **Pools**, **Virtual Machines (VMs)**, and **virtual hard disks (VHDs)**, then exports them into clean **CSV files** — ideal for reporting, CMDB integration, or capacity analysis.

## Purpose

The primary purpose of this script is to automate the process of gathering detailed information from a Xen Orchestra environment and exporting it into an easily-parseable format (CSV). This can be useful for:

-   Inventory management
-   Auditing and reporting
-   Data analysis and capacity planning
-   Migration planning

The script generates the following files:
-   `xo-host.csv`: Contains information about host servers.
-   `xo-pool.csv`: Contains information about resource pools.
-   `xo-vms.csv`: Contains detailed information about all virtual machines.
-   `xo-vhd.csv`: Contains information about virtual hard disks and their usage, mapped to their respective VMs.

The script includes a progress bar with an ETA for long-running export operations.

## Requirements

To run this script, you need the following command-line tools installed on your system:

-   `bash`: The script is written in Bash (version 4.0+ recommended).
-   `curl`: Used to make API requests to the Xen Orchestra server.
-   `jq`: Used to parse the JSON responses from the API.
-   `awk`: Used for data manipulation (calculating sizes in GB).

You also need network access to the Xen Orchestra API endpoint from the machine where you run the script.

## Configuration

Before running the script, you must set the following environment variables:

-   `XO_API_URL`: The full URL to your Xen Orchestra API endpoint (e.g., `https://xo.your-domain.com/rest/v0`).
-   `XO_API_TOKEN`: A valid API token generated from your Xen Orchestra user profile. **Keep this token secure.**

You can also optionally set the following environment variable:

-   `PARALLEL_JOBS`: Controls the number of parallel processes used for fetching VHD information. It defaults to `10`. A higher number can speed up the export on powerful machines but may increase the load on the XO server.

## How to Run the Script

1.  **Make the script executable:**
    ```sh
    chmod +x xen-orchestra-inventory.sh
    ```

2.  **Set the environment variables and run the script:**

    You can either `export` the variables in your shell session:
    ```sh
    export XO_API_URL="https://<IP Address or FQDN>/rest/v0"
    export XO_API_TOKEN="your_secret_token_here"
    ./xen-orchestra-inventory.sh
    ```

    Or, you can pass them on the same line as the command:
    ```sh
    XO_API_URL="https://<IP Address or FQDN>/rest/v0" XO_API_TOKEN="your_secret_token_here" ./xen-orchestra-inventory.sh
    ```

    To use a different number of parallel jobs, set the `PARALLEL_JOBS` variable:
    ```sh
    export PARALLEL_JOBS=20
    ./xen-orchestra-inventory.sh
    ```

## Sample Output

When you run the script, the output will look like this:

```text
=========================================================
        Xen Orchestra Full Inventory Exporter v1.0
=========================================================
  API Endpoint: https://<IP Address or FQDN>/rest/v0
  Parallel Jobs: 10

--- [ Step 0: Verifying Requirements ] ---
  ✓ curl: Found
  ✓ jq: Found
  ✓ awk: Found

--- [ Step 1/4: Fetching Hosts ] ---
  ✓ Success: xo-host.csv created

--- [ Step 2/4: Fetching Pools ] ---
  ✓ Success: xo-pool.csv created

--- [ Step 3/4: Fetching VMs ] ---
[########################################] 100% (251/251) ETA: 00:00
  ✓ Success: xo-vms.csv created

--- [ Step 4/4: Fetching VHD Inventory ] ---
[########################################] 100% (251/251) ETA: 00:00
  ✓ Success: xo-vhd.csv created in 25s

--- [ Export Complete ] ---
All inventory data has been successfully exported.

Generated Files:
  - xo-host.csv
  - xo-pool.csv
  - xo-vms.csv
  - xo-vhd.csv

=========================================================
```%
