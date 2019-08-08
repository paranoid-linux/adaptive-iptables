# Adaptive iptables
[heading__title]:
  #adaptive-iptables
  "&#x2B06; Top of ReadMe File"


Scripts triggered by `systemd` for modifying `iptables` firewall rules.


## [![Byte size of adaptive-iptables.py][badge__master__adaptive_iptables__source_code]][adaptive_iptables__master__source_code] [![Open Issues][badge__issues__adaptive_iptables]][issues__adaptive_iptables] [![Open Pull Requests][badge__pull_requests__adaptive_iptables]][pull_requests__adaptive_iptables] [![Latest commits][badge__commits__adaptive_iptables__master]][commits__adaptive_iptables__master]



------


#### Table of Contents


- [:arrow_up: Top of ReadMe File][heading__title]

- [:zap: Quick Start][heading__quick_start]

- [:shell: Utilize Adaptive iptables][heading__utilize]

- [&#x1F5D2; Notes][heading__notes]

- [:card_index: Attribution][heading__attribution]

- [&#x2696; License][heading__license]


------



## Quick Start
[heading__quick_start]:
  #quick-start
  "&#9889; Perhaps as easy as one, 2.0,..."


**Downloading**


```Bash
sudo su -
cd /usr/local/etc

git clone git@github.com:paranoid-linux/adaptive-iptables.git
```


**Upgrading**


```Bash
sudo su -
cd /usr/local/etc/adaptive-iptables

git pull
git submodule update --init --recursive --merge
```

___


## Utilize Adaptive iptables
[heading__utilize]:
  #utilize-adaptive-iptables
  "&#x1F41A; How to make use of this repository on most Linux systems"


The [`base-policies.sh`][source__adaptive_iptables__base_policies] script, and each script under the [`interface-protocols`][source__adaptive_iptables__interface_protocols] and [`services`][source__adaptive_iptables__services] directories may be run with `--help` argument to output available options.


```Bash
bash base-policies.sh --help
```


**Installation**


1. Assign interface names to array for easier looping

2. Install base policies and protocol filters

3. Enable base policies and protocol filters


```Bash
_interface_list=('eth0' 'wlan0')


bash base-policies.sh --install
bash interface-protocols/icmp.sh --install
bash interface-protocols/tcp.sh --install
bash interface-protocols/udp.sh --install


bash base-policies.sh --systemd='enable'
for _interface in "${_interface_list[@]}"; do
    bash interface-protocols/icmp.sh --systemd='enable' --interface="${_interface}"
    bash interface-protocols/tcp.sh --systemd='enable' --interface="${_interface}"
    bash interface-protocols/udp.sh --systemd='enable' --interface="${_interface}"
done
```


Restarting of interfaces _should_ trigger protocol filters, and restarting of device _should_ trigger `base-policies.sh`


**Logging**


Enable [`logging.sh`][source__adaptive_iptables__logging] to facilitate debugging of connections that should be allowed...


```Bash
bash interface-protocols/logging.sh --install

for _interface in "${_interface_list[@]}"; do
    bash interface-protocols/logging.sh --systemd='enable' --interface="${_interface}"
done
```


Disable [`logging.sh`][source__adaptive_iptables__logging] to avoid filling logs with traffic that should be ignored...


```Bash
for _interface in "${_interface_list[@]}"; do
    bash interface-protocols/logging.sh --systemd='disable' --interface="${_interface}"
done
```


View logs with your favorite text parser...


```Bash
grep -i -- 'put_log' /var/log/messages

tail -f /var/log/messages | awk '$7 ~ "put_log" {print}'
```


**Services**


1. Install `systemd` template for a given service

2. Enable service firewall rules for a set of interfaces


```Bash
bash services/ssh.sh --install

for _interface in "${_interface_list[@]}"; do
    bash services/ssh.sh --systemd='enable' --interface="${_interface}"
done
```


Firewall rules _should_ now be triggered when service **and** interface are available.


___


## Notes
[heading__notes]:
  #notes
  "&#x1F5D2; Additional resources and things to keep in mind when developing"


Unless other wise stated within an individual script, the scripts within this repository target `iptables` and **not** `ip6tables`


___


## Attribution
[heading__attribution]:
  #attribution
  "&#x1F4C7; Resources that where helpful in building this project so far."


- `ICMP`

  - `iptables -p icmp -h`
  -  https://serverfault.com/questions/84963/why-not-block-icmp
  - https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol

- `UDP`

  - https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers

- `TCP`

  - https://www.cyberciti.biz/faq/linux-detect-port-scan-attacks/
  - https://www.ossramblings.com/using_iptables_rate_limiting_to_prevent_portscans
  - https://www.linuxquestions.org/questions/linux-security-4/tcp-packet-flags-syn-fin-ack-etc-and-firewall-rules-317389/
  - https://gist.github.com/petrilli/1959001
  - https://serverfault.com/questions/123208/iptables-p-udp-state-established
  - https://serverfault.com/questions/191390/iptables-and-dhcp-questions


___


## License
[heading__license]:
  #license
  "&#x2696; Legal bits of Open Source software"


Legal bits of Open Source software


```
Adaptive iptables documentation on how this project may be utilized
Copyright (C) 2019  S0AndS0

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation; version 3 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```



[badge__commits__adaptive_iptables__master]:
  https://img.shields.io/github/last-commit/paranoid-linux/adaptive-iptables/master.svg

[commits__adaptive_iptables__master]:
  https://github.com/paranoid-linux/adaptive-iptables/commits/master
  "&#x1F4DD; History of changes on this branch"


[adaptive_iptables__community]:
  https://github.com/paranoid-linux/adaptive-iptables/community
  "&#x1F331; Dedicated to functioning code"


[badge__issues__adaptive_iptables]:
  https://img.shields.io/github/issues/paranoid-linux/adaptive-iptables.svg

[issues__adaptive_iptables]:
  https://github.com/paranoid-linux/adaptive-iptables/issues
  "&#x2622; Search for and _bump_ existing issues or open new issues for project maintainer to address."


[badge__pull_requests__adaptive_iptables]:
  https://img.shields.io/github/issues-pr/paranoid-linux/adaptive-iptables.svg

[pull_requests__adaptive_iptables]:
  https://github.com/paranoid-linux/adaptive-iptables/pulls
  "&#x1F3D7; Pull Request friendly, though please check the Community guidelines"


[badge__master__adaptive_iptables__source_code]:
  https://img.shields.io/github/repo-size/paranoid-linux/adaptive-iptables

[adaptive_iptables__master__source_code]:
  https://github.com/paranoid-linux/adaptive-iptables
  "&#x2328; Project source code!"


[source__adaptive_iptables__base_policies]:
  https://github.com/paranoid-linux/adaptive-iptables/blob/master/base-policies.sh


[source__adaptive_iptables__interface_protocols]:
  https://github.com/paranoid-linux/adaptive-iptables/tree/master/interface-protocols

[source__adaptive_iptables__services]:
  https://github.com/paranoid-linux/adaptive-iptables/tree/master/services

[source__adaptive_iptables__logging]:
  https://github.com/paranoid-linux/adaptive-iptables/blob/master/interface-protocols/logging.sh
