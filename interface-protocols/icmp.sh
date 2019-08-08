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
__DESCRIPTION__="Enables or disables ${__NAME__%.*} filtering for named interface"

__IPT_ACCEPT_LIMITS__=('-m' 'limit' '--limit' "10/second" '--limit-burst' "50")


#
#    Source useful functions
#
source "${__G_PARENT__}/shared-functions/modules/trap-failure/failure.sh"
trap 'failure "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

source "${__G_PARENT__}/shared-functions/modules/argument-parser/argument-parser.sh"
source "${__G_PARENT__}/shared-functions/license.sh"


## Provides: await_ipv4_address <interface>
source "${__G_PARENT__}/shared-functions/modules/await-ipv4-address/await-ipv4-address.sh"

## Provides: disable_systemd_template <name> <target>
source "${__G_PARENT__}/shared-functions/systemd/disable-systemd-template.sh"

## Provides: enable_systemd_template <name> <target>
source "${__G_PARENT__}/shared-functions/systemd/enable-systemd-template.sh"

## Provides: erase_systemd_protocol_filter <protocal>
source "${__G_PARENT__}/shared-functions/systemd/erase-systemd-protocol-filter.sh"

## Provides: write_systemd_protocol_filter <protocal>
source "${__G_PARENT__}/shared-functions/systemd/write-systemd-protocol-filter.sh"

## Provides: range_ipv4_address <ip>
source "${__G_PARENT__}/shared-functions/modules/range-ipv4-address/range-ipv4-address.sh"


## Provides: '--check' before issueing '--append' or '--delete' rules
source "${__G_PARENT__}/shared-functions/modules/iptables-check-before/iptables-check-before.sh"

## Provides: iptables_wipe_chain <chain>
source "${__G_PARENT__}/shared-functions/modules/iptables-wipe-chain/iptables-wipe-chain.sh"

## Provides: iptables_insert_before_logging (<args>)
source "${__G_PARENT__}/shared-functions/modules/iptables-insert-before-logging/iptables-insert-before-logging.sh"


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


iptables_icmp_rate_limit(){
    local _chain_name="${1:?No chain name provided to iptables_icmp_chain_log_drop}"
    local _icmp_type="${2:?No ICMP type provided to iptables_icmp_chain_log_drop}"

    local _rule="${_chain_name} -m icmp -p icmp --icmp-type ${_icmp_type}"

    iptables_check_before -A ${_rule} ${__IPT_ACCEPT_LIMITS__[@]} -j ACCEPT
    iptables_check_before -A ${_rule} -j DROP
}


do_stop(){
    local _interface="${1:?No interface provided}"

    iptables_wipe_chain "${_interface}_input_icmp"
    iptables_wipe_chain "${_interface}_output_icmp"

    printf '## %s finished with %s\n' "${FUNCNAME[0]}" "${_interface}"
}


