#!/bin/bash

# each curl command is run with timeout 15 and max-time 10
# We do this to avoid blocking the script for too long if the host is down

top3=false
url=""
declare -a mounts_array
conky=false
skip_gpu=false
while getopts ":htu:m:cg" opt; do
  case "$opt" in
    h) echo -e "Usage: $0 [-h] [-c] [-t] [-g] -u <GLANCES_URL> [-m <MOUNT_POINT:DISPLAY>...]\n  -h show this help\n  -c conky compatible output\n  -t show top 3 CPU and memory usage\n  -g skip GPU information\n  -u <GLANCES_URL> URL of the GLANCES API\n  -m <MOUNT_POINT:DISPLAY>... list of mount points and their display names" >&2; exit 0 ;;
    t) top3=true ;;
    u) url="$OPTARG" ;;
    m) mounts_array+=("$OPTARG") ;;
    c) conky=true ;;
    g) skip_gpu=true ;;
    \?) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 1 ;;
  esac
done

if [ -z "$url" ]; then
  echo "Missing GLANCES_URL" >&2
  exit 1
fi

GLANCES_URL="$url/api/4"

# check if it is a valid url
if [[ ! "$url" =~ ^https?:// ]]; then
  echo "Invalid GLANCES_URL" >&2
  exit 1
fi

# check if the Host answers that URL
if ! timeout 15 curl --max-time 10 -s "$GLANCES_URL/uptime" &> /dev/null; then
  if [ "$conky" = true ]; then
    echo "\${color red}No response from Host\${color $default_color}"
  else
    echo "No response from Host"
  fi
  exit 0
fi

default_color="white"

# get uptime
uptime=$(timeout 15 curl --max-time 10 -s "$GLANCES_URL/uptime" | tr -d '"')
# if answer is 404 page not found (Traefik answer, adapt to your reverse proxy)
if [[ "A$uptime" == "A404 page not found" ]]; then
  if [ "$conky" = true ]; then
    echo "\${color red}Host down\${color $default_color}"
  else
    echo "Host down"
  fi
  exit 0
fi

# conky 'execpi' compatible color code
colorcode() {
  if [ "$conky" = false ]; then
    echo -n "$1"
    return
  fi

  local value=$1
  local limit1=$2 # red
  local limit2=$3 # orange
  local limit3=$4 # yellow
  # numerical comparison
  if (( $(echo "$value >= $limit1" | bc -l) )); then
    echo -n "\${color red}$value\${color $default_color}"
  elif (( $(echo "$value >= $limit2" | bc -l) )); then
    echo -n "\${color orange}$value\${color $default_color}"
  elif (( $(echo "$value >= $limit3" | bc -l) )); then
    echo -n "\${color yellow}$value\${color $default_color}"
  else
    echo -n "\${color green}$value\${color $default_color}"
  fi
}

cpu=$(timeout 15 curl --max-time 10 -s "$GLANCES_URL/cpu" | jq '.total')
load_data=$(timeout 15 curl --max-time 10 -s "$GLANCES_URL/load")
min1=$(echo "$load_data" | jq '.min1')
min1_fmt=$(awk "BEGIN {printf \"%.2f\", $min1}")
cores=$(echo "$load_data" | jq '.cpucore')

# First line
echo "$cores cores Uptime: $uptime"

mem=$(timeout 15 curl --max-time 10 -s "$GLANCES_URL/mem")
mem_used=$(echo "$mem" | jq '.used / 1024 / 1024 | floor')
mem_free=$(echo "$mem" | jq '.free / 1024 / 1024 | floor')
mem_percent=$(colorcode $(echo "$mem" | jq '.percent') 90 70 50)

# Next line
echo "CPUs: "$(colorcode "$cpu" 90 70 50)"% Load: $min1_fmt RAM $mem_percent% U:${mem_used} MB F:${mem_free} MB"

if [ "$top3" = true ]; then
  processlist=$(timeout 15 curl --max-time 10 -s "$GLANCES_URL/processlist")
  top3cpu=$(echo "$processlist" | jq -r 'sort_by(.cpu_percent) | reverse | .[:3][] | "\(.name):\(.cpu_percent | floor)"')
  # Next line
  echo -n "top3cpu: "
  for i in $top3cpu; do
    i_proc=$(echo "$i" | cut -d ':' -f 1)
    i_cpu=$(echo "$i" | cut -d ':' -f 2)
    echo -n "$i_proc "$(colorcode $i_cpu 90 70 50)"% "
  done
  echo ""
  top3mem=$(echo "$processlist" | jq -r 'sort_by(.memory_percent) | reverse | .[:3][] | "\(.name):\(.memory_percent | floor)"')
  # Next line
  echo -n "top3mem: "
  for i in $top3mem; do
    i_proc=$(echo "$i" | cut -d ':' -f 1)
    i_mem=$(echo "$i" | cut -d ':' -f 2)
    echo -n "$i_proc "$(colorcode $i_mem 90 70 50)"% "
  done
  echo ""
fi

if [ "$skip_gpu" = false ]; then
  gpu_data=$(timeout 15 curl --max-time 10 -s "$GLANCES_URL/gpu")
  gpu_name=$(echo $gpu_data | jq '.[0].name')
  if [[ "A$gpu_name" != "Anull"  ]]; then
    gpu_name=$(echo $gpu_name | sed 's/geforce//I' | tr -s ' ' | tr -d '"')
    gpu_mem=$(colorcode $(awk "BEGIN {printf \"%.2f\", $(echo $gpu_data | jq '.[0].mem')}") 90 70 50)
    gpu_proc=$(colorcode $(echo $gpu_data | jq '.[0].proc') 90 70 50)
    gpu_temp=$(echo $gpu_data | jq -r '.[0] .temperature')
    # Next line
    echo "$gpu_name $gpu_proc% VRAM U:$gpu_mem% $gpu_temp°C"
  fi
fi

if [ "${#mounts_array[@]}" -gt 0 ]; then
  disk_data=$(timeout 15 curl --max-time 10 -s "$GLANCES_URL/fs")
  for mounts in "${mounts_array[@]}"; do
    to_find=$(echo "$mounts" | cut -d ':' -f 1)
    to_display=$(echo "$mounts" | cut -d ':' -f 2)
    get_percent=$(echo "$disk_data" | jq -r '.[] | select(.mnt_point == "'$to_find'") | .percent')
    if [ -z "$get_percent" ]; then
      if [ "$conky" = true ]; then
        echo -n "\${color red}$to_display unknown%\${color $default_color} "
      else
        echo -n "$to_display unknown% "
      fi
      continue
    fi
    disk_percent=$(colorcode $get_percent 90 70 50)
    # Next line
    echo -n "$to_display $disk_percent% "
    echo "$disk_data" | jq -r '.[] | select(.mnt_point == "'$to_find'") | "of \(.size / 1024 / 1024 / 1024 | floor) GB U: \(.used / 1024 / 1024 / 1024 | floor) GB  F: \(.free / 1024 / 1024 / 1024 | floor) GB"'
  done
fi

exit 0
