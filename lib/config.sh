#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=""

fb_config_init() {
  local candidate="$PWD/founderbooster.yml"
  if [[ -f "$candidate" ]]; then
    CONFIG_FILE="$candidate"
  else
    CONFIG_FILE=""
  fi
}

yaml_get() {
  local path="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  awk -v target="$path" '
    function ltrim(s){sub(/^[ \t]+/,"",s); return s}
    function rtrim(s){sub(/[ \t]+$/,"",s); return s}
    function trim(s){return rtrim(ltrim(s))}
    function join_path(level, key,    i, out){
      out=key
      for(i=level-1;i>=0;i--) {
        if (stack[i] != "") {
          out=stack[i] "." out
        }
      }
      return out
    }
    {
      line=$0
      sub(/#.*/, "", line)
      if (line ~ /^[ \t]*$/) next
      indent = match($0, /[^ ]/) - 1
      if (indent < 0) indent = 0
      level = int(indent/2)
      split(line, parts, ":")
      key = trim(parts[1])
      value = ""
      if (length(parts) > 1) {
        value = substr(line, index(line, ":") + 1)
        value = trim(value)
      }
      stack[level] = key
      for (i=level+1; i<20; i++) stack[i]=""
      if (value != "") {
        if (value ~ /^".*"$/) {
          value = substr(value, 2, length(value)-2)
        } else if (value ~ /^'\''.*'\''$/) {
          value = substr(value, 2, length(value)-2)
        }
        full = join_path(level, key)
        values[full] = value
      }
    }
    END {
      if (target in values) print values[target]
    }
  ' "$file"
}

config_get() {
  local path="$1"
  if [[ -z "$CONFIG_FILE" ]]; then
    return 0
  fi
  yaml_get "$path" "$CONFIG_FILE"
}

config_app_name() {
  local val
  val="$(config_get "app")"
  if [[ -n "$val" ]]; then
    echo "$val"
    return 0
  fi
  val="$(config_get "app.name")"
  if [[ -n "$val" ]]; then
    echo "$val"
  fi
}