do_start(){
    local _interface="${1:?No interface provided}"

    local _ip="$(await_ipv4_address "${_interface}")"
    if [ -z "${_ip}" ]; then
        printf '%s cannot find an IP for %s\n' "${FUNCNAME[0]}" "${_interface}" >&2
        return 1
    fi

    _nat_ip_range="$(range_ipv4_address "${_ip}")"
    if [ -z "${_nat_ip_range}" ]; then
        printf '%s cannot parse IP %s for an address range\n' "${FUNCNAME[0]}" "${_ip}" >&2
        return 1
    fi

    iptables --new-chain "${_interface}_input_icmp"
    iptables_check_before -A "${_interface}_input_icmp" ! -p icmp -j RETURN
    iptables_check_before -A "${_interface}_input_icmp" -m conntrack --ctstate INVALID -j DROP
    iptables_check_before -A "${_interface}_input_icmp" -m conntrack --ctstate RELATED -j ACCEPT
    iptables_check_before -A "${_interface}_input_icmp" -m conntrack --ctstate ESTABLISHED -j ACCEPT
    ## Note, accepting RELATED connection *should* accept most of the following
    ##  but to be on the safe side this script will not block useful ICMP types
    ##  ... well so long as rate limiting does not get tripped.
    iptables_icmp_rate_limit "${_interface}_input_icmp" "address-mask-reply"
    iptables_icmp_rate_limit "${_interface}_input_icmp" "destination-unreachable"
    iptables_icmp_rate_limit "${_interface}_input_icmp" "echo-reply"
    iptables_icmp_rate_limit "${_interface}_input_icmp" "fragmentation-needed"
    iptables_icmp_rate_limit "${_interface}_input_icmp" "time-exceeded"
    iptables_icmp_rate_limit "${_interface}_input_icmp" "timestamp-reply"
    iptables_icmp_rate_limit "${_interface}_input_icmp" "timestamp-request"
    iptables_icmp_rate_limit "${_interface}_input_icmp" "parameter-problem"
    ## Allow echo-requests from local NAT only
    if [ -n "${_ip}" ] && [ -n "${_nat_ip_range}" ]; then
        iptables_check_before -A "${_interface}_input_icmp" -m icmp -p icmp --icmp-type echo-request -s "${_nat_ip_range}" ${__IPT_ACCEPT_LIMITS__[@]} -j ACCEPT
        iptables_check_before -A "${_interface}_input_icmp" -m icmp -p icmp --icmp-type echo-request -s "${_nat_ip_range}" -j DROP
    fi
    iptables_check_before -A "${_interface}_input_icmp" -j RETURN

    iptables --new-chain "${_interface}_output_icmp"
    iptables_check_before -A "${_interface}_output_icmp" ! -p icmp -j RETURN
    iptables_check_before -A "${_interface}_output_icmp" -m conntrack --ctstate INVALID -j DROP
    iptables_check_before -A "${_interface}_output_icmp" -m conntrack --ctstate RELATED -j ACCEPT
    iptables_check_before -A "${_interface}_output_icmp" -m conntrack --ctstate ESTABLISHED -j ACCEPT
    iptables_icmp_rate_limit "${_interface}_output_icmp" "echo-request"
    iptables_icmp_rate_limit "${_interface}_output_icmp" "address-mask-request"
    iptables_icmp_rate_limit "${_interface}_output_icmp" "timestamp-reply"
    iptables_icmp_rate_limit "${_interface}_output_icmp" "timestamp-request"
    if [ -n "${_ip}" ] && [ -n "${_nat_ip_range}" ]; then
        iptables_check_before -A "${_interface}_output_icmp" -m icmp -p icmp --icmp-type echo-reply -d "${_nat_ip_range}" ${__IPT_ACCEPT_LIMITS__[@]} -j ACCEPT
        iptables_check_before -A "${_interface}_output_icmp" -m icmp -p icmp --icmp-type echo-reply -d "${_nat_ip_range}" -j DROP
    fi

    ## TO-DO: encapuslate the following to enable Access Point/Router like behaviours
    # iptables_icmp_rate_limit "${_interface}_output_icmp" "address-mask-reply"
    # iptables_icmp_rate_limit "${_interface}_output_icmp" "destination-unreachable"
    # iptables_icmp_rate_limit "${_interface}_output_icmp" "fragmentation-needed"
    # iptables_icmp_rate_limit "${_interface}_output_icmp" "redirect"
    # iptables_icmp_rate_limit "${_interface}_output_icmp" "router-advertisement"
    # iptables_icmp_rate_limit "${_interface}_output_icmp" "router-solicitation"
    # iptables_icmp_rate_limit "${_interface}_output_icmp" "parameter-problem"

    iptables_check_before -A "${_interface}_output_icmp" -j RETURN

    ## Link INPUT & OUTPUT to chains
    ## Note for ICMP one cannot use '-m icmp' without also defining other peramaters
    iptables_insert_before_logging -A INPUT -i "${_interface}" -p icmp -j "${_interface}_input_icmp"
    iptables_insert_before_logging -A OUTPUT -o "${_interface}" -p icmp -j "${_interface}_output_icmp"

    printf '## %s finished with %s\n' "${FUNCNAME[0]}" "${_interface}"
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
        write_systemd_protocol_filter "${__NAME__%.*}"
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
