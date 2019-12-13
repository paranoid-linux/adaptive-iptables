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





#
#    Source useful functions
#
source "${__G_PARENT__}/shared-functions/modules/trap-failure/failure.sh"
trap 'failure "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

source "${__G_PARENT__}/shared-functions/modules/argument-parser/argument-parser.sh"
source "${__G_PARENT__}/shared-functions/modules/await-interface/await-interface.sh"
source "${__G_PARENT__}/shared-functions/modules/await-ipv4-address/await-ipv4-address.sh"
source "${__G_PARENT__}/shared-functions/modules/iptables-check-before/iptables-check-before.sh"
source "${__G_PARENT__}/shared-functions/modules/iptables-insert-before-logging/iptables-insert-before-logging.sh"
source "${__G_PARENT__}/shared-functions/modules/iptables-wipe-chain/iptables-wipe-chain.sh"
source "${__G_PARENT__}/shared-functions/modules/range-ipv4-address/range-ipv4-address.sh"

source "${__G_PARENT__}/shared-functions/systemd/erase-systemd-service-filter.sh"
source "${__G_PARENT__}/shared-functions/systemd/disable-systemd-template.sh"
source "${__G_PARENT__}/shared-functions/systemd/enable-systemd-template.sh"
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

  --service ${_service:-<name>}
Configuration file name under /etc/openvpn/server directory

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
    local _service="${1:?${FUNCNAME} not provided a service name}"
    local _interfaces="${2:?${FUNCNAME} not provided an interface}"

    local _server_config_path="/etc/openvpn/server/${_service}.conf"
    local _server_enabled_confgurations="$(grep -v '#' "${_server_config_path}")"
    local _server_listen_ip="$(awk '/server /{print $2}' <<<"${_server_enabled_confgurations}")"
    local _server_ipv4_range="$(range_ipv4_address "${_server_listen_ip}")"
    local _server_interface_hint="$(awk '/dev /{print $2}' <<<"${_server_enabled_confgurations}")"

    if [ "$(grep -qE '[0-9]' <<<"${_server_interface_hint}")" ]; then
        local _server_interface="${_server_interface_hint}"
    else
        local _server_interface="$(await_interface "${_server_interface_hint:-tun}")"
    fi

    for i in ${_interfaces//,/ }; do
        iptables_wipe_chain "${i}_${_server_interface:-tun0}_input_udp_ovpns"
        iptables_wipe_chain "${i}_${_server_interface:-tun0}_output_udp_ovpns"

        iptables_wipe_chain "${i}_${_server_interface:-tun0}_input_ovpns"
        iptables_wipe_chain "${i}_${_server_interface:-tun0}_forward_ovpns"
        iptables_wipe_chain "${i}_${_server_interface:-tun0}_output_ovpns"


        iptables_wipe_chain "${i}_${_server_interface:-tun0}_input_tcp_ovpns"
        iptables_wipe_chain "${i}_${_server_interface:-tun0}_output_tcp_ovpns"

        iptables -t nat -D POSTROUTING -s ${_server_ipv4_range} -o ${i} -j MASQUERADE
    done
}


