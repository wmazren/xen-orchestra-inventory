#!/bin/bash
# =========================================================
#  Xen Orchestra Full Inventory Export Script v1.0
#  Combines Host, Pool, VM, and VHD Inventory with Progress Bar + ETA
#  Author: Azren
#  Repository: https://github.com/wmazren/xo-inventory
# =========================================================

set -euo pipefail

# --- Configuration ---
# The following environment variables must be set:
# - XO_API_URL:   URL of the Xen Orchestra API (e.g., "https://<IP Address or FQDN>/rest/v0")
# - XO_API_TOKEN: Your Xen Orchestra API authentication token.

# PARALLEL_JOBS can be overridden as an environment variable.
PARALLEL_JOBS="${PARALLEL_JOBS:-10}"

# --- Colors ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

# --- Global Maps ---
declare -A HOST_MAP
declare -A POOL_MAP

# --- Functions ---

usage() {
  echo ""
  echo "Usage: $0"
  echo "This script requires the following environment variables to be set:"
  echo "  - XO_API_URL:   URL of the Xen Orchestra API (e.g., \"https://<IP Address or FQDN>/rest/v0\")"
  echo "  - XO_API_TOKEN: Your Xen Orchestra API authentication token."
  echo ""
  exit 1
}

print_header() {
  echo -e "${CYAN}=========================================================${RESET}"
  echo -e "${CYAN}        Xen Orchestra Full Inventory Exporter v1.0        ${RESET}"
  echo -e "${CYAN}=========================================================${RESET}"
  echo -e "  ${YELLOW}API Endpoint:${RESET} ${XO_API_URL}"
  echo -e "  ${YELLOW}Parallel Jobs:${RESET} ${PARALLEL_JOBS}"
}

check_deps() {
  echo -e "\n${CYAN}--- [ Step 0: Verifying Requirements ] ---${RESET}"
  local all_found=true
  for cmd in curl jq awk; do
    if ! command -v "$cmd" &> /dev/null; then
      echo -e "  ${YELLOW}✗ $cmd: Not Found${RESET}"
      all_found=false
    else
      echo -e "  ${GREEN}✓ $cmd: Found${RESET}"
    fi
  done

  if [[ "$all_found" = false ]]; then
      echo -e "\n${YELLOW}Please install the missing tools and try again.${RESET}"
      exit 1
  fi
}

