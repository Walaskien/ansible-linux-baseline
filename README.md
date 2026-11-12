# ansible-linux-baseline

[![ci](https://github.com/Walaskien/ansible-linux-baseline/actions/workflows/ci.yml/badge.svg)](https://github.com/Walaskien/ansible-linux-baseline/actions/workflows/ci.yml)

Ansible roles for the basic setup of a Linux server: users, time and packages, SSH hardening, firewall, Prometheus node_exporter. Written for Ubuntu, Debian and Rocky Linux; tested in containers of those three (see Verified).

Use it when you have a few servers that were set up by hand, each a little different, and you want one repeatable baseline that you can read, review and run again without changing anything that is already correct.

| Role | Does | Tag |
|---|---|---|
| `users` | accounts, SSH keys, passwordless sudo via the OS admin group (`sudo` / `wheel`) | `users` |
| `baseline` | packages, timezone, chrony (optional NTP servers), sysctl settings | `baseline` (`packages`, `time`, `sysctl`) |
| `ssh_hardening` | sshd drop-in: no root login, no passwords, limits; validated with `sshd -t` | `ssh` |
| `firewall` | nftables, default drop on input, SSH/ports restricted by source CIDR | `firewall` |
| `node_exporter` | node_exporter from the GitHub release (checksum verified), systemd unit, non-root user | `monitoring` |

Each role has its variables with comments in `roles/<role>/defaults/main.yml`.

## Use it on your servers

```console
python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt
cp -r inventories/example inventories/prod        # edit hosts and group_vars/all.yml
ansible-playbook -i inventories/prod/hosts.yml site.yml --check --diff     # dry run first
ansible-playbook -i inventories/prod/hosts.yml site.yml
ansible-playbook -i inventories/prod/hosts.yml site.yml --tags firewall,ssh --limit app01.example.com
```

Read before the first real run:

- **Do not lock yourself out.** `ssh_hardening` turns password login off by default, and `firewall` drops everything except SSH and the ports you list. Make sure your key is in `users_list` (or already on the server), keep a second SSH session open, and start with one host and `--check`.
- `users` adds keys; it does not remove keys that are already in `authorized_keys`.
- If SSH runs on another port, set `ssh_hardening_port` and `firewall_ssh_port` to the same value.
- The playbook assumes you connect as a user that can use `sudo`.
- node_exporter listens on all interfaces on `:9100`; the firewall role opens it only to `node_exporter_allowed_sources`.

Variables set in the example inventory (`inventories/example/group_vars/all.yml`) show the typical set. Addresses there are documentation ranges and the key is a dummy.

## Verified

Ansible-core 2.15.13, ansible-lint 6.22.2, yamllint, Python 3.9 on macOS; containers via Docker (Colima).

| Check | Result |
|---|---|
| `yamllint .` | no findings |
| `ansible-lint` | passed, 0 failures |
| `ansible-playbook --syntax-check site.yml` | OK |
| `tests/run-in-docker.sh ubuntu:22.04` | first run `changed=18, failed=0`; **second run `changed=0, failed=0`** |
| `tests/run-in-docker.sh debian:12` | first run `changed=18, failed=0`; **second run `changed=0, failed=0`** |
| `tests/run-in-docker.sh rockylinux:9` | first run `changed=19, failed=0`; **second run `changed=0, failed=0`** |
| `make test IMAGE=debian:12` (after the script change on 2026-11-12) | second run `changed=0, failed=0`; shellcheck and actionlint on the script and workflow pass |
| `make test` on `debian:12`, `ubuntu:22.04`, `rockylinux:9` (after adding a third run, 2026-11-12) | third run with `--check` also `changed=0, failed=0` on all three |
| GitHub Actions | `lint` job, and `converge` for `ubuntu:22.04`, `debian:12` and `rockylinux:9`; the script fails unless the second run and a third `--check` run report `changed=0`. The package setup in the script is retried because a mirror download once failed a Rocky run |

Container test details: `tests/converge.yml` applies all five roles to the container itself (local connection), then again. It runs with `manage_services=false` (no systemd in the container) and `firewall_validate=false` (no `CAP_NET_ADMIN`). The node_exporter download is served from a small local HTTP mirror inside the container with a dummy binary, so the download, checksum, unpack and install steps and their idempotence are tested, but not the real GitHub URL (it was not reachable from the test machine).

**Not verified:** starting and reloading services (systemd), `nft -c` validation of the generated ruleset, a real node_exporter binary, Rocky/Ubuntu on real hosts or VMs. Molecule is not used.

## Limits

- Level: practical baseline, not a compliance profile (no CIS/STIG claim). SSH ciphers are left at the distribution defaults.
- `sources` lists take IPv4 CIDRs. Ports without `sources` are open for IPv4 and IPv6, and the default-drop policy covers both.
- `firewall` replaces `/etc/nftables.conf` completely. If you manage rules for Docker/Kubernetes with nftables, do not use this role as is.
- Timezone is set through `/etc/localtime`, not `timedatectl`, so it also works in containers.
- Pinned to ansible-core 2.15 (see `requirements-dev.txt`), which is older than the releases that get fixes now. Not tried on newer ones.

## Repository layout

```
Makefile                  help, lint, syntax, test (IMAGE=debian:12)
site.yml                  playbook (roles in a sensible order, tags)
inventories/example/      hosts.yml, group_vars/all.yml
roles/<role>/             tasks, defaults, handlers, templates, vars
tests/                    converge.yml, run-in-docker.sh
.github/workflows/ci.yml  lint + container run
```

## What I would improve next

- Run the roles against a real VM (systemd, `nft -c`, real node_exporter download) instead of only containers.
- Add Molecule scenarios so each role can be tested on its own.
- Remove stale keys in `users` (today it only adds keys).
- Support a non-nftables firewall (ufw/firewalld) for hosts that already use one.

## Related

- [queue-saturation-observability](https://github.com/Walaskien/queue-saturation-observability): Prometheus rules and dashboards that use the node_exporter metrics this role installs.
- [mikrotik-site-to-site](https://github.com/Walaskien/mikrotik-site-to-site): config generator for the network side of the same kind of small estate.
