# docker.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: your containers as a screen, with their state, image, ports and uptime, and keys for logs, a shell, restart, stop and start. It can look at another host's docker too (`docker -H ssh://vps`).

Needs ranma v0.2.2 or newer, and the docker CLI (podman works through `docker.command`).

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/docker.lua`:

```lua
return { "masshirodev/docker.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/docker.ranma ~/.config/ranma/pack/plugins/start/docker.ranma
```

## What it does

```text
docker: containers as a screen.

leader D   (shift+d), `docker` in the palette, or ranma.emit("docker_open")
           opens a screen of the containers (`docker ps -a`), running ones
           first: each with its state, image, ports and how long it has
           been up (or since it exited). On it:
  enter  logs -f in a new pane         s  a shell in it (bash, else sh)
  r      restart (asks)                x  stop (asks)
  t      start a stopped one           i  inspect: the whole of
  h      the next host (docker.hosts)     `docker inspect`, on a view
  u      look again now
The list is fetched again every docker.refresh seconds, only while the
screen is open; nothing runs while it is closed.

Hosts: docker.hosts lists name=address pairs (`vps=ssh://vps`); `local`
is the docker the server's environment points at. `h` steps through them,
`docker [host]` opens on one. A pane opened for a remote container runs
`docker -H <address> …` there.

Panes (logs, shell) open beside the focused pane, in its workspace, as
`exec` does, named after the container.

Needs ranma 0.2.2 or newer, and the docker CLI.

ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Screens",
"Timers and processes", "Actions").
```

## Binds and commands

| Key / command | |
| --- | --- |
| `leader D` (shift+d, plugins group) | The screen of containers. |
| `docker [host]` in the palette (`leader :`) | The same, on a host from `docker.hosts`. |
| `ranma.emit("docker_open", host)` | The same, for a key or a bar module of your own (bar-extras.ranma's `docker` module opens it on a click). |

On the screen: `enter` logs, `s` shell, `r` restart (asks), `x` stop (asks), `t` start, `i` inspect, `h` next host, `u` look again, `/` filter, `o` options.

## Options

In ranma's settings panel under `docker`, or with hako's `opts`, or `ranma.set { docker = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `docker.hosts` | `"local"` | The hosts `h` steps through: `local`, and `name=address` pairs for `docker -H` (`vps=ssh://vps`), space-separated. |
| `docker.refresh` | `3` | Seconds between two looks while the screen is open. |
| `docker.command` | `"docker"` | The CLI to run; `podman` takes the same arguments. |

## Costs

One `docker ps -a` every `docker.refresh` seconds while the screen is open, through `ranma.spawn`, off ranma's thread; nothing at all while it is closed. Over `ssh://`, each look is an ssh connection unless the config multiplexes them (`ControlMaster`).

## Limits

- The stop and restart questions are the only guard: `r` and `x` act on the selected row once `y` answers.
- A remote host needs the docker CLI on this machine and SSH access with docker rights there; errors show on the screen's top edge.

## License

MIT or Apache-2.0, as ranma.