api_get() {
  local path="$1"
  local api_base_url
  api_base_url=$(echo "$XO_API_URL" | grep -oE 'https?://[^/]+')

  local url
  if [[ "$path" == /* ]]; then
    url="${api_base_url}${path}"
  else
    url="${XO_API_URL}/${path}"
  fi

  curl -s -k -b "authenticationToken=${XO_API_TOKEN}" "$url"
}

progress_bar() {
  local progress=$1
  local total=$2
  local elapsed=$3
  local width=40

  if [[ $total -le 0 ]]; then
    percent=100; filled=$width; eta=0;
  else
    percent=$(( progress * 100 / total ))
    filled=$(( width * progress / total ))
    ((filled < 0)) && filled=0
    ((filled > width)) && filled=$width
    if [[ $progress -le 0 ]]; then
      eta=0
    else
      local remaining=$(( total - progress ))
      eta=$(( elapsed * remaining / progress ))
      ((eta < 0)) && eta=0
    fi
  fi

  local bar_filled
  bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '#')
  local bar_empty
  bar_empty=$(printf '%*s' $((width - filled)) '')
  printf "\r[%-${width}s] %3d%% (%d/%d) ETA: %02d:%02d" \
    "${bar_filled}${bar_empty}" "$percent" "$progress" "$total" "$((eta / 60))" "$((eta % 60))"
}

fetch_hosts() {
  echo -e "\n${CYAN}--- [ Step 1/4: Fetching Hosts ] ---${RESET}"
  echo "id,name_label,address,power_state" > xo-host.csv

  local hosts_json
  hosts_json=$(api_get "hosts?fields=id,name_label,address,power_state")

  echo "$hosts_json" | jq -r '.[] | [.id, .name_label, .address, .power_state] | @csv' >> xo-host.csv

  # Populate HOST_MAP for later steps
  while IFS="=" read -r key value; do
      [[ -n "$key" ]] && HOST_MAP["$key"]="$value"
  done < <(echo "$hosts_json" | jq -r '.[] | "\(.id)=\(.name_label)"')

  echo -e "  ${GREEN}✓ Success:${RESET} xo-host.csv created"
}

fetch_pools() {
  echo -e "\n${CYAN}--- [ Step 2/4: Fetching Pools ] ---${RESET}"
  echo "id,name_label,description_text" > xo-pool.csv

  local pools_json
  pools_json=$(api_get "pools?fields=id,name_label,description_text")

  echo "$pools_json" | jq -r '.[] | [.id, .name_label, .description_text] | @csv' >> xo-pool.csv

  # Populate POOL_MAP for later steps
  while IFS="=" read -r key value; do
      [[ -n "$key" ]] && POOL_MAP["$key"]="$value"
  done < <(echo "$pools_json" | jq -r '.[] | "\(.id)=\(.name_label)"')

  echo -e "  ${GREEN}✓ Success:${RESET} xo-pool.csv created"
}

fetch_vms() {
  echo -e "\n${CYAN}--- [ Step 3/4: Fetching VMs ] ---${RESET}" >&2
  echo "id,name_label,name_description,power_state,resident_on,pool,ip_address,memory_GB,CPUs,auto_poweron,tags" > xo-vms.csv

  local vm_hrefs_json
  vm_hrefs_json=$(api_get "vms")
  local vm_count
  vm_count=$(echo "$vm_hrefs_json" | jq 'length')
  local start_time
  start_time=$(date +%s)

  local processed_count=0
  local all_vms_json_lines=() # Array to hold individual JSON objects

  for href in $(echo "$vm_hrefs_json" | jq -r '.[]'); do
    local vm_json_line
    vm_json_line=$(api_get "$href")
    all_vms_json_lines+=("$vm_json_line")

    # --- Process for xo-vms.csv ---
    local id name desc state ip mem_bytes mem_gb cpus auto tags host_id pool_id host_name pool_name
    id=$(echo "$vm_json_line" | jq -r '.id')
    name=$(echo "$vm_json_line" | jq -r '.name_label // "unknown"')
    desc=$(echo "$vm_json_line" | jq -r '.name_description // "unknown"')
    state=$(echo "$vm_json_line" | jq -r '.power_state // "unknown"')
    ip=$(echo "$vm_json_line" | jq -r '.addresses | flatten | join(",") // "N/A"')
    mem_bytes=$(echo "$vm_json_line" | jq -r '.memory.size // 0')
    mem_gb=$(awk -v b="$mem_bytes" 'BEGIN { printf "%.2f", b / 1073741824 }')
    cpus=$(echo "$vm_json_line" | jq -r '.CPUs.number // 0')
    auto=$(echo "$vm_json_line" | jq -r '.auto_poweron // false')
    tags=$(echo "$vm_json_line" | jq -r '.tags | join(",") // ""')
    pool_id=$(echo "$vm_json_line" | jq -r '.["$poolId"] // .["$pool"] // empty')
    host_id=$(echo "$vm_json_line" | jq -r '.resident_on // .["$container"] // empty')
    host_name="N/A"
    if [[ -n "${host_id:-}" ]]; then
        host_name="${HOST_MAP[$host_id]:-N/A}"
    fi
    pool_name="N/A"
    if [[ -n "${pool_id:-}" ]]; then
        pool_name="${POOL_MAP[$pool_id]:-N/A}"
    fi
    echo "\"$id\",\"$name\",\"$desc\",\"$state\",\"$host_name\",\"$pool_name\",\"$ip\",$mem_gb,$cpus,$auto,\"$tags\"" >> xo-vms.csv
    # --- End of processing for xo-vms.csv ---

    processed_count=$((processed_count + 1))
    local elapsed=$(( $(date +%s) - start_time ))
    progress_bar "$processed_count" "$vm_count" "$elapsed" >&2
  done

  echo -e "\n  ${GREEN}✓ Success:${RESET} xo-vms.csv created" >&2

  # Join the array of JSON strings into a single JSON array string
  local final_json
  final_json=$(printf ',%s' "${all_vms_json_lines[@]}")
  final_json="[${final_json:1}]"

  # Return the full VM JSON for the VHD step
  echo "$final_json"
}

process_vm_vhd() {
  local vm_json="$1"
  local out_file="$2"
  local host_name="$3"
  local pool_name="$4"

  local vm_name vm_uuid
  vm_name=$(echo "$vm_json" | jq -r '.name_label // "unknown"')
  vm_uuid=$(echo "$vm_json" | jq -r '.uuid // .id // "unknown"')

  local vbd_list
  vbd_list=$(echo "$vm_json" | jq -r '.["$VBDs"][]?' 2>/dev/null)

  for vbd_id in $vbd_list; do
    local vbd_json vdi_id
    vbd_json=$(api_get "vbds/$vbd_id?fields=VDI")
    vdi_id=$(echo "$vbd_json" | jq -r '.VDI // empty')
    [[ -z "$vdi_id" ]] && continue

    local vdi_json vdi_name vdi_uuid size_bytes size_gb usage_bytes usage_gb
    vdi_json=$(api_get "vdis/$vdi_id?fields=name_label,uuid,size,usage")
    vdi_name=$(echo "$vdi_json" | jq -r '.name_label // "unknown"')
    vdi_uuid=$(echo "$vdi_json" | jq -r '.uuid // .id // "unknown"')
    size_bytes=$(echo "$vdi_json" | jq -r '.size // 0')
    usage_bytes=$(echo "$vdi_json" | jq -r '.usage // 0')
    size_gb=$(awk -v b="$size_bytes" 'BEGIN { printf "%.2f", b / 1073741824 }')
    usage_gb=$(awk -v b="$usage_bytes" 'BEGIN { printf "%.2f", b / 1073741824 }')

    echo "\"$vm_name\",\"$vm_uuid\",\"$host_name\",\"$pool_name\",\"$vdi_name\",\"$vdi_uuid\",$size_gb,$usage_gb" >> "$out_file"
  done
}

fetch_vhds() {
  local vms_json="$1"

  echo -e "\n${CYAN}--- [ Step 4/4: Fetching VHD Inventory ] ---${RESET}"
  local out_file="xo-vhd.csv"
  echo "vm_name,vm_uuid,host_name,pool_name,vdi_name,vdi_uuid,size_GB,usage_GB" > "$out_file"

  local tmp_dir
  tmp_dir=$(mktemp -d)

  export -f api_get process_vm_vhd
  export XO_API_URL XO_API_TOKEN

  local vm_count current=0
  vm_count=$(echo "$vms_json" | jq 'length')
  local start_time
  start_time=$(date +%s)

  mapfile -t vm_json_lines < <(echo "$vms_json" | jq -c '.[]')

  for vm_json_line in "${vm_json_lines[@]}"; do
    current=$((current + 1))

    local host_id pool_id host_name pool_name
    host_id=$(echo "$vm_json_line" | jq -r '.resident_on // .["$container"] // empty')
    pool_id=$(echo "$vm_json_line" | jq -r '.["$poolId"] // .["$pool"] // empty')
    host_name="N/A"
    if [[ -n "${host_id:-}" ]]; then
        host_name="${HOST_MAP[$host_id]:-N/A}"
    fi
    pool_name="N/A"
    if [[ -n "${pool_id:-}" ]]; then
        pool_name="${POOL_MAP[$pool_id]:-N/A}"
    fi

    process_vm_vhd "$vm_json_line" "$tmp_dir/vm_$current.csv" "$host_name" "$pool_name" &

    if (( current % PARALLEL_JOBS == 0 )); then
      wait
    fi

    local elapsed=$(( $(date +%s) - start_time ))
    progress_bar "$current" "$vm_count" "$elapsed"
  done

  wait
  cat "$tmp_dir"/*.csv >> "$out_file"
  rm -rf "$tmp_dir"

  local total_elapsed=$(( $(date +%s) - start_time ))
  echo -e "\n  ${GREEN}✓ Success:${RESET} xo-vhd.csv created in ${total_elapsed}s"
}

summary() {
  echo -e "\n${CYAN}--- [ Export Complete ] ---${RESET}"
  echo -e "${GREEN}All inventory data has been successfully exported.${RESET}"
  echo -e "\n${YELLOW}Generated Files:${RESET}"
  echo "  - xo-host.csv"
  echo "  - xo-pool.csv"
  echo "  - xo-vms.csv"
  echo "  - xo-vhd.csv"
  echo -e "\n${CYAN}=========================================================${RESET}"
}

main() {
  # --- Validation ---
  check_deps
  if [[ -z "${XO_API_URL:-}" || -z "${XO_API_TOKEN:-}" ]]; then
    usage
  fi

  print_header

  # --- Main Logic ---
  fetch_hosts
  fetch_pools
  local vms_json
  vms_json=$(fetch_vms)

  fetch_vhds "$vms_json"

  summary
}

# --- Execution ---
main "$@"
