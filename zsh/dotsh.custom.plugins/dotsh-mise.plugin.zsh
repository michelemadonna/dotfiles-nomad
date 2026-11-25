#!/usr/bin/env zsh
# mise plugin for zsh
# this plugin integrates mise (https://github.com/mise/mise) into zsh shell

[[ ${DOTSH_USE_MISE:-true} == true ]] || return

# TODO: 2024-01-03 remove rtx support
local __mise=mise
if (( ! $+commands[mise] )); then
  if (( $+commands[rtx] )); then
    __mise=rtx
  else
    return
  fi
fi
typeset -g _DOTSH_MISE_COMMAND=$__mise

# This lightweight compatibility tree lets Powerlevel10k's asdf segment show
# ASDF-compatible Mise runtimes without scanning the complete plugin registry.
local mise_asdf_compat_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/mise-asdf"
local mise_legacy_asdf_dir="${XDG_DATA_HOME:-$HOME/.local/share}/asdf"
if [[ -z ${ASDF_DATA_DIR:-} || $ASDF_DATA_DIR == $mise_legacy_asdf_dir ]]; then
  export ASDF_DATA_DIR=$mise_asdf_compat_dir
fi

unset mise_asdf_compat_dir mise_legacy_asdf_dir

builtin source "${${(%):-%x}:A:h}/dotsh-mise-performance.plugin.zsh" || return

asdf() {
  command mise --quiet "$@"
}

# Keep the native Mise activation function available before the deferred
# completion setup, so the command wrapper works even if typed immediately.
if (( $+functions[mise] )); then
  functions[mise_orig]=$functions[mise]
fi

