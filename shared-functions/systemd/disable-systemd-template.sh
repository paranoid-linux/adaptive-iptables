#!/usr/bin/env bash


__SYSTEMD_DIR__="${__SYSTEMD_DIR__:-/lib/systemd/system}"


disable_systemd_template(){    ## disable_systemd_template <name> <target>
    local _name="${1:?${FUNCNAME[0]} not provided a template name}"
    local _target="${2:?${FUNCNAME[0]} not provided a target}"

    local _path="${__SYSTEMD_DIR__}/iptables-${_name}@.service"
    if ! [ -f "${_path}" ]; then
        printf 'No file found at: %s\n' "${_path}" >&2
        return 1
    fi

    systemctl disable iptables-${_name}@${_target}.service

    printf '## %s finished\n' "${FUNCNAME[0]}"
}
