#!/usr/bin/env bash


__SYSTEMD_DIR__="${__SYSTEMD_DIR__:-/lib/systemd/system}"
__BASE_FILTER_NAME__="${__BASE_FILTER_NAME__:-iptables-base-policies}"

if [ -z "${__GG_PARENT__}" ]; then
    __SOURCE__="${BASH_SOURCE[0]}"
    while [[ -h "${__SOURCE__}" ]]; do
        __SOURCE__="$(find "${__SOURCE__}" -type l -ls | sed -n 's@^.* -> \(.*\)@\1@p')"
    done
    __GG_PARENT__="$(dirname "$(dirname "$(cd -P "$(dirname "${__SOURCE__}")" && pwd)")")"
fi


write_systemd_protocol_filter(){    ## write_systemd_protocol_filter <protocal>
    local _protocal="${1:?${FUNCNAME[0]} not provided a protocal}"

    local _script_path="${__GG_PARENT__}/${_protocal}.sh"
    if ! [ -f "${_script_path}" ]; then
        printf 'No script at: %s\n' "${_script_path}" >&2
        return 1
    elif ! [ -x "${_script_path}" ]; then
        printf 'Non-executable: %s\n' "${_script_path}" >&2
        return 1
    fi

    local _systemd_path="${__SYSTEMD_DIR__}/iptables-${_protocal}@.service"
    if [ -f "${_systemd_path}" ]; then
        printf 'Configuration already exists %s\n' "${_systemd_path}" >&2
        return 1
    fi

    tee "${_systemd_path}" 1>/dev/null <<EOF
[Unit]
Description=${_protocal^^} iptables filter changes triggered by interface %I changes
Documentation=man:systemd.unit(5) man:device.device(5)
Requires=${__BASE_FILTER_NAME__}.service sys-subsystem-net-devices-%i.device
BindsTo=${__BASE_FILTER_NAME__}.service sys-subsystem-net-devices-%i.device
After=${__BASE_FILTER_NAME__}.service sys-subsystem-net-devices-%i.device
Wants=${__BASE_FILTER_NAME__}.service sys-subsystem-net-devices-%i.device
PartOf=${__BASE_FILTER_NAME__}.service sys-subsystem-net-devices-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart='${_script_path}' 'start' '%i'
ExecStop='${_script_path}' 'stop' '%i'
ExecReload='${_script_path}' 'reload' '%i'

[Install]
WantedBy=${__BASE_FILTER_NAME__}.service sys-subsystem-net-devices-%i.device
EOF
}
