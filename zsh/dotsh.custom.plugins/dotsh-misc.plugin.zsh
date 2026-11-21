#!/usr/bin/env zsh
# Final interactive-shell customizations. Load after the other custom plugins.
alias _dig=dogggo _ping=gping _hex=hexyl _curl=http _ps=procs _top=btop
alias _ls='command ls' nodejs='command node'

myip() {
  local ipv4 ipv6
  ipv4=$(curl --silent -4 https://ifconfig.me)
  ipv6=$(curl --silent -6 https://ifconfig.co)

  [[ -z ${ipv4} ]] && ipv4=$(curl --silent -4 https://ifconfig.co)
  [[ -z ${ipv6} ]] && ipv6=$(curl --silent -6 https://ifconfig.me) 

  [[ -z ${ipv4} ]] && echo "No IPv4 internet connectivity" || echo "IPv4: ${ipv4}"
  [[ -z ${ipv6} ]] && echo "No IPv6 internet connectivity" || echo "IPv6: ${ipv6}"
}



if [[ ${DOTSH_ENABLE_ALLAFINE:-false} == true ]]; then
  allafine() {
    zle accept-line
    print -n $'\e[9999;1H'
  }
  zle -N allafine
  bindkey '^M' allafine
fi

function app-reset-permissions() {
  if (( $# == 0 )); then
    echo "Usage: app-reset-permissions <App Name|/path/App.app>"
    return 1
  fi

  local app="$*"
  local app_path bundle_id

  if [[ "$app" == *.app && -d "$app" ]]; then
    app_path="$app"
  else
    app_path=$(mdfind "kMDItemContentType == 'com.apple.application-bundle' && kMDItemDisplayName == '$app'" | head -n 1)

    if [[ -z "$app_path" ]]; then
      app_path="/Applications/${app}.app"
    fi
  fi

  if [[ ! -d "$app_path" ]]; then
    echo "Application not found: $app"
    return 1
  fi

  bundle_id=$(
    /usr/libexec/PlistBuddy \
      -c 'Print :CFBundleIdentifier' \
      "$app_path/Contents/Info.plist" 2>/dev/null
  )

  if [[ -z "$bundle_id" ]]; then
    echo "Unable to determine Bundle ID for: $app_path"
    return 1
  fi

  echo "App:       $app_path"
  echo "Bundle ID: $bundle_id"
  echo "Resetting TCC permissions..."

  tccutil reset All "$bundle_id"
}