do_start(){
    local _service="${1:?${FUNCNAME} not provided a service name}"
    local _interfaces="${2:?${FUNCNAME} not provided an insterface}"

    local _server_config_path="/etc/openvpn/server/${_service}.conf"
    local _server_enabled_confgurations="$(grep -v '#' "${_server_config_path}")"
    if [ -z "$(awk '/push \"redirect-gateway def1\"/{print $2}' <<<"${_server_enabled_confgurations}")" ]; then
      local _server_tunnel_clients='no'
    else
      local _server_tunnel_clients='yes'
    fi
    local _server_listen_ip="$(awk '/server /{print $2}' <<<"${_server_enabled_confgurations}")"
    local _server_ipv4_range="$(range_ipv4_address "${_server_listen_ip}")"
    local _server_interface_hint="$(awk '/dev /{print $2}' <<<"${_server_enabled_confgurations}")"

    for i in ${_interfaces//,/ }; do
        local _ip="$(await_ipv4_address "${i}")"
        local _nat_ip_range="$(range_ipv4_address "${_ip}")"
        if [ -z "${_ip}" ] || [ -z "${_nat_ip_range}" ]; then
            printf '%s cannot find IP for %s\n' "${__NAME__}" "${i}" >&2
            return 1
        fi

        local _protocal="$(awk '/proto /{print $2}' <<<"${_server_enabled_confgurations}")"
        local _listen_port="$(awk '/port /{print $2}' <<<"${_server_enabled_confgurations}")"
        if [ "$(grep -qE '[0-9]' <<<"${_server_interface_hint}")" ]; then
            local _server_interface="${_server_interface_hint}"
        else
            local _server_interface="$(await_interface "${_server_interface_hint:-tun}")"
        fi

        local _client_to_client="$(awk '/client-to-client /{print $1}' <<<"${_server_enabled_confgurations}")"
        local _pushed_route_ips="$(awk '/push \"route /{print $3}' <<<"${_server_enabled_confgurations}")"
        local _pushed_route_dns_ips="$(awk '/push \"dhcp-option DNS /{gsub("\"",""); print $4}' <<<"${_server_enabled_confgurations}")"

        local _listen_ips="$(awk '/local /{print $2}' <<<"${_server_enabled_confgurations}")"
        for _listen_ip in ${_listen_ips:-0.0.0.0}; do
            if [ "${_listen_ip}" != '0.0.0.0' ] || [ "${_listen_ip}" != "${_ip%/*}" ]; then
                continue
            fi

            ## Chain to handle inbound cleints connecting to server
            iptables --new-chain ${i}_${_server_interface:-tun0}_input_${_protocal:-udp}_ovpns
            iptables_check_before -A ${i}_${_server_interface:-tun0}_input_${_protocal:-udp}_ovpns -m conntrack --ctstate ESTABLISHED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_input_${_protocal:-udp}_ovpns -m conntrack --ctstate NEW -m limit --limit 5/sec --limit-burst 100 -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_input_${_protocal:-udp}_ovpns -j RETURN

            ## Chains to filter inbound & outbound connections to & from connected clients
            iptables --new-chain ${i}_${_server_interface:-tun0}_input_ovpns
            iptables_check_before -A ${i}_${_server_interface:-tun0}_input_ovpns -m conntrack --ctstate ESTABLISHED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_input_ovpns -j RETURN

            iptables --new-chain ${i}_${_server_interface:-tun0}_output_ovpns
            iptables_check_before -A ${i}_${_server_interface:-tun0}_output_ovpns -m conntrack --ctstate ESTABLISHED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_output_ovpns -m conntrack --ctstate NEW -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_output_ovpns -j RETURN

            ##
            iptables --new-chain ${i}_${_server_interface:-tun0}_forward_ovpns
            iptables_check_before -A ${i}_${_server_interface:-tun0}_forward_ovpns -i ${_server_interface:-tun0} -o ${i} -m conntrack --ctstate ESTABLISHED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_forward_ovpns -i ${_server_interface:-tun0} -o ${i} -m conntrack --ctstate RELATED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_forward_ovpns -i ${_server_interface:-tun0} -o ${i} -s ${_server_ipv4_range} -m conntrack --ctstate NEW -j ACCEPT

            iptables_check_before -A ${i}_${_server_interface:-tun0}_forward_ovpns -i ${i} -o ${_server_interface:-tun0} -m conntrack --ctstate ESTABLISHED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_forward_ovpns -i ${i} -o ${_server_interface:-tun0} -m conntrack --ctstate RELATED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_forward_ovpns -j RETURN

            ## Chain to handle outbound responces to connected cleints
            iptables --new-chain ${i}_${_server_interface:-tun0}_output_${_protocal:-udp}_ovpns
            iptables_check_before -A ${i}_${_server_interface:-tun0}_output_${_protocal:-udp}_ovpns -m conntrack --ctstate ESTABLISHED -j ACCEPT
            iptables_check_before -A ${i}_${_server_interface:-tun0}_output_${_protocal:-udp}_ovpns -j RETURN

            ## Link INPUT, FORWARD & OUTPUT to chains
            iptables_insert_before_logging -A INPUT -i ${i} -p ${_protocal:-udp} -m ${_protocal:-udp} -s ${_nat_ip_range} --dport ${_listen_port:-1194} -j ${i}_${_server_interface:-tun0}_input_${_protocal:-udp}_ovpns

            for _pushed_route_dns_ip in ${_pushed_route_dns_ips}; do
                case "${_pushed_route_dns_ip##*.}" in
                    0|1)
                        local _pushed_route_dns_ip="$(range_ipv4_address "${_pushed_route_dns_ip}")"
                    ;;
                esac

                iptables_insert_before_logging -A INPUT -i ${_server_interface:-tun0} -m udp -p udp -s ${_pushed_route_dns_ip} --sport 53 -j ${i}_${_server_interface:-tun0}_input_ovpns
                iptables_insert_before_logging -A OUTPUT -o ${_server_interface:-tun0} -m udp -p udp -d ${_pushed_route_dns_ip} --dport 53 -j ${i}_${_server_interface:-tun0}_output_ovpns
            done

            for _pushed_route_ip in ${_pushed_route_ips}; do
                ## Detects if range or spicific IP is being pushed... hopefully
                case "${_pushed_route_ip##*.}" in
                    0|1)
                        local _pushed_route_ip="$(range_ipv4_address "${_pushed_route_ip}")"
                    ;;
                esac

                iptables_insert_before_logging -A INPUT -i ${_server_interface:-tun0} -s ${_pushed_route_ip} -j ${i}_${_server_interface:-tun0}_input_ovpns
                iptables_insert_before_logging -A OUTPUT -o ${_server_interface:-tun0} -d ${_pushed_route_ip} -j ${i}_${_server_interface:-tun0}_output_ovpns
            done

            if [ "${_server_tunnel_clients,,}" == 'yes' ]; then
                iptables_insert_before_logging -A INPUT -i ${_server_interface:-tun0} -j ${i}_${_server_interface:-tun0}_input_ovpns
                iptables_insert_before_logging -A OUTPUT -o ${_server_interface:-tun0} -j ${i}_${_server_interface:-tun0}_input_ovpns
            fi

            iptables_insert_before_logging -A FORWARD -i ${i} -o ${_server_interface:-tun0} -j ${i}_${_server_interface:-tun0}_forward_ovpns
            iptables_insert_before_logging -A FORWARD -o ${i} -i ${_server_interface:-tun0} -j ${i}_${_server_interface:-tun0}_forward_ovpns
            iptables_insert_before_logging -A OUTPUT -o ${i} -p ${_protocal:-udp} -m ${_protocal:-udp} -s ${_nat_ip_range} --sport ${_listen_port:-1194} -j ${i}_${_server_interface:-tun0}_output_${_protocal:-udp}_ovpns

            if [ "${_server_tunnel_clients,,}" == 'yes' ]; then
                iptables_insert_before_logging -t nat -A POSTROUTING -s ${_server_ipv4_range} -o ${i} -j MASQUERADE
            fi
        done

        ## Enable forwarding within kernal for listening interface if need be
        if [[ "$(sysctl net.ipv4.conf.${i}.forwarding)" != '1' ]]; then
            sysctl net.ipv4.conf.${i}.forwarding=1
        fi
    done

    ## Enable forwarding within kernal for VPN tun/tap interface too
    if [[ "$(sysctl net.ipv4.conf.${_server_interface}.forwarding)" != '1' ]]; then
        sysctl net.ipv4.conf.${_server_interface}.forwarding=1
    fi
}


