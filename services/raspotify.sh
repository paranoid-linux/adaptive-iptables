#!/usr/bin/env bash


__SYSTEMD_DIR__="${__SYSTEMD_DIR__:-/lib/systemd/system}"
set -E -o functrace


## Enable sourcing via absolute path
__SOURCE__="${BASH_SOURCE[0]}"
while [[ -h "${__SOURCE__}" ]]; do
    __SOURCE__="$(find "${__SOURCE__}" -type l -ls | sed -n 's@^.* -> \(.*\)@\1@p')"
done
__G_PARENT__="$(dirname "$(cd -P "$(dirname "${__SOURCE__}")" && pwd)")"
__NAME__="${__SOURCE__##*/}"
__PATH__="${__G_PARENT__}/${__NAME__}"
__AUTHOR__='S0AndS0'
__DESCRIPTION__="Enables or disables ${__NAME__%.*} service firewall rules for named interface"

## Defaults to port 22 but maybe a list of ports
__LISTEN_TCP_SERVICE_PORTS__="$(sshd -T | awk '/port /{print $2}')"
__LISTEN_TCP_SERVICE_PORTS__="${__LISTEN_TCP_SERVICE_PORTS__:-22}"


#
#    Source useful functions
#
source "${__G_PARENT__}/shared-functions/modules/trap-failure/failure.sh"
trap 'failure "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

source "${__G_PARENT__}/shared-functions/modules/argument-parser/argument-parser.sh"
source "${__G_PARENT__}/shared-functions/modules/await-ipv4-address/await-ipv4-address.sh"
source "${__G_PARENT__}/shared-functions/modules/iptables-check-before/iptables-check-before.sh"
source "${__G_PARENT__}/shared-functions/modules/iptables-insert-before-logging/iptables-insert-before-logging.sh"
source "${__G_PARENT__}/shared-functions/modules/iptables-wipe-chain/iptables-wipe-chain.sh"
source "${__G_PARENT__}/shared-functions/modules/range-ipv4-address/range-ipv4-address.sh"

source "${__G_PARENT__}/shared-functions/systemd/erase-systemd-protocol-filter.sh"
source "${__G_PARENT__}/shared-functions/systemd/write-systemd-service-filter.sh"
source "${__G_PARENT__}/shared-functions/license.sh"


#
#    Script functions
#
usage(){
    local -n _parsed_argument_list="${1}"
    cat <<EOF
${__DESCRIPTION__}
Copyright AGPL-3.0 2019 ${__AUTHOR__}


#
#   Usage Options
#


  --background
Run 'start', 'stop', or 'restart' tasks with ">/dev/null 2>&1 &", note this may silence errors

  --up           --start
Inserts iptables rules defined within "do_start" of ${__PATH__}

  --down         --stop
Deletes iptables rules via commands within "do_stop" of ${__PATH__}

  --restart      --reload
Run "--up" then "--down" tasks

  <interface>
Name of interface to run iptables scripted actions with


> Note, any of the above maybe used without prefixed hyphens '--', eg. ${__NAME__} restart ${_interface}


#
#   Install Options
#

  --install      --write
Write systemd configuration to: ${__SYSTEMD_DIR__}/iptables-${__NAME__%.*}@.service

  --uninstall    --erase
Remove systemd configuration

  --reinstall    --update
Runs "--uninstall" then "--install" tasks

  --systemd="enable"    --systemd="disable"
Enable or disable systemd configuration


#
#   Additional Options
#

  -l      --license
Shows script or project license then exits

  -h      --help
Shows values set for above options, print usage, then exits
EOF
    if (("${#_parsed_argument_list[@]}")); then
        printf '\n\n#\n#    Parsed Options\n#\n\n\n'
        printf '    %s\n' "${_parsed_argument_list[@]}"
    fi
}


