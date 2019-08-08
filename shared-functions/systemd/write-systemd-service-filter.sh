#!/usr/bin/env bash


__SYSTEMD_DIR__="${__SYSTEMD_DIR__:-/lib/systemd/system}"


if [ -z "${__GG_PARENT__}" ]; then
    __SOURCE__="${BASH_SOURCE[0]}"
    while [[ -h "${__SOURCE__}" ]]; do
        __SOURCE__="$(find "${__SOURCE__}" -type l -ls | sed -n 's@^.* -> \(.*\)@\1@p')"
    done
    __GG_PARENT__="$(dirname "$(dirname "$(cd -P "$(dirname "${__SOURCE__}")" && pwd)")")"
fi


## Restarting named service should also bring along iptables hooks

write_systemd_service_filter(){    ## write_systemd_service_filter <service> script_directory
    local _service_name="${1:?${FUNCNAME[0]} not provided a service name}"
    local _script_dir="${2:-${__GG_PARENT__}/services}"

    local _script_path="${_script_dir}/${_service_name}.sh"
    if ! [ -f "${_script_path}" ]; then
        printf 'No script at: %s\n' "${_script_path}" >&2
        exit 1
    elif ! [ -x "${_script_path}" ]; then
        printf 'Non-executable: %s\n' "${_script_path}" >&2
        exit 1
    fi

    local _systemd_path="${__SYSTEMD_DIR__}/iptables-${_service_name}@.service"
    if [ -f "${_systemd_path}" ]; then
        printf 'Configuration already exists %s\n' "${_systemd_path}" >&2
        exit 1
    fi

    tee "${_systemd_path}" 1>/dev/null <<EOF
[Unit]
Description=${_service_name} iptables script calls firing on service or interface %I changes
Documentation=man:systemd.unit(5) man:device.device(5)
Requires=${_service_name}.service sys-subsystem-net-devices-%i.device
BindsTo=${_service_name}.service sys-subsystem-net-devices-%i.device
After=${_service_name}.service sys-subsystem-net-devices-%i.device
Wants=${_service_name}.service sys-subsystem-net-devices-%i.device
PartOf=${_service_name}.service sys-subsystem-net-devices-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${_script_path} 'start' '%i'
ExecStop=${_script_path} 'stop' '%i'
ExecReload=${_script_path} 'reload' '%i'

[Install]
WantedBy=${_service_name}.service sys-subsystem-net-devices-%i.device
EOF

		printf '## %s finished\n' "${FUNCNAME[0]}"
}