write_systemd_service_filter(){
    local _service="${1:?${FUNCNAME[0]} not provided a service name}"

    local _script_path="${__G_PARENT__}/services/openvpn-server.sh"
    if ! [ -f "${_script_path}" ]; then
        printf 'No script at: %s\n' "${_script_path}" >&2
        exit 1
    elif ! [ -x "${_script_path}" ]; then
        printf 'Non-executable: %s\n' "${_script_path}" >&2
        exit 1
    fi

    local _systemd_path="${__SYSTEMD_DIR__}/iptables-${_service}@.service"
    if [ -f "${_systemd_path}" ]; then
        printf 'Configuration already exists %s\n' "${_systemd_path}" >&2
        return 1
    fi

    tee "${_systemd_path}" 1>/dev/null <<EOF
[Unit]
Description=${_service} server iptables script calls firing on interface %I changes
Documentation=man:systemd.unit(5) man:device.device(5)
Requires=openvpn-server@${_service}.service sys-subsystem-net-devices-%i.device
BindsTo=openvpn-server@${_service}.service sys-subsystem-net-devices-%i.device
After=openvpn-server@${_service}.service sys-subsystem-net-devices-%i.device
Wants=openvpn-server@${_service}.service sys-subsystem-net-devices-%i.device
PartOf=openvpn-server@${_service}.service sys-subsystem-net-devices-%i.device
#Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${_script_path} service "${_service}" 'start' '%i'
ExecStop=${_script_path} service "${_service}" 'stop' '%i'
ExecReload=${_script_path} service "${_service}" 'reload' '%i'

[Install]
WantedBy=openvpn-server@${_service}.service sys-subsystem-net-devices-%i.device
EOF
}

#
#    Parse arguments to variables
#
_args=("${@:?# No arguments provided try: ${__NAME__} help}")
_valid_args=('--help|-h|help:bool'
             '--license|-l|license:bool'
             '--service|service:print'
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
elif [ -z "${_service}" ]; then
    usage '_assigned_args'
    printf '\nargument_error: missing --service <name>\n' >&2
    exit 1
fi


## Pull configs for iptables from server configurations shared between do_start & do_stop


if ((_stop)) || ((_restart)); then
    if ((_background)); then
        do_stop "${_service}" "${_interface}" >/dev/null 2>&1 &
    else
        do_stop "${_service}" "${_interface}"
    fi
fi

if ((_start)) || ((_restart)); then
    if ((_background)); then
        do_start "${_service}" "${_interface}" >/dev/null 2>&1 &
    else
        do_start "${_service}" "${_interface}"
    fi
fi

if [ -z "${_systemd}" ]; then
    if ((_uninstall)) || ((_reinstall)); then
        erase_systemd_protocol_filter "${_service}"
    fi

    if ((_install)) || ((_reinstall)); then
        write_systemd_service_filter "${_service}"
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
