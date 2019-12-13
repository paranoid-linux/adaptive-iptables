#!/usr/bin/env bash


## Suposedly 'bin' and 'lib' directories are to be re-sorted under
##  'usr' directory, eg. '/usr/local/systemd/system/' however,
##  Debian still uses the following path as of 2019.
__SYSTEMD_DIR__="${__SYSTEMD_DIR__:-/lib/systemd/system}"


## Enable sourcing via absolute path
__SOURCE__="${BASH_SOURCE[0]}"
while [[ -h "${__SOURCE__}" ]]; do
    __SOURCE__="$(find "${__SOURCE__}" -type l -ls | sed -n 's@^.* -> \(.*\)@\1@p')"
done
__DIR__="$(cd -P "$(dirname "${__SOURCE__}")" && pwd)"
__NAME__="${__SOURCE__##*/}"
__PATH__="${__DIR__}/${__NAME__}"
__AUTHOR__='S0AndS0'
__DESCRIPTION__='Inserts or deletes loopback spoof dropping as well as setting policies to DROP or ACCEPT'


#
#    Source useful functions
#
## Provides: 'failure'
source "${__DIR__}/shared-functions/modules/trap-failure/failure.sh"
trap 'failure "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

source "${__DIR__}/shared-functions/modules/argument-parser/argument-parser.sh"


#
#    Script functions
#
usage(){
    local -n _parsed_argument_list="${1}"
    cat <<EOF
${__DESCRIPTION__}
Copyright AGPL-3.0 2019 ${__AUTHOR__}


## Usage Options


  --up           --start
Inserts loopback spoofing filters and sets INPUT, OUTPUT, and FORWARD chains to DROP policy

  --down         --stop
Deletes loopback spoofing filters and sets INPUT, OUTPUT, and FORWARD chains to ACCEPT policy

  --restart      --reload
Run "--up" then "--down" tasks


> Note, any of the above maybe used without prefixed hyphens '--', eg. ${__NAME__} restart


## Install Options


  --install      --write
Write systemd configuration to: ${__SYSTEMD_DIR__}/iptables-${_name}.service

  --uninstall    --erase
Remove systemd configuration

  --reinstall    --update
Runs "--uninstall" then "--install" tasks

  --systemd="enable"    --systemd="disable"
Enable or disable systemd configuration


## Additional Options


  -l      --license
Shows script or project license then exits

  -h      --help
Shows values set for above options, print usage, then exits
EOF
    if (("${#_parsed_argument_list[@]}")); then
        printf '\n\n## Parsed Options\n\n'
        printf '    %s\n' "${_parsed_argument_list[@]}"
    fi
}


do_stop(){
    iptables -D INPUT ! -i lo -s 127.0.0.0/8 -j DROP
    iptables -D INPUT -i lo -j ACCEPT
    iptables -D OUTPUT -o lo -j ACCEPT

    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
}


do_start(){
    ## Let loopback interface do what it needs for the most part
    iptables -I INPUT 1 ! -i lo -s 127.0.0.0/8 -j DROP
    iptables -I INPUT 2 -i lo -j ACCEPT
    iptables -I OUTPUT 1 -o lo -j ACCEPT

    ## Default policy for any packet not matched
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP
}


erase_systemd_base_filter(){
    local _name="${__NAME__%.*}"
    _name="${_name//[_ ]/-}"
    local _systemd_path="${__SYSTEMD_DIR__}/iptables-${_name}.service"

    if ! [ -f "${_systemd_path}" ]; then
        return 1
    fi

    rm -v "${_systemd_path}" || return "${?}"
}


write_systemd_base_filter(){
    local _name="${__NAME__%.*}"
    _name="${_name//[_ ]/-}"
    local _systemd_path="${__SYSTEMD_DIR__}/iptables-${_name}.service"

    if [ -f "${_systemd_path}" ]; then
        printf 'Configuration for systemd already exsists: %s\n' "${_systemd_path}" >&2
        return 1
    fi

    tee "${_systemd_path}" 1>/dev/null <<EOF
[Unit]
Description=Custom iptables base policies
After=fail2ban.service
BindsTo=network-online.target
Requires=network-online.target
Wants=network-online.target
PartOf=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart='${__PATH__}' 'start'
ExecStop='${__PATH__}' 'stop'
ExecReload='${__PATH__}' 'stop'
#TimeoutStartSec=1min 30s

[Install]
WantedBy=network-online.target
EOF
    printf '## %s finished\n' "${FUNCNAME[0]}"
}


disable_systemd_base_filter(){
    local _name="${__NAME__//[ _]/-}"
    local _path="${__SYSTEMD_DIR__}/iptables-${_name%.*}.service"

    if ! [ -f "${_path}" ]; then
        printf 'Configuration for systemd does not exsist: %s\n' "${_path}" >&2
        return 1
    fi

    rm -v "${_path}" || return "${?}"
    printf '## %s finished\n' "${FUNCNAME[0]}"
}


enable_systemd_base_filter(){
    local _name="${__NAME__//[ _]/-}"
    local _path="${__SYSTEMD_DIR__}/iptables-${_name%.*}.service"

    if ! [ -f "${_path}" ]; then
        printf 'No file found at: %s\n' "${_path}" >&2
        return 1
    fi

    systemctl enable iptables-${_name%.*}.service

    printf '## %s finished\n' "${FUNCNAME[0]}"
}


#
#    Parse arguments to variables
#
_args=("${@:?# No arguments provided try: ${__NAME__} help}")
_valid_args=('--help|-h|help:bool'
             '--license|-l|license:bool'
             '--start|start|--up|up:bool'
             '--stop|stop|--down|down:bool'
             '--restart|restart|--reload|reload:bool'
             '--install|--write:bool'
             '--uninstall|--erase:bool'
             '--reinstall|--update:bool'
             '--systemd:alpha_numeric'
             '--background|--bg:bool')
argument_parser '_args' '_valid_args'
_exit_status="$?"


#
# Do things maybe
#
if ((_help)) || ((_exit_status)); then
    usage '_assigned_args'
    exit ${_exit_status:-0}
elif ((_license)); then
    __license__ "${__DESCRIPTION__}" "${__AUTHOR__}"
    exit ${_exit_status:-0}
fi


if ((_stop)) || ((_restart)); then
    if ((_background)); then
        do_stop >/dev/null 2>&1 &
    else
        do_stop
    fi
fi

if ((_start)) || ((_restart)); then
    if ((_background)); then
        do_start >/dev/null 2>&1 &
    else
        do_start
    fi
fi

if [ -z "${_systemd}" ]; then
    if ((_uninstall)) || ((_reinstall)); then
        erase_systemd_base_filter "${__NAME__%.*}"
    fi

    if ((_install)) || ((_reinstall)); then
        write_systemd_base_filter "${__NAME__%.*}"
    fi
else
    case "${_systemd,,}" in
        'activate'|'enable')
            enable_systemd_base_filter
        ;;
        'deactivate'|'disable')
            disable_systemd_base_filter
        ;;
    esac
fi