_dotsh_mise_init_completion() {
  emulate -L zsh
  if (( $+functions[_dotsh_mise_external_versions] )) &&
     [[ $functions[_mise] == $functions[_dotsh_mise_completion] ]]; then
    return 0
  fi
  # Register the runtime probes when completion is initialized.
  typeset -gA _DOTSH_MISE_RUNTIME_BINS=(
    python 'python3 python' node node deno deno bun bun go go rust rustc
    ruby ruby perl perl php php lua lua julia julia dart dart kotlin kotlinc
    scala scala ghc ghc elixir elixir zig zig crystal crystal haxe haxe
    swift swift dotnet dotnet clang clang java javac npm:typescript tsc
  )

  # Called by the Mise completion, with the output of a successful version probe.
  _dotsh_mise_parse_external_versions() {
    emulate -L zsh
    local tool=$1 line value prefix
    local version_pattern='^v?([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?)([[:space:]]|$)'
    local -a match

    for line in ${(f)2}; do
      value=$line
      prefix=''
      case $tool in
        python) prefix='Python ' ;;
        deno) prefix='deno ' ;;
        go) prefix='go version go' ;;
        rust) prefix='rustc ' ;;
        ruby)
          [[ $line == 'ruby '* ]] || continue
          value=${line#ruby }
          value=${${value%% *}%p<->}
          ;;
        php) prefix='PHP ' ;;
        lua) prefix='Lua ' ;;
        julia) prefix='julia version ' ;;
        dart) prefix='Dart SDK version: ' ;;
        kotlin)
          value=${line#info: }
          prefix='kotlinc-jvm '
          ;;
        scala)
          [[ $line == 'Scala code runner version '* || $line == 'Scala compiler version '* ]] || continue
          value=${line#* version }
          ;;
        elixir) prefix='Elixir ' ;;
        crystal) prefix='Crystal ' ;;
        swift)
          [[ $line == *'Swift version '* ]] || continue
          value=${line#*Swift version }
          ;;
        dotnet) [[ $line == *' ['*']' ]] || continue ;;
        clang)
          # Apple Clang versions identify Xcode builds, not LLVM releases.
          [[ $line == *'clang version '* && $line != 'Apple clang '* ]] || continue
          value=${line#*clang version }
          ;;
        java)
          [[ $line == 'javac '* ]] || continue
          value=${line#javac }
          if [[ $value == 1.8.0_<-> ]]; then
            value=8.0.${value#1.8.0_}
          fi
          ;;
        npm:typescript) prefix='Version ' ;;
      esac

      [[ $value == "$prefix"* ]] || continue
      value=${value#"$prefix"}
      [[ $value =~ $version_pattern ]] && print -r -- "$match[1]"
    done
  }

  _dotsh_mise_external_versions() {
    emulate -L zsh
    local tool=$1
    local -i check_only=0
    [[ ${2:-} == --check ]] && check_only=1
    case $tool in
      core:(python|node|deno|bun|go|rust|ruby|elixir|zig|swift|dotnet|java)) tool=${tool#core:} ;;
      nodejs) tool=node ;;
      golang) tool=go ;;
      dotnet-core) tool=dotnet ;;
    esac

    local -a bins=(${=_DOTSH_MISE_RUNTIME_BINS[$tool]}) probe=(--version)
    (( $#bins )) || return $check_only
    case $tool in
      python) probe=(-E -S --version) ;;
      go) probe=(version) ;;
      perl) probe=(-e 'print "$^V\n"') ;;
      lua) probe=(-v) ;;
      kotlin|scala|java) probe=(-version) ;;
      ghc) probe=(--numeric-version) ;;
      dotnet) probe=(--list-sdks) ;;
    esac

    local -a homebrew_prefixes
    local -aU bin_dirs=(/usr/bin /bin)
    case $OSTYPE in
      darwin*)
        if [[ $CPUTYPE == arm64 || $CPUTYPE == aarch64 ]]; then
          homebrew_prefixes=(/opt/homebrew /usr/local)
        else
          homebrew_prefixes=(/usr/local /opt/homebrew)
        fi
        bin_dirs+=(${^homebrew_prefixes}/bin /opt/local/bin)
        ;;
      linux*)
        local os_release=/etc/os-release key value
        local -a distribution_ids
        [[ -r $os_release ]] || os_release=/usr/lib/os-release
        [[ -r $os_release ]] || return $check_only
        while IFS='=' read -r key value; do
          case $key in
            ID|ID_LIKE) distribution_ids+=(${=${(Q)value}}) ;;
          esac
        done < "$os_release"
        (( ${distribution_ids[(I)debian]} || ${distribution_ids[(I)ubuntu]} )) || return $check_only

        homebrew_prefixes=(/home/linuxbrew/.linuxbrew)
        bin_dirs+=(/usr/local/bin ${^homebrew_prefixes}/bin)
        ;;
      *) return $check_only ;;
    esac

    local formula=$tool prefix developer_dir
    case $tool in
      clang) formula=llvm ;;
      java) formula=openjdk ;;
      npm:typescript) formula=typescript ;;
    esac

    # Keg-only and versioned formulae can be installed without links in bin.
    for prefix in "${homebrew_prefixes[@]}"; do
      bin_dirs+=("$prefix/opt/$formula/bin" "$prefix/opt/$formula"@*/bin(N-/))
      if [[ $tool == java && $OSTYPE == darwin* ]]; then
        bin_dirs+=("$prefix/opt/openjdk/libexec/openjdk.jdk/Contents/Home/bin"
          "$prefix/opt/openjdk"@*/libexec/openjdk.jdk/Contents/Home/bin(N-/))
      fi
    done

    case $tool in
      python)
        [[ $OSTYPE != darwin* ]] ||
          bin_dirs+=(/Library/Frameworks/Python.framework/Versions/*/bin(N-/))
        ;;
      go)
        bin_dirs+=(/usr/local/go/bin)
        [[ $OSTYPE != linux* ]] || bin_dirs+=(/usr/lib/go-*/bin(N-/))
        ;;
      swift) bin_dirs+=(/usr/local/swift/usr/bin) ;;
      dotnet) bin_dirs+=(/usr/share/dotnet /usr/local/share/dotnet) ;;
      java)
        if [[ $OSTYPE == darwin* ]]; then
          bin_dirs+=(/Library/Java/JavaVirtualMachines/*/Contents/Home/bin(N-/))
        else
          bin_dirs+=(/usr/lib/jvm/*/bin(N-/))
        fi
        ;;
    esac
    if [[ $OSTYPE == darwin* && ( $tool == python || $tool == swift ) ]]; then
      developer_dir=$(/usr/bin/xcode-select -p 2>/dev/null)
    fi

    local mise_data_dir=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}
    local system_mise_data_dir=${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}
    local -a managed_dirs=(
      "$mise_data_dir" "$system_mise_data_dir" "$HOME/.asdf"
      "${ASDF_DATA_DIR:-$HOME/.asdf}" "${XDG_DATA_HOME:-$HOME/.local/share}/asdf"
      ${MISE_INSTALLS_DIR:+"$MISE_INSTALLS_DIR"} ${MISE_SHIMS_DIR:+"$MISE_SHIMS_DIR"}
      ${MISE_SYSTEM_INSTALLS_DIR:+"$MISE_SYSTEM_INSTALLS_DIR"}
      ${MISE_SYSTEM_SHIMS_DIR:+"$MISE_SYSTEM_SHIMS_DIR"}
    )
    managed_dirs=("${(@)managed_dirs:A}")

    local dir executable real_file root output version
    local -a candidates
    local -A probed
    local probe_path=${(j.:.)bin_dirs}
    for dir in "${bin_dirs[@]}"; do
      [[ -d $dir ]] || continue
      candidates=("$dir/"${^bins})
      case $tool in
        python) candidates+=("$dir"/python3.<->(N)) ;;
        clang) candidates+=("$dir"/clang-<->(N) "$dir"/clang-mp-<->(N)) ;;
        lua) candidates+=("$dir"/lua<->.<->(N)) ;;
        php|ruby) candidates+=("$dir/$tool"<->.<->(N) "$dir/$tool"<->(N)) ;;
      esac

      for executable in "${candidates[@]}"; do
        [[ -f $executable && -x $executable ]] || continue
        real_file=${executable:A}
        if [[ $OSTYPE == darwin* && ( ${real_file:h} == /usr/bin || ${real_file:h} == /bin ) ]]; then
          case $tool in
            java|clang) continue ;; # JDK launcher or Apple Clang.
            python)
              [[ -n $developer_dir && -x $developer_dir/usr/bin/${real_file:t} ]] || continue
              ;;
            swift)
              [[ -n $developer_dir &&
                ( -x $developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift ||
                  -x $developer_dir/usr/bin/swift ) ]] || continue
              ;;
          esac
        fi

        [[ $real_file != */shims/* && $real_file != */.venv/* &&
          $real_file != *$'\t'* && $real_file != *$'\n'* &&
          ! $real_file -ef ${commands[mise]:-/dev/null} ]] || continue
        for root in "${managed_dirs[@]}"; do
          [[ $real_file == "$root"/* ]] && continue 2
        done
        (( check_only )) && return 0
        (( ! ${+probed[$real_file]} )) || continue
        probed[$real_file]=1

        # Version commands should see the system toolchain, not the project or shims.
        output=$(
          cd / || exit
          /usr/bin/env -i HOME="$HOME" PATH="$dir:$probe_path" LC_ALL=C GOTOOLCHAIN=local \
            DOTNET_CLI_TELEMETRY_OPTOUT=1 ${developer_dir:+DEVELOPER_DIR="$developer_dir"} \
            "$executable" "${probe[@]}" 2>&1
        ) || continue
        for version in ${(f)"$(_dotsh_mise_parse_external_versions "$tool" "$output")"}; do
          print -r -- "$version"$'\t'"$executable"
        done
      done
    done
    return $check_only
  }

  local mise_command=${_DOTSH_MISE_COMMAND:-mise}
  local mise_completion_file="$ZSH_CACHE_DIR/completions/_$mise_command"
  _dotsh_mise_prepare_completion_cache "$mise_command" "$mise_completion_file"

  typeset -g -A _comps
  if [[ -s $mise_completion_file ]]; then
    source "$mise_completion_file"
    functions[_mise_orig]=$functions[_mise]
  else
    autoload -Uz _$mise_command
  fi
  _comps[$mise_command]=_$mise_command

  functions[_mise]=$functions[_dotsh_mise_completion]
}

# Wrap mise to update .tool-versions on `mise use`; preserve its native completion
# for all subcommands outside the custom `mise use` version selector.
_dotsh_mise_native_completion() {
  if (( ! $+functions[_mise_orig] )); then
    # Fallback for a missing/unwritable cache: invoke the autoload trampoline in
    # the real completion context, capture it, then restore this wrapper.
    unfunction _mise 2>/dev/null
    autoload -Uz _mise
    _mise "$@"
    local completion_status=$?
    functions[_mise_orig]=$functions[_mise]
    functions[_mise]=$functions[_dotsh_mise_completion]
    return $completion_status
  fi

  _mise_orig "$@"
}

_dotsh_mise_completion() {
  if [[ $words[2] == use ]]; then
    local idx=3
    [[ $words[3] == -g ]] && idx=4

    if [[ ${words[$idx]} == *@* ]]; then
      local runtime=${words[$idx]%%@*} version executable
      local -A version_sources
      local -a versions specs descriptions

      while IFS= read -r version; do
        version_sources[$version]=''
      done < <(MISE_OFFLINE=1 command mise ls --installed --quiet -- "$runtime" |
        awk 'NF >= 2 && $2 != "system" {print $2}')

      while IFS=$'\t' read -r version executable; do
        if (( ! ${+version_sources[$version]} )); then
          version_sources[$version]=$executable
        fi
      done < <(_dotsh_mise_external_versions "$runtime")

      if (( ! $#version_sources )); then
        echo "⚠️ No versions installed for '$runtime'."
        echo "👉 Install with: mise install ${runtime}@<version>"
        return 1
      fi

      versions=(${(f)"$(printf '%s\n' "${(@k)version_sources}" | sort -V)"})
      for version in "${versions[@]}"; do
        specs+=("$runtime@$version")
        executable=${version_sources[$version]}
        descriptions+=("$runtime@$version${executable:+  [detected at $executable]}")
      done
      compadd -Q -S '' -V mise-versions -d descriptions -- "${specs[@]}"
      return 0
    fi

    local tool_prefix=${words[$idx]} tool
    local -aU available_tools
    available_tools=(${(f)"$(MISE_OFFLINE=1 command mise ls --installed --quiet |
      awk -v prefix="$tool_prefix" 'NF >= 2 && $2 != "system" && index($1, prefix) == 1 {print $1}')"})
    for tool in "${(@k)_DOTSH_MISE_RUNTIME_BINS}"; do
      [[ $tool == "$tool_prefix"* ]] || continue
      (( ${available_tools[(Ie)$tool]} )) && continue
      if _dotsh_mise_external_versions "$tool" --check; then
        available_tools+=("$tool")
      fi
    done
    (( $#available_tools )) || return 0
    local -a specs=(${^available_tools}'@')
    compadd -Q -S '' -- "${specs[@]}"
    return 0
  fi
  _dotsh_mise_native_completion "$@"
}

_dotsh_mise_defer_completion

# Translate mise runtime@version to asdf format and save to .tool-versions
_mise_runtime_to_asdf() {
  local spec="$1"
  local runtime="${spec%@*}"
  local version="${spec#*@}"
  local file=".tool-versions"

  if [[ "$2" == "-g" ]]; then
    file="$HOME/$file"
  fi

  if [[ "$runtime" == "$version" ]]; then
    # `mise use node` has no explicit version. Read only the selected
    # version from `mise current`; the runtime name must not leak into the
    # value written to .tool-versions.
    version=$(mise_orig current "$runtime" | awk 'NF {print $NF; exit}')
  fi

  if [[ "$runtime" == "node" ]]; then
    runtime="nodejs"
  fi

  [[ -n "$version" ]] || return 0
  [[ -f "$file" ]] || touch "$file"

  if [ $(uname -a | grep -ci Darwin) = 1 ]; then
    # macOS
    sed -i '' "/^$runtime /d" "$file"
  else  
    # Linux
    sed -i "/^$runtime /d" "$file"
  fi  

  print -r -- "$runtime $version" >> "$file"
}

_dotsh_refresh_mise_asdf_compat() {
  command sh "$DOTFILES_DIR/zsh/helpers/prepare-mise-cache.sh" --asdf-only
}

export MISE_QUIET=1
mise () {
  if [[ "$1" == use || "$1" == u ]]; then
    shift
    local global_flag=""
    if [[ "$1" == "-g" ]]; then
      global_flag="-g"
      shift
    fi
    local runtime_spec="$1"
    shift

    mise_orig use ${global_flag:+"$global_flag"} "$runtime_spec" "$@" || return "$?"

    if [[ -n "$runtime_spec" ]]; then
      _mise_runtime_to_asdf "$runtime_spec" "$global_flag"
    fi
    _dotsh_refresh_mise_asdf_compat || return
    typeset -gi _DOTSH_MISE_REFRESH_REQUIRED=1
  elif [[ "$1" == install || "$1" == i || "$1" == uninstall ||
          "$1" == prune || "$1" == upgrade || "$1" == up ]]; then
    export MISE_QUIET=0
    mise_orig "$@"
    local mise_status=$?
    export MISE_QUIET=1
    if (( mise_status == 0 )); then
      _dotsh_refresh_mise_asdf_compat || return
      typeset -gi _DOTSH_MISE_REFRESH_REQUIRED=1
    fi
    return $mise_status
  else
    mise_orig "$@"
    local mise_status=$?
    (( mise_status == 0 )) && typeset -gi _DOTSH_MISE_REFRESH_REQUIRED=1
    return $mise_status
  fi
}

unset __mise