do_stop(){
    _interfaces="${1}"
    for i in ${_interfaces//,/ }; do
				iptables_wipe_chain "${i}_input_tcp_raspotify"
				iptables_wipe_chain "${i}_input_udp_raspotify"
				iptables_wipe_chain "${i}_output_tcp_raspotify"
				iptables_wipe_chain "${i}_output_udp_raspotify"
    done
}


do_start(){
    _interfaces="${1}"
		## librespot listens on a random unprivlaged tcp port and usually 5353 for udp
		_listen_tcp_port="$(await_service_port "librespot" "tcp")"
		_listen_udp_port="$(await_service_port "librespot" "udp")"
    for i in ${_interfaces//,/ }; do
        _ip="$(await_ipv4_address "${i}")"
        _nat_ip_range="$(range_ipv4_address "${_ip}")"
        if [ -z "${_ip}" ] || [ -z "${_nat_ip_range}" ]; then
            printf '%s cannot find IP for %s\n' "${__NAME__}" "${i}" >&2
            return 1
        fi

				iptables --new-chain ${i}_input_tcp_raspotify
				iptables_check_before -A ${i}_input_tcp_raspotify -m conntrack --ctstate ESTABLISHED -j ACCEPT
				iptables_check_before -A ${i}_input_tcp_raspotify -m conntrack --ctstate NEW -m limit --limit 5/second --limit-burst 100 -j ACCEPT
				iptables_check_before -A ${i}_input_tcp_raspotify -j RETURN

				iptables --new-chain ${i}_input_udp_raspotify
				iptables_check_before -A ${i}_input_udp_raspotify -m conntrack --ctstate ESTABLISHED -j ACCEPT
				iptables_check_before -A ${i}_input_udp_raspotify -m conntrack --ctstate NEW -m limit --limit 5/second --limit-burst 100 -j ACCEPT
				iptables_check_before -A ${i}_input_udp_raspotify -j RETURN

				iptables --new-chain ${i}_output_tcp_raspotify
				iptables_check_before -A ${i}_output_tcp_raspotify -m conntrack --ctstate ESTABLISHED -j ACCEPT
				## Supposedly 4070 is tried before port 443
				iptables_check_before -A ${i}_output_tcp_raspotify -m conntrack --ctstate NEW --dport 4070 -j ACCEPT
				iptables_check_before -A ${i}_output_tcp_raspotify -j RETURN

				iptables --new-chain ${i}_output_udp_raspotify
				iptables_check_before -A ${i}_output_udp_raspotify -m conntrack --ctstate ESTABLISHED -j ACCEPT
				iptables_check_before -A ${i}_output_udp_raspotify -j RETURN

				## Link INPUT & OUTPUT to chains
				iptables_insert_before_logging -A INPUT -i ${i} -p tcp -m tcp -s ${_nat_ip_range} --dport ${_listen_tcp_port} -j ${i}_input_tcp_raspotify
				iptables_insert_before_logging -A INPUT -i ${i} -p udp -m udp -s ${_nat_ip_range} --dport ${_listen_udp_port} -j ${i}_input_udp_raspotify

				iptables_insert_before_logging -A OUTPUT -o ${i} -p tcp -m tcp -d ${_nat_ip_range} --sport ${_listen_tcp_port} -j ${i}_output_tcp_raspotify
				iptables_insert_before_logging -A OUTPUT -o ${i} -p udp -m udp -d ${_nat_ip_range} --sport ${_listen_udp_port} -j ${i}_output_udp_raspotify
    done
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
             '--background|background:bool'
             '--interface:posix-nil')
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
        do_stop "${_interface}" >/dev/null 2>&1 &
    else
        do_stop "${_interface}"
    fi
fi

if ((_start)) || ((_restart)); then
    if ((_background)); then
        do_start "${_interface}" >/dev/null 2>&1 &
    else
        do_start "${_interface}"
    fi
fi

if [ -z "${_systemd}" ]; then
    if ((_uninstall)) || ((_reinstall)); then
        erase_systemd_protocol_filter "${__NAME__%.*}"
    fi

    if ((_install)) || ((_reinstall)); then
        write_systemd_service_filter "${__NAME__%.*}"
    fi
else
    case "${_systemd,,}" in
        'activate'|'enable')
            enable_systemd_template "${__NAME__%.*}" "${_interface}"
            systemctl daemon-reload
        ;;
        'deactivate'|'disable')
            disable_systemd_template "${__NAME__%.*}" "${_interface}"
            systemctl daemon-reload
        ;;
    esac
fi
