# AGENTS.md

docker.ranma is a ranma plugin in Lua: `plugin/docker.lua` is all of it, and
its header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Keep to the API of the latest ranma release, which CI loads it into.
- Test stop, restart and start on a throwaway container of your own
  (`docker run -d --name ranma-docker-test python:3-alpine sleep 3600`),
  selected on purpose, and remove it after; never on someone else's
  containers. A remote host is tested against a bogus address, not a server.
- Every destructive key goes through `screen:ask`.
- Fetch only while the screen is open.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server. Test behaviour in a private server
  (its own `RANMA_CONFIG_DIR`, `XDG_RUNTIME_DIR` and tmux socket, with
  `RANMA_SOCKET RANMA RANMA_PANE TMUX` unset), never the one you are typing in.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
