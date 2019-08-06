#!/usr/bin/env bash


__SYSTEMD_DIR__="${__SYSTEMD_DIR__:-/lib/systemd/system}"


erase_systemd_protocol_filter(){    ## erase_systemd_protocol_filter <protocal>
    local _protocal="${1:?${FUNCNAME[0]} not provided a protocal}"

    local _systemd_path="${__SYSTEMD_DIR__}/iptables-${_protocal}@.service"
    if ! [ -f "${_systemd_path}" ]; then
        return 1
    fi
    rm -v "${_systemd_path}" || return "${?}"

    printf '## %s finished\n' "${FUNCNAME[0]}"
}
