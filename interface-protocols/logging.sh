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
__DESCRIPTION__='Enables or disables protocal logging of dropped packets for named interface'


#
#    Source useful functions
#
source "${__G_PARENT__}/shared-functions/modules/trap-failure/failure.sh.sh"
trap 'failure "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

source "${__G_PARENT__}/shared-functions/modules/argument-parser/argument-parser.sh"
source "${__G_PARENT__}/shared-functions/license.sh"


## Provides: '--check' before issueing '--append' or '--delete' rules
source "${__G_PARENT__}/shared-functions/modules/iptables-check-before/iptables-check-before.sh"

## Provides: iptables_whipe_chain <chain>
source "${__G_PARENT__}/shared-functions/modules/iptables-whipe-chain/iptables-whipe-chain.sh"


## Provides _configurations_ for following variables
# source "${__G_PARENT__}/shared_variables/iptables_logging.vars"
__IPT_LOG_OPTS__="${__IPT_LOG_OPTS__:---log-level 4 --log-ip-options --log-tcp-sequence}"
__IPT_LOG_LIMITS__="${__IPT_LOG_LIMITS__:--m limit --limit 5/m --limit-burst 7}"


#
#    Script functions
#
usage(){
    local -n _parsed_argument_list="${1}"
    cat <<EOF
${__DESCRIPTION__}
Copyright AGPL-3.0 2019 ${__AUTHOR__}


#
#		Usage Options
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
#		Install Options
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
#		Additional Options
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
		local _interface="${1:?No interface provided}"

    iptables_whipe_chain "${_interface}_input_log"
    iptables_whipe_chain "${_interface}_output_log"

		printf '## %s finished with %s\n' "${FUNCNAME[0]}" "${_interface}"
}


do_start(){
		local _interface="${1:?No interface provided}"

		iptables --new-chain "${_interface}_input_log"
		iptables --new-chain "${_interface}_output_log"

		for _prot in icmp udp tcp; do
				_log_prefix="${_interface}_input_log did not accept ${_prot} packet"
				iptables_check_before -A "${_interface}_input_log" ${__IPT_LOG_LIMITS__} -m "${_prot}" -p "${_prot}" -j LOG ${__IPT_LOG_OPTS__} --log-prefix \"${_log_prefix}\"
		done

		for _prot in icmp udp tcp; do
				_log_prefix="${_interface}_output_log did not send ${_prot} packet"
				iptables_check_before -A "${_interface}_output_log" ${__IPT_LOG_LIMITS__} -m "${_prot}" -p "${_prot}" -j LOG ${__IPT_LOG_OPTS__} --log-prefix \"${_log_prefix}\"
		done

		iptables_check_before -A "${_interface}_input_log" -j RETURN
		iptables_check_before -A "${_interface}_output_log" -j RETURN

		iptables_check_before -A INPUT -i ${i} -j "${_interface}_input_log"
		iptables_check_before -A OUTPUT -o ${i} -j "${_interface}_output_log"

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
