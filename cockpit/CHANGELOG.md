# Changelog — Remote Pi Cockpit

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
As versões seguem o `version:` do `pubspec.yaml` (SSOT). O campo `notes` do
`latest.json` (VPS) deriva deste arquivo.

<!--
  ATENÇÃO: a PRIMEIRA seção `## ` deste arquivo é o texto que o usuário vê no
  diálogo de update (Sparkle/WinSparkle) e na página de download. Regras:

  - **Seções novas em INGLÊS** (a partir da 1.20.0). É texto user-facing, então
    vale a mesma regra da UI do app. As seções antigas ficam em português —
    são o que já foi publicado, não reescreva.

  - A seção da versão que está saindo fica no TOPO. O job `meta` do
    .github/workflows/cockpit-release.yml **falha a release** se a versão do
    primeiro `## ` não bater com a tag — foi assim que 1.16/1.17/1.18 saíram
    repetindo a nota da 1.15.4.
  - Nada de `## [Unreleased]` na frente: o guard reprova.
  - Markdown normal (parágrafo, `### Fixed`, lista, `**negrito**`, `código`) —
    o CI converte pra HTML (cockpit/packaging/release_notes_html.py) antes de
    pôr no appcast, então quebra de linha e formatação aparecem certinho.
  - O `notes` do latest.json (página de download) ainda usa só as 20 primeiras
    linhas não-vazias — o começo da seção deve fazer sentido sozinho.
-->

## [1.28.23] - 2026-08-29

**Still a beta for the upcoming 2.0.0.** Closing the app no longer crashes, and
listing databases from a terminal on a remote host works.

### Fixed

- **Closing the app no longer hangs for a few seconds.** It was not slowness:
  the app was crashing on every exit, and the pause you saw was the system
  writing a ~30 MB crash dump before the window went away. Destroying the
  window made the toolkit emit its final resize events, which the app answered
  by asking a window that no longer existed whether it was maximized.

  It had a second cost that was easy to miss: the app marked the exit as clean
  *before* the crash, so its own crash detector never saw the most frequent
  crash it had - one per close. Old dumps can be cleared with
  `coredumpctl --vacuum-size=0` on Linux.

- **`cockpit db` now finds the connections of a remote workspace.** The
  previous release stopped it from refusing the tab, but it then answered with
  an empty list on a workspace that has ten connections - worse than the error,
  because it looks like an answer. It was reading the connection file from the
  client's disk, where the host's folder does not exist. `db query` and
  `db schema` were affected too, reporting "no connection named ..." for
  connections that exist.

  Only the client needed this one; a host already on 1.28.21 needs nothing.

## [1.28.21] - 2026-08-29

**Still a beta for the upcoming 2.0.0.** Databases behind an SSH bastion now
work from a remote workspace, and the internal CLI stops refusing the very tab
it is running in.

### Fixed

- **`cockpit db` now works from a terminal on a remote host.** It answered
  "this pane has no workspace folder" for every remote tab, along with
  `list-tasks` and `read-task`. A remote workspace keeps its folder in a
  different field, and the CLI was reading the empty one - the panel in the app
  worked because it resolved the folder another way.

  This mattered more than a plain failure: agents do not stop at an error, they
  find another route. One of them worked around it by pointing at a *local*
  workspace and reported the state of a database running on the client machine
  as if it were the host's. A command that names a workspace on another machine
  now says so.

- **Database connections that go through an SSH bastion work from a remote
  workspace.** The tunnel is now opened by the host - the machine that can
  actually reach the bastion and holds the private key - instead of not being
  opened at all. The key and its passphrase live on the host, next to the
  database they reach.

  The first connection to a bastion the host has never seen will fail once, on
  purpose, and offer you its fingerprint to review. Trusting it is remembered on
  the host.

- **Renaming a database connection no longer loses its saved password.**
- **A Linux client connecting to a macOS host no longer drops a working
  connection.** It compared its own server binary against the host's, concluded
  the host was out of date on every boot, and tore down a connection that was
  working to attempt an install it cannot perform.

## [1.28.20] - 2026-08-29

**Still a beta for the upcoming 2.0.0.** One password store per machine, and
the background server now shuts down with the app.

### Fixed

- **A database password typed on the host now works from remote clients.**
  There were two separate stores on the same machine: opening a workspace
  locally saved the password to the OS keychain, while a remote client saved it
  to the host's file. The background server has no way to read the OS keychain -
  it starts over SSH, with no desktop session - so a password you typed while
  sitting at the host was never found from anywhere else. You saved it
  successfully and the remote kept reporting it as missing. There is now one
  store per machine, and passwords already in the OS keychain move into it the
  first time they are used - nothing to retype.

  The key is now derived from the workspace folder rather than an id generated
  per machine, which is what made the same connection look different from every
  client.

- **The background server no longer outlives the app.** Closing Cockpit left
  `cockpit-server` running. Because an update replaces its file on disk while
  the old process keeps running the old code, a machine used as a host could
  serve a stale version indefinitely - silently, since nothing errors. It now
  exits with the app, including when the app is force quit or crashes.

### Note on where passwords live

Local workspaces moved off the OS keychain to the same encrypted file the host
uses. The keychain is stronger in principle - it prompts when an unauthorized
program reads an item - and the file does not. That trade buys one place
instead of two, which is what makes "configure it once, use it from anywhere"
true. Passwords for connections you would rather not store at all are still
better left unsaved.

## [1.28.19] - 2026-08-29

**Still a beta for the upcoming 2.0.0.** The database passwords stored on a
remote host are no longer kept as plain text on disk.

### Changed

- **The host's database password store is now encrypted.** Passwords that a
  client saves on a remote host used to sit in a plain-text file. They are now
  encrypted (AES-GCM) in the same file, with a product key built into the app -
  the same approach DBeaver takes for its saved credentials. Nothing to do on
  your side: an existing store keeps working and is rewritten encrypted the
  next time you save a password.

  Worth knowing what this does and does not cover. It takes the secret out of
  plain text on disk, which is what protects you from the realistic accident -
  a backup, a synced folder, a search across files, a screenshot. It is not a
  defense against someone already running programs under your account on the
  host: the key ships with the app, and it has to, because the server starts
  over SSH with nobody there to type anything. Anyone with that level of access
  to the host can reach the databases through it regardless.

## [1.28.18] - 2026-08-29

**Still a beta for the upcoming 2.0.0.** Remote hosts get two fixes that made
them unusable in common setups - password login and remote databases - plus a
way to close tabs from the internal CLI.

### Fixed

- **Remote hosts registered with a password now actually use it.** The password
  was saved correctly but never offered: SSH tried key authentication first and
  the stored password was never reached, so the connection failed with
  "Permission denied (publickey)" or "Too many authentication failures". Exactly
  the case of someone who chooses password *because* their key does not work.
- **Databases of a remote workspace now work from any client.** The connection
  was defined on the host and the query ran on the host, but the password was
  looked up on the client under a key derived per machine - so a connection set
  up on one computer was never found from another, and it silently connected
  without a password. The password now lives on the host, next to the database
  it opens, and never travels over the wire. Saving or editing a connection of a
  remote workspace also works now; before, it failed before writing anything.
  A connection you already had keeps working: open it once and the old password
  is moved to the host for you.
- **Adding a workspace no longer repeats itself.** The "+" menu said "New local
  workspace" / "New remote workspace" on both entries; it now reads **Local** and
  **Remote**.

### Added

- **`cockpit close-tab`** in the internal CLI - the counterpart of `new-tab`,
  which could open tabs but never close them. Takes a tab id or a stable tab
  label; with no target it closes the tab you are in.

### Known limitation

- A database connection that goes through an **SSH tunnel** (bastion) still does
  not work from a remote workspace: the tunnel is described on the host but
  nothing opens it there yet. Connections without a tunnel are unaffected.

## [1.28.17] - 2026-08-27

**Still a beta for the upcoming 2.0.0.** Three Windows fixes, all reproduced and
verified on a real Windows 10 machine.

### Fixed

- **Cockpit no longer opens to a blank screen on Windows.** A workspace with no
  saved layout would build its pane tree without telling the interface, so
  everything below the title bar stayed empty until you clicked something -
  typically opening the workspaces rail, which made the whole screen appear at
  once. Most visible on a fresh install, where no workspace has a saved layout
  yet.
- **The internal CLI now installs reliably.** Every boot logged a failure while
  copying `cockpit.exe` into place, because the Claude and Codex hook installers
  raced each other writing the same file.
- **Closing a tab really does kill the whole process tree now.** The fix shipped
  in 1.28.16 did not take effect: it corrected a code path that terminals no
  longer use, and the Job Object it relied on turned out not to contain the
  shell's children. A `ping -t` started in a tab survived the tab being closed;
  now it does not.

## [1.28.16] - 2026-08-27

**Still a beta for the upcoming 2.0.0.** A big responsiveness fix for remote
sessions on iPad and Android, plus two additions on the desktop side.

### Fixed

- **Remote sessions no longer freeze on iPad and Android.** Connecting to a
  host would get slower and slower until the app stopped responding
  altogether — file tree, terminal, tasks, everything. Cockpit was issuing far
  more requests to the host than it needed: worktree listings piled up on every
  reconnection attempt, workspace roots were discovered twice on every boot,
  and the folder scan fired dozens of listings at once through a single SSH
  channel. On a Mac this was invisible; on mobile, where the SSH encryption
  shares the thread that draws the screen, it was enough to lock up the app.
- Windows terminals no longer leave orphaned PowerShell processes behind when a
  tab is closed. Closing a tab now terminates the whole process tree it
  started, instead of only the shell itself.

### Added

- **Close the focused tab with ⌘W** (Ctrl+W on Windows and Linux). Tabs with
  unsaved changes still ask before closing.
- **Swap side panels.** A new option under Appearance → Layout moves the
  workspaces rail to the right and files/search/git/database to the left.

## [1.28.15] - 2026-08-26

**Still a beta for the upcoming 2.0.0.** Windows machines can now be used as
remote hosts, and several remote-terminal fixes land alongside it.

### Added

- **Windows as a remote host.** You can connect to a Windows machine over SSH,
  install the server there and open remote terminals and workspaces, from any
  client — including macOS and iPad. Previously Windows hosts were refused.

### Fixed

- Remote terminals on a Windows host opened forever empty: the host tried to
  start `/bin/sh` instead of its own login shell. It now falls back to
  PowerShell (or `cmd` on Windows ARM). Requires updating Cockpit **on the
  host** as well.
- Connecting from iPad or Android to a Windows host failed with an obscure
  `open failed` error, because the host was mistakenly detected as Linux/macOS.
- When a host advertises a server that is no longer running, the error now says
  so instead of showing a raw SSH channel failure.
- Picking a folder on a Windows host produced mixed separators
  (`C:\Users\you/folder`), and the "go up" button jumped straight to the root
  instead of the parent folder.
- A pinned remote workspace on a Windows host showed the full path instead of
  the folder name.
- Terminal font metrics on Linux are aligned again (thanks, @pretodev).
- Builds could silently package an outdated remote server; the packaged server
  now rebuilds when the engine changes.
- Diagnostics were completely silent on clients without a log file (iPad); they
  are now always mirrored to the console.

## [1.28.14] - 2026-08-26

**Still a beta for the upcoming 2.0.0.** The `cockpit` CLI now has a short
name, connecting to a Windows machine says what is actually wrong, and closing
the window no longer hangs.

### Added

- **`ck` is the same command, shorter.** `ck list-tabs` == `cockpit list-tabs`,
  in local and remote terminals. If you already have your own `ck` alias, yours
  still wins.

### Fixed

- **The remote CLI answered from the wrong device.** With two Cockpits attached
  to the same host (say a desktop and an iPad), a command typed on one could be
  answered by the other, listing tabs you were not looking at. Commands now go
  to the Cockpit that owns the tab.
- **Pointing at a Windows machine failed with `FormatException: Missing
  extension byte`.** That was never about the server: Windows replies in the
  local codepage, and reading it as UTF-8 blew up on the first accented
  character, hiding the real error. Cockpit now says plainly that it connects
  *from* Windows, but a Windows machine cannot be the host yet.
- **Closing the window looked frozen on Windows.** Each shutdown step now has a
  two-second ceiling and is timed, so the app closes instead of waiting — and
  the diagnostics log records which step was slow.
- Typing an accent in a terminal on iPad no longer freezes it for good; it
  still stalls until you switch tabs and back, and the accent may be lost.

## [1.28.13] - 2026-08-26

**Still a beta for the upcoming 2.0.0.** Fixes for worktrees on remote
workspaces, and the host's server finally updates itself.

### Fixed

- **The server on your host never updated.** Once installed, it stayed on that
  version forever, so nothing the server learned later ever reached you — the
  remote `cockpit` CLI answered nowhere and last release's Source Control fixes
  never showed up. The app now notices an outdated binary, replaces it and
  restarts it. **This closes the terminals open on that host, once, the first
  time you connect after updating.**
- **Clicking a worktree could show the parent workspace instead.** A hiccup on
  the SSH connection was read as "this workspace has no worktrees", which
  dropped them from the rail and moved your selection back to the parent.
  Restarting the app appeared to fix it because the next listing worked.
- **A worktree opened empty, losing its tabs.** Selecting one gave you a blank
  pane instead of the layout you left there, and a `claude` running in it never
  came back. Its saved layout was only read at startup, before worktrees were
  known — and, worse, the scrollback of its terminals was being deleted on every
  launch. Both fixed, for local and remote worktrees.

## [1.28.12] - 2026-08-26

**Still a beta for the upcoming 2.0.0.** Remote workspaces catch up with local
ones: multi-repo folders work over SSH, and the `cockpit` CLI now answers in
remote terminals. Plus a round of fixes for iPad and Android.

### Added

- **Multi-repo works on remote workspaces.** Point one at a folder holding
  several repositories and you get what you already had locally: the tree split
  per repo, the aggregate badge on the rail, worktrees listed for every repo,
  and git actions targeting one repo at a time.
- **`cockpit` works in a remote terminal.** An agent over SSH can query the
  workspace's databases, read another tab, send text to it, open a file or a new
  tab — all handled by the Cockpit on your machine. Commands whose argument
  belongs to the other machine (`browse`, `http`) say so instead of doing the
  wrong thing quietly.

### Fixed

- **A hidden folder with changes showed up as a file in Source Control.** A new
  `.cockpit/` appeared as a single entry named `.cockpit` on remote workspaces;
  its files are now listed one by one. Renames no longer leave a phantom entry
  with a clipped name, and ignored folders are treated as ignored.
- **Opening a text file on a remote workspace could spin forever.** The content
  arrived but the tab kept showing the spinner until you switched tabs and came
  back.
- **iOS asked for local network permission at the worst moment.** Adding a host
  on your network failed and showed the permission dialog at the same time,
  working only after restarting the app. The dialog now comes up on launch.
- **On iPad and Android**, the redundant "SSH" badge is gone (every workspace
  there is remote), a long press opens the context menu on the workspace rail,
  and the worktree chevron gave way to a double tap on the card.

**Heads up:** update the server on your host to get the Source Control fixes
and to have the CLI answer there.

## [1.28.11] - 2026-08-25

**Still a beta for the upcoming 2.0.0.** `.http` files now open as a request
tab: write a request, hit it, read the response, without leaving Cockpit.

### Added

- **A tab for `.http` files.** Open one and you get an editor on top and the
  response below, the same shape as the `.dbq` database tab. Run the request
  under the cursor with ⌘↵, or pick another one from the selector in the top
  bar. The footer shows status, time and size, with the response as **JSON**
  (parsed and indented), **Headers**, or **Text** (exactly what came back).
- **The syntax you already write.** `.http` files follow the REST Client /
  JetBrains HTTP Client format: `###` separates and names requests,
  `@name = value` declares a variable, `{{name}}` uses it, and `< ./body.json`
  sends a file as the body. Syntax highlighting for all of it, plus JSON
  highlighting in the response.
- **`cockpit http list` and `cockpit http run` in the CLI.** Agents can fire a
  request from a `.http` file and read the response as JSON — same engine as
  the tab. Write the file and a human can open, tweak and re-run it.

Requests that fail before touching the network — an undeclared `{{variable}}`,
a URL missing its scheme, a missing body file — say exactly what is wrong
instead of putting a placeholder on the wire. A 4xx or 5xx is a normal
response, not an error.

## [1.28.10] - 2026-08-25

**Still a beta for the upcoming 2.0.0.** Commit message automations work again,
and the workspace list behaves the way you expect. Thanks, @pretodev.

### Fixed

- **Generating a commit message failed on three harnesses.** Pi offered a model
  its own runtime then refused; OpenCode returned an empty message and hid the
  real reason; Copilot ran without proper isolation. All three are fixed, and
  errors now reach the screen instead of vanishing.
- **Clicking a workspace no longer expands its worktrees by accident.** The
  card selects, and the chevron next to it toggles the list on its own.
- **Right-clicking a remote workspace opened no menu and removed the pin
  right away.** It now opens the menu at the cursor, like every other item.
- The workspace list is lighter with many workspaces open.

### Changed

- **The model list only offers what your account can actually use.** Each
  harness reports its own models now, and where one routes automatically
  (Copilot, Claude Code) Cockpit stops pretending you can choose.

### Added

- **`previewOpen` in `.cockpit/tasks.json`** (`always` / `start` / `never`):
  with `start`, restarting a task no longer reopens the browser every time.
- Structured JSON logs are colorized in the task terminal.

## [1.28.9] - 2026-08-21

**Still a beta for the upcoming 2.0.0.** Several fixes around remote hosts,
databases and the workspace list.

### Fixed

- **Editing or removing a remote host did nothing.** The change was never
  saved, and no error showed up — adding a host worked, which made it look
  arbitrary. Picking your SSH key is also friendlier now: choosing the `.pub`
  file by mistake no longer fails with a confusing message about file
  permissions, and hosts already saved that way are corrected automatically.
- **Databases reordered themselves.** Saving a connection sent it to the bottom
  of the list. Connections are now always listed alphabetically, and the
  `databases.json` file in your repository is written in that order too, so
  saving stops producing noisy diffs.
- **Reordering workspaces took about two seconds** to settle after the drop.
  It is immediate now. Deleting a realm with many workspaces was slow for the
  same reason and is fixed as well.
- **Markdown containing a LaTeX formula could crash the app.**
- After an update, Cockpit no longer keeps talking to the background server
  left behind by the previous version — which is how a shipped fix could end
  up never running.

## [1.28.8] - 2026-08-20

**Still a beta for the upcoming 2.0.0.** The Windows terminal fix, this time
verified on Windows before shipping.

### Fixed

- **Windows: local terminals opened empty and ignored typing.** The shell was
  inheriting the wrong input and output, so its screen never reached the tab and
  it saw its input as already finished. 1.28.7 aimed at the wrong half of this
  and did not fix it; this one was tested against the real setup before release.

## [1.28.7] - 2026-08-20

**Still a beta for the upcoming 2.0.0.** Finishes the Windows terminal fix
started in 1.28.6.

### Fixed

- **Windows: local terminals opened and immediately froze.** The tab appeared,
  even picked up a title, and then nothing — no prompt, no reaction to typing.
  The shell was being started with an invalid input handle, so it read
  end-of-input and quit the moment it launched. PowerShell users may also stop
  seeing the "console is running without PSReadLine" warning, which had the
  same cause.

## [1.28.6] - 2026-08-20

**Still a beta for the upcoming 2.0.0.** Fixes local terminals on Windows,
broken by 1.28.5.

### Fixed

- **Windows: local terminals stopped opening in 1.28.5.** A tab would open and
  stay blank forever. The background terminal server had never actually run on
  Windows — it died on startup, and Cockpit quietly used its built-in terminal
  instead. A fix in 1.28.5 kept the server alive, which exposed a second bug in
  it: a terminal started without a folder failed to launch the shell at all.
  Both are fixed. Remote terminals from Windows keep working.

## [1.28.5] - 2026-08-20

**Still a beta for the upcoming 2.0.0.** One crash that could take every
terminal down at once, and remote terminals working from Windows.

### Fixed

- **All your terminals could go dead at once.** The background server that owns
  them quit outright whenever a client disconnected at the wrong moment, taking
  every workspace's terminals with it. It now survives that, shuts down within
  seconds when asked instead of hanging around, and a leftover server from a
  previous window closes itself rather than lingering forever.
- **Windows: remote terminals opened empty.** Picking the folder worked and the
  workspace appeared, but the tab never showed anything, because Cockpit asked
  the remote machine to start *its own* shell — PowerShell on a Mac. The host
  now chooses its shell, and Cockpit no longer sends its local `PATH` along,
  which would have broken the remote shell anyway.
- The markdown preview scrolls like the rest of the app, without the rubber
  band bounce at the edges (macOS 13+).

## [1.28.4] - 2026-08-19

**Still a beta for the upcoming 2.0.0.** The markdown preview looks like the
rest of the app again.

### Fixed

- **The markdown preview ignored your theme entirely** — white background and a
  serif font, no matter which theme the app was using. Its stylesheet was never
  reaching the page. It now follows the theme, and switching between light and
  dark while a preview is open recolors it right away instead of waiting for
  the file to be reopened.
- **Frontmatter is rendered again.** The `---` header block at the top of
  `SKILL.md` and `agent.md` files was being spilled into the document as loose
  text; it is shown as a key/value table, the same one you already saw
  elsewhere in the app.
- The workspace list no longer repeats the branch icon next to the "N
  worktrees" line — it belongs to the worktrees listed underneath.

## [1.28.3] - 2026-08-19

**Still a beta for the upcoming 2.0.0.** Windows can reach remote hosts again.

### Fixed

- **Connecting to a remote host from Windows always failed** with `Bad local
  forwarding specification`. Cockpit was asking SSH to open the local end of
  the tunnel as a Unix socket, which Windows does not have — the path was not
  even parsed, because the `C:` in it reads as a separator. Windows now uses a
  local loopback port instead. Nothing changes on the machine you connect to.
- **A host that already had the server installed could refuse to start it**
  when the two machines ran different operating systems. Cockpit now starts the
  server that is already there, and only declines when it would actually need
  to copy a new one over.

## [1.28.2] - 2026-08-19

**Still a beta for the upcoming 2.0.0.** Connecting to a machine you have never
connected to before now works from the app itself.

### Fixed

- **A remote host you had never connected to could not be added at all.** SSH
  refused it with "Host key verification failed" and the only way out was to
  open a terminal and connect by hand once. Cockpit now shows you the host's
  fingerprint and asks whether to trust it, the same way it already did for
  database tunnels. A host presenting a **different** key than the one it
  presented before is still refused, with no way to accept it inline — that
  case is either a reinstalled machine or an attack, and it deserves a look.
- **Connection errors said `@` instead of the host name**, and a host that
  answered but was not trusted was reported as unreachable, sending you to
  check whether the machine was even turned on.

### Added

- **Pick the SSH private key when you register a host.** It is required for
  key authentication on macOS, Linux and Windows, and the file dialog opens
  straight in your `.ssh` folder. On a machine with many keys this is what
  keeps the server from rejecting you for too many authentication attempts
  before your real key is ever tried. Hosts you registered earlier keep
  working as they did.

## [1.28.1] - 2026-08-19

**Still a beta for the upcoming 2.0.0.** This one is about terminals opening
instantly again — and about the terminal engine behind them actually running
on your machine.

### Fixed

- **New terminal tabs took about 6 seconds to open.** Every tab waited on a
  background server that could never start, then quietly fell back to the old
  in-process terminal. The server binary was being mangled while the app was
  packaged, so it failed to launch on both Intel and Apple Silicon Macs. It is
  packaged correctly now, and when a server does fail the app falls back
  immediately instead of waiting.
- **Windows: same delay, different cause.** The terminal server could not
  listen at all on Windows. It now uses a local loopback connection with a
  token, so it works there like it does elsewhere.
- **Connecting to a remote host could fail without saying why.** The app now
  picks the server build that matches the remote machine, refuses hosts it
  cannot support with a clear message, and checks that the server really
  started instead of assuming it did. Bootstrapping a remote host from Linux
  installed a server that could not start at all; fixed.
- **Accented characters were mangled in the file editor and diffs** — `ação`
  showed up as `Ã§Ã£o`. Thanks, @pretodev.

## [1.28.0] - 2026-08-18

**A beta for the upcoming 2.0.0.** Everything here is meant to ship as 2.0.0
once it settles; this release puts it in your hands first, so expect rough
edges in the new remote and mobile paths and please report what you hit.

Remote workspaces over SSH: open a folder on another machine and use it like a
local one — terminals, files, editor, source control and databases all running
on the host. The app also runs on iPad, iPhone and Android as a remote client.

### Added

- **Remote workspaces over SSH**: connect to a host, pick any folder on it, and
  work there. Sessions live on the host, so closing the app does not kill what
  is running there. A workspace now also shows which machine and folder it uses.
- **Mobile client (iPad, iPhone, Android)**: the same workspace from a tablet or
  phone. Panels become drawers on narrow screens, and tabs scroll and reorder by
  touch.
- **Terminal key bar on mobile**: the keys a phone keyboard lacks — ESC, Tab,
  Ctrl+C, arrows, F1–F12 — plus copy and paste, right above the keyboard.
- **Automatic reconnect**: when a host drops, Cockpit keeps retrying and shows a
  banner with a Reconnect button. Terminals freeze instead of closing and resume
  where they stopped once the host is back.
- **Collapse worktrees per workspace**: each workspace remembers whether its
  worktree list is expanded. Thanks, @fabiojansenbr.

### Fixed

- **Terminals no longer mirror each other** when a workspace restores with more
  than one pane, and splitting a pane no longer crashes the terminal view.
- **Selection in the browser and in the markdown/HTML preview lands where you
  click** on macOS; it used to drift further the lower you went.
- **The built-in browser no longer gets the legacy version of websites.**
- **A remote terminal is no longer left mute after reconnecting**: if the host
  restarted and the session is gone, the tab closes instead of ignoring input.
- **Creating a worktree now carries your uncommitted changes over**, instead of
  leaving them behind in the original checkout.
- **Windows stays responsive after being minimized**, and the Windows build no
  longer fails with error C1041. Thanks, @fabiojansenbr and @jeferson-m-bruno.

## [1.27.1] - 2026-08-17

A built-in browser, git change marks in the editor, and a fix for agents
stalling while the window sat in the background.

### Added

- **Built-in browser pane**: open a web page right inside Cockpit, with a
  compact toolbar (back, forward, reload, address). The tab is persisted and
  reopens on the last URL.
- **Markdown and HTML preview**: `.md`, `.mdx` and `.html` files render in a
  themed preview, with relative images resolved inside the workspace.
- **Auto-open on tasks**: the first local URL a task prints opens the browser
  automatically. Control it per task in `tasks.json` with `"preview"`.
- **`cockpit browse <url>`**: open (or reuse) a browser tab from the CLI.
- **Git change marks in the code editor**: added, modified and removed lines
  show in the gutter and as ticks in the scrollbar lane; clicking a tick jumps
  to that line.
- **Harness icons on terminal tabs**: Claude Code, Codex, Cursor, GitHub
  Copilot, Antigravity and OpenCode each get their own icon.
- **Full name on hover**: truncated tab and worktree labels reveal the complete
  text in a tooltip.

### Fixed

- **The window no longer freezes ("Not responding") on Windows when writing to
  a terminal whose shell stopped draining input.** ConPTY input now runs on a
  dedicated writer thread per terminal, so a suspended or stuck child process
  cannot block the UI, including during large pastes. macOS/Linux terminals
  were never affected.
- Agents no longer stall mid-request when the window is in the background:
  macOS App Nap was throttling the terminal's child processes. The machine can
  still sleep on idle as usual.
- A maximized window reopens maximized instead of merely screen-sized, and a
  window saved on a monitor you no longer have is pulled back into view.
- The last line of a file is no longer hidden under the horizontal scrollbar.

## [1.26.0] - 2026-08-11

Codex tabs now report what they are doing, just like Claude Code tabs.

### Added

- **Turn status for the Codex CLI.** A tab running `codex` now shows the
  spinner while it works, raises the attention badge when it asks for approval,
  and plays the completion sound when the turn ends — the same treatment Claude
  Code tabs already had. Notifications when the window is in the background work
  too.
- Cockpit sets this up on its own at startup, including Codex's hook trust, so
  there is nothing to enable or approve by hand. Your own Codex hooks are left
  untouched, and the rest of `config.toml` is never rewritten. Requires Codex
  CLI 0.147 or newer; if Codex isn't installed, nothing is created.
- **Restoring a tab reattaches the right session.** Cockpit now remembers which
  agent a conversation belongs to, so a restored tab resumes with `codex resume`
  or `claude --resume` accordingly.

## [1.25.1] - 2026-08-11

A smoother terminal under heavy output, and realm switching that remembers where you were.

### Fixed

- The window no longer freezes when a command floods the terminal with output.
  PTY output now shares a frame-time budget across every terminal, and hidden
  terminals stop painting entirely instead of competing for the frame. Thanks,
  @pretodev.
- Switching realms (keyboard shortcut or the realm picker) now brings you back to the
  worktree you were working in, not to its main workspace. If that worktree is
  gone, focus falls back to the workspace it belonged to.
- The tab bar scrolls horizontally with the mouse wheel again when there are
  more tabs than fit the panel. Thanks, @pretodev.

## [1.25.0] - 2026-08-09

Sounds you can tell apart, worktrees you can configure, and one less crash.

### Added

- **A sound per event.** Turn completed, action required and agent error each
  get their own sound, with a volume control, a preview button, and the option
  to play even when the tab is already active. Any of them can be swapped for
  an audio file of your own, or reset back to the default.
- **Advanced settings when creating a worktree** (thanks, @pretodev). A
  collapsed section adds: pick the **base branch** instead of always branching
  from the current HEAD, **fetch the remote** first so that base is up to date,
  and copy **ignored** (`.env`, local keys) or **untracked** files into the new
  worktree.
- **Flexoki theme** (thanks, @pretodev), the first built-in that brings its own
  syntax palette rather than reusing GitHub's.

### Fixed

- **Closing the selected workspace could take the app down with it** (thanks,
  @jamesldr). The terminal was freed while its view was still on screen, and
  the next frame touched memory that was already gone. Being a native crash, it
  left nothing behind in the logs. Teardown now waits for the views to leave
  before releasing anything.

## [1.24.0] - 2026-08-07

Git history, a real font picker, and clickable paths that actually click.

### Added

- **Git history panel.** Browse the repository's commits, see which files each
  one touched, and open the change in the editor from there (thanks,
  @HumbertoChiesi).
- **Font picker.** Pick interface, code and terminal fonts from the families
  installed on the machine, each name drawn in its own font, with search. Typing
  an exact family name by hand still works.
- **Terminal size and weight of their own.** The terminal no longer has to
  follow the code size, and the stroke weight is now a setting. Auto lightens it
  on low-density screens, where the same font renders heavier, and leaves Retina
  untouched.
- **Copy branch** in the workspace menu. In a multi-repo workspace it opens a
  submenu with one entry per root, like Pull and Push.

### Fixed

- **Clicking a relative file path in the terminal did nothing.** Absolute paths
  opened, so the failure was easy to miss, but `lib/foo.dart:12:3` is exactly
  what `dart analyze` and `flutter test` print. Paths are now resolved against
  the tab's directory. The same click now works in a task's output pane, which
  had no handler at all.

## [1.23.0] - 2026-08-06

Themes: eight of them, and any JSON file can become one.

### Added

- **Themes.** One choice now paints the whole app: interface, code highlighting
  and terminal palette together. Eight come built in, from the official
  **Cockpit** to **Pantera** (pure black in dark, pure white in light), each
  with a light and a dark variant picked by the new **Mode** setting.
- **Import and export themes**, in Settings, Appearance. A theme is a single
  JSON file you can share, version or edit by hand: declare only the tokens you
  want to change and the rest is inherited. Format in `docs/theme-format.md`.
- **Live preview** of how code and terminal will look, in the Appearance tab.
- **Middle-click a tab to close it** (thanks, @thKali).

### Fixed

- **"Cockpit closed unexpectedly" on every launch (Windows).** Closing through
  the title bar X destroyed the window without Cockpit noticing, so the next
  launch always assumed a crash, and dismissing the notice did not help because
  the notice is not what clears it. Cockpit now handles the closing itself.
- **Code and terminal share the tab's background**, instead of two neighbouring
  tabs showing two different shades of black with a seam between them.
- Text over the accent color is picked by measuring contrast instead of
  assuming white, so a light accent no longer gets unreadable labels.
- Closing a workspace no longer floods the console (thanks, @thKali).

## [1.22.0] - 2026-08-05

A focus overhaul for the terminal, plus a rescue for workspaces whose folder is
gone.

### Fixed

- **The terminal would stop taking the keyboard mid-session.** Typing went
  nowhere, the cursor stopped blinking, and the only way back was clicking the
  tab header. Two separate gaps caused it: clicking inside a terminal that had
  lost focus could not restore it, and switching realm or workspace left the
  keyboard behind on the previous pane while the new tab already looked
  selected. Both paths now hand the keyboard over.
- **Deleting a workspace folder no longer bricks the app.** Cockpit used to
  hang on the loading screen forever, with nothing on screen to explain it,
  because restoring a terminal in a folder that no longer exists failed the
  whole boot. Now the terminal opens in the nearest folder that does exist and
  says so, and a workspace that fails to restore no longer stops the rest.
- Images in the viewer kept showing the previous version after the file changed
  on disk, even after closing and reopening the tab.
- Duplicate scrollbars in the code editor. Thanks, @pretodev.

### Added

- **Creating a worktree now shows git's output live**, including anything your
  post-checkout hook prints, instead of freezing the dialog until it finishes.
  The dialog also warns beforehand when the repository has such a hook. Thanks,
  @pretodev.

## [1.21.0] - 2026-08-05

Cockpit now speaks your language, and can write your commit messages for you.

### Added

- **Interface in English, Português (BR) and Español.** Cockpit follows your
  system language on first launch and falls back to English when the system
  language isn't supported. You can pin one in **Settings → General →
  Language**; the whole window, including the menu bar, switches immediately.
  Thanks, @tecrodrigocastro.
- **Commit messages written by a coding agent.** Pick a CLI you already have
  installed in **Settings → Automations** (Pi, Claude Code, Codex CLI, Gemini
  CLI, OpenCode or Copilot CLI), optionally pick a model, and a **Generate**
  button shows up in Source Control and in the per-file commit dialog. Only the
  diff you're committing and your recent commit subjects are sent, common
  credential patterns and sensitive files are stripped first, and nothing is
  committed until you review the message. Thanks, @pretodev.
- The Source Control list/tree toggle now sticks across sessions and
  workspaces.

### Fixed

- The window no longer freezes when a terminal produces a burst of output, such
  as a busy TUI redrawing. Thanks, @pretodev.
- Language servers that failed to start are no longer left running in the
  background.
- Choosing a workspace photo now opens the file picker in the workspace folder.

## [1.20.0] - 2026-08-04

The internal CLI was rewritten in Rust. It now works on Intel Macs, can be
called from outside the app, and can submit what it types.

### Added
- **`cockpit send --enter`**: types the text and presses Enter in one call,
  instead of always pairing `send` with `send-key Enter`.
- **`cockpit send --focused`**: targets the tab you are looking at, so external
  tools (a dictation app, a script) no longer need a tab id to type into.
- **The CLI works from outside a Cockpit terminal.** With no environment
  inherited it finds the running app by itself, and `list-tabs` now marks which
  tab is focused.

### Fixed
- **Intel Macs had no internal CLI and no Claude turn status.** The app itself
  was universal, but its two helper binaries were Apple Silicon only, so the
  `cockpit` command and the spinner/chime silently did nothing there.

### Changed
- The `cockpit-hook` helper is now `cockpit hook`, a subcommand of the CLI. One
  binary instead of two: the app is about 11 MB lighter, and the hook that runs
  on every Claude event starts in milliseconds.

## [1.19.0] — 2026-08-02

Precisão do mouse: menus, foco de pane e seleção de texto voltam a cair onde
você clica. E a nota que aparece no update finalmente é legível.

### Added
- **Frequência da verificação de update** em Configurações → Updates: diária,
  semanal, mensal ou nunca (obrigado, @OrlandoEduardo101).

### Fixed
- **Menus e dropdowns abriam fora do lugar** com "Interface size" diferente de
  14 — menu de contexto da aba, opções do workspace e as listas das
  Configurações. O erro crescia conforme a distância do canto da janela.
- **Clicar dentro do terminal não ativava o pane:** com vários agentes lado a
  lado, o clique era engolido e o que você digitava saía na aba anterior — às
  vezes só clicando na aba resolvia.
- **Seleção de texto escorregava depois de rolar** no markdown, no viewer de
  código e no diff: quanto mais rolado, mais a seleção saía abaixo do cursor.
- **Notas de update repetidas e ilegíveis:** o diálogo de atualização mostrava
  o texto de uma versão antiga, com o markdown cru e tudo numa linha só.
- Erro ao abrir as Configurações e falha de injeção na tela de update.

## [1.15.4] — 2026-07-28

Conexão de banco por túnel SSH: o Mongo em Atlas finalmente funciona.

### Fixed
- **Túnel SSH pendurava o primeiro comando pra sempre:** o registro de abertura
  em voo era limpo com `whenComplete(() => map.remove(key))` e o future passava
  a esperar por si mesmo — só o primeiro chamador travava, o que aparecia como
  "o painel carrega pra sempre mas a CLI responde".
- **Proxy SOCKS do túnel morria em silêncio** a cada teardown de pool do driver
  Mongo; agora é nosso, sobrevive a reset e o cache reabre quando ele cai.
- **Comando Mongo custava ~7s:** `anaki_mongodb` 0.1.7 devolve o `close()` na
  hora (era 5s, e 59s antes disso em `mongodb+srv://`).

### Added
- **Mongo escolhe o database:** URL de Atlas não traz database e o painel caía
  no `admin`, mostrando `system.*`. A conexão agora expande nos databases.
- **`cockpit mongo --database <nome>`:** o agente escolhe a base sem mexer no
  que o humano vê; sem database resolvível, erro listando as disponíveis.
- **"Copy name"** no menu da conexão (o nome que a CLI usa em `--db`).

## [1.14.6] — 2026-07-20

Correção de digitação de acentos no terminal.

### Fixed
- **Caracteres acentuados duplicados no terminal** (@pretodev, #66): o IME
  podia reenviar o mesmo caractere já commitado (dead keys como `´` + vogal),
  e cada reenvio ia pro PTY — `á` virava `ááá`. Agora cada commit é emitido
  uma única vez.
- **Build Linux com Clang novo:** warning legado do
  `flutter_secure_storage_linux` (nlohmann/json antigo) não derruba mais o
  build com `-Werror`.

## [1.14.5] — 2026-07-20

Drivers de DB com TLS de verdade (anakiORM atualizado) e tela de loading
no boot.

### Added
- **Tela de loading no boot** (@jamesldr, #65): a janela abre na hora com
  splash animado no tema salvo enquanto o setup roda atrás; falha no boot
  mostra tela de erro com Retry em vez de fechar sem feedback.

### Fixed
- **TLS nos drivers:** anaki_postgres 0.1.4 / anaki_mysql 0.1.5 compilados
  com rustls — `sslmode=require` funciona (antes: "SQLx was built without
  TLS support"). MySQL repassa `ssl-mode`, MSSQL repassa `encrypt`.
- **FFI:** fix de colisão de símbolos quando vários drivers anaki carregam
  no mesmo processo (sqlite/mssql/redis/mongodb 0.1.4).
- **New query:** o SELECT gerado pela árvore cita o nome da tabela na
  sintaxe do engine (`"Tabela"`, backtick, `[colchete]`) — tabela CamelCase
  no Postgres quebrava sem aspas.

## [1.14.3] — 2026-07-20

Switch de SSL/TLS no dialog de conexão do Database.

### Added
- **Use SSL/TLS:** switch no dialog de conexão grava a forma certa por
  engine (Postgres `sslmode=require`, MySQL `ssl-mode=REQUIRED`, MSSQL
  `encrypt=true`, Mongo `tls=true`, Redis `rediss://`); OFF remove a chave
  preservando os demais query params. SRV (Atlas) implica TLS (switch
  travado). Necessário pra bancos gerenciados (RDS `rds.force_ssl` etc).

## [1.14.2] — 2026-07-20

Fix no parse de URL do Database.

### Fixed
- **Senha crua na URL:** conexão com senha sem percent-encoding
  (`user:8nJM9g8%?FC(@host`) falhava no parse e sumia da lista; agora o
  userinfo é re-encodado automaticamente ao carregar.

## [1.14.1] — 2026-07-20

Fixes no painel Database (Mongo Atlas).

### Fixed
- **Mongo Atlas (`mongodb+srv://`):** URLs SRV agora são reconhecidas; antes
  a entrada era tratada como engine desconhecido.
- **Painel Database:** uma conexão inválida no `databases.json` zerava a
  lista inteira; agora só a entrada com problema é pulada.
- **Editar conexão Atlas:** o dialog preserva o formato SRV e os query
  params da URL (antes reescrevia pra `mongodb://host:porta` e quebrava a
  conexão).

## [1.14.0] — 2026-07-20

Motores internalizados (terminal, PTY, frontmatter), CLI cria abas de
terminal e melhorias de multirepo/UI.

### Added
- **CLI `cockpit new-tab`:** agentes abrem abas de terminal (cwd, título,
  split) de dentro dos panes.
- **Multirepo:** Files volta à árvore única com seções por repo + popup de
  branches no badge da rail.
- **Guardrails de DB:** cada conexão define acesso read/readwrite e se fica
  visível pros agentes na CLI (default: só leitura).

### Changed
- **Motores absorvidos pro repo:** emulador de terminal (xterm) virou módulo
  interno; PTY nativo virou o plugin `cockpit_pty`; frontmatter YAML do
  markdown agora é pré-processamento próprio. Zero forks git no pubspec —
  markdown vem do pub.dev 1.1.8 (fix de links consecutivos incluso).

### Fixed
- Source Control mostrava pasta nova como arquivo; play/stop de Tasks sem
  resposta imediata; submenu e tooltips desalinhados sob zoom da interface;
  atalho ⌘`/⌘⇧` de realm parava após o primeiro uso.

## [1.13.0] — 2026-07-19

Novo: browsers visuais de Redis e MongoDB na tab Database — tabela de chaves
editável e collection browser estilo Compass, com abertura via CLI.

### Added
- **Redis key table:** clique na conexão abre a tabela key/value/type/ttl —
  edição inline (valor, TTL e rename de chave), compostos expandem com o valor
  completo, criação dos 5 tipos, SCAN paginado com busca por pattern.
- **Mongo collection browser:** collections no painel; documentos como cards
  JSON com highlight, filter bar JSON, editar/inserir/deletar por `_id`.
  Extended JSON (`$oid`/`$date`) preservado de ponta a ponta.
- **CLI `cockpit redis|mongo browse`:** o agente abre a view já filtrada pro
  humano (`--pattern` / `--filter`), sem expor credenciais.
- Logos de marca (Redis/MongoDB) nas abas dos browsers.

### Fixed
- `cockpit mongo` agora devolve ObjectId/Date como extended JSON canônico
  (antes saía hex/string ambíguos).

## [1.12.0] — 2026-07-19

Novo: acesso a bancos de dados direto no Cockpit — painel de conexões, tab de
query `.dbq` e a CLI `cockpit db` para os agentes.

### Added
- **Painel Database:** conexões por workspace (`.cockpit/databases.json`),
  SQLite detectado automaticamente, senha no cofre do SO. Árvore de schema
  (tabelas → colunas) e logos de marca por engine.
- **Tab de query `.dbq`:** editor SQL com highlight + grid de resultado (split
  arrastável), Run por statement sob o cursor, resultado como tabela ou JSON
  (copiável), buffers *untitled* (o arquivo nasce só ao salvar).
- **Engines:** SQLite, Postgres, MySQL e SQL Server (via anakiORM).
- **CLI `cockpit db list|schema|query|execute|run`** — JSON de uma linha para
  os agentes; execução no app, credenciais nunca passam pela CLI.
- **Redis e MongoDB via CLI** (`cockpit redis` / `cockpit mongo`) — acesso do
  agente sem UI por enquanto.

## [1.11.0] — 2026-07-18

Melhorias na árvore de Files (criação e reveal), no multi-root e na CLI interna.

### Added
- **New file/folder ciente da seleção:** cria dentro da pasta selecionada, na
  pasta-mãe do arquivo selecionado, ou na raiz quando nada está selecionado.
  Clicar numa área vazia da árvore deseleciona.
- **Revelar na árvore:** selecionar uma tab de arquivo destaca o arquivo no
  painel Files e expande as pastas-pai até ele.
- **Copy Absolute/Relative Path** no menu de contexto de cada repo (multi-root).

### Changed
- **CLI interna (`cockpit`):** nomenclatura alinhada pra *tab* — `list-tabs`,
  `read-tab`, `$COCKPIT_TAB_ID`. Os antigos `list-panes`/`read-pane`/
  `$COCKPIT_PANE_ID` seguem como aliases de compatibilidade.

### Fixed
- **Multi-root:** New file/New folder agora funcionam por repo (antes o botão do
  header não criava nada num workspace multirepo).
- **Multi-root:** o chip “N roots · M” contava divergência de upstream como se
  fosse alteração; agora conta só arquivos modificados.

## [1.10.1] — 2026-07-18

### Fixed
- **Commit falhava em repositórios com hook de `pre-commit`** que chama
  `npx`/`node` (ex.: `lint-staged`, `husky`, `simple-git-hooks`): o app roda com
  um PATH mínimo e o hook não achava o `npx` ("command not found"). O Source
  Control agora passa o mesmo PATH com `node` do terminal/tasks — o hook resolve.

## [1.10.0] — 2026-07-17

Workspaces multi-root pra quem trabalha com multirepo, mais git no Source
Control e novas ações de worktree.

### Added
- **Workspace multi-root:** pasta sem `.git` com repositórios dentro vira um
  workspace só — cada repo é uma root na árvore, com branch e status próprios;
  Sync/Pull/Push/worktree escolhem a root num submenu.
- **Source Control:** botão-direito no arquivo — View Diff, Commit (com dialog
  de mensagem validado), Unstage ou Discard; deletados aparecem riscados.
- **Worktrees:** "Update from Parent" (traz a branch do pai) e "Fork Worktree"
  (nova worktree a partir da branch do fork).

### Fixed
- Tooltips e menus de contexto abrindo fora do lugar (agora seguem o cursor e
  respeitam o tamanho da interface).

## [1.9.0] — 2026-07-17

Atalhos de teclado pra navegar o workspace, além de vários acertos no terminal,
nas Tasks e no visualizador de arquivos.

### Added
- **Selecionar aba por teclado:** ⌘1…⌘8 vão pra aba N da pane focada e ⌘9 pula
  pra última (View → Select Tab).
- **Navegar entre panes:** ⌘⌥ + setas move o foco pra pane vizinha na direção
  (View → Focus Pane).

### Changed
- **Visualizador de arquivos:** os botões Format/Discard/Save saíram da barra
  inferior — as ações seguem no menu File (e nos atalhos ⌘S / ⇧⌘F).
- **Worktrees** passam a morar em `.cockpit/worktrees` (antes `.pi/`), com
  `.cockpit/worktrees/` garantido no `.gitignore` do repo.

### Fixed
- **Spinner preso ao interromper o agente:** apertar ESC pra parar o harness
  agora apaga o indicador de "trabalhando" na hora.
- **Tasks:** o debug tab escreve "finished" ao encerrar, sinalizando o fim.

## [1.8.5] — 2026-07-16

Correções de Windows: o updater não reoferece mais a mesma versão, e o
PowerShell 7 aparece na lista de terminais.

### Fixed
- **Updater reoferecia a mesma versão pra sempre.** O VERSIONINFO levava o build
  number (`1.8.4+21`) e o appcast anuncia a versão marketing (`1.8.4`); o
  WinSparkle lê o `+` como texto e trata `1.8.4+21` como um pré-lançamento de
  `1.8.4`. Agora o VERSIONINFO publica só `x.y.z`.
- **PowerShell 7 não aparecia** no seletor do `+` nem nas Configurações: era
  tratado como substituto do `powershell.exe`, o alias MSIX escapava da detecção
  e o PTY duplicava o executável na linha de comando. "PowerShell 7" e "Windows
  PowerShell" agora são perfis separados.
- **Arrastar a janela pela barra de título com o dedo** não movia nada em telas
  de toque.
- Espaçamento do menu hambúrguer no Windows.

### Known issues
- **Teclado virtual não abre ao tocar** num campo. Não é do app: o Windows
  recusa exibi-lo mesmo pedido via COM, e nem o Notepad o levanta nesta
  configuração — ligue em *Configurações › Hora e idioma › Digitação › Teclado
  de toque*.

## [1.8.4] — 2026-07-16

### Added
- **Seletor de terminal (plano 50):** seta ao lado do `+` para escolher qual
  shell abrir, e Configurações › Terminal para definir o padrão (só Windows, onde
  há escolha real). Descoberta de PowerShell/cmd/distros WSL.
- Barra de menu do Windows/Linux recolhida num **menu hambúrguer**.

### Fixed
- **Self-update do Windows travado:** o WinSparkle não baixa sozinho nem avisa
  que baixou, então o card ficava eternamente em "Downloading v…" e o clique era
  no-op. O card agora vai direto para "click to install".
- **IME/acentuação no terminal do Windows:** o fork do xterm não passava o
  `viewId` no `TextInputConfiguration`, o `TextInput.setClient` era rejeitado e a
  digitação morria — o contorno era desligar o IME e ler teclas cruas.

## [1.8.3] — 2026-07-04

### Added
- **Self-update (plano 47):** Cockpit agora se atualiza sozinho no macOS e no
  Windows via Sparkle/WinSparkle (pacote `auto_updater`): checa e baixa em
  background, mostra "restart to install" no card do rail e troca o binário ao
  reiniciar. **Linux** segue no aviso + download manual (`latest.json`). O CI
  passa a publicar `appcast-macos.xml` e `appcast-windows.xml` (assinados EdDSA)
  ao lado do `latest.json`.

## [1.1.0] — 2026-06-12

### Changed
- Interface fully translated to **English** (all on-screen text, tooltips,
  dialogs, notifications and error messages). The machine name in the rail now
  shows the real hostname.

## [1.0.0] — 2026-06-12

Primeira release distribuível do Cockpit (cliente desktop do Remote Pi).

### Adicionado
- Identidade de release: app ID `work.jacobmoura.cockpit`, nome de exibição
  **Remote Pi Cockpit** nas três plataformas.
- macOS: Hardened Runtime no Release; build assinado com Developer ID +
  notarização + staple (DMG universal x86_64+arm64).
- Linux: integração de desktop (`.desktop`, ícones hicolor, AppStream
  `metainfo.xml`) e controles de janela na barra customizada.
- Windows: metadados do executável (CompanyName/ProductName) e controles de
  janela na barra customizada.
- Empacotamento via Fastforge: `distribute_options.yaml` + `make_config.yaml`
  de dmg/exe/deb/rpm.

### Funcionalidades do app (MVP)
- Multiplexador de panes por workspace: agentes (`pi --mode rpc`) e terminais
  lado a lado, com splits e abas.
- Árvore de arquivos com menu de contexto (criar agente/terminal numa pasta).
- Worktrees por workspace (clona a estrutura de panes pro fork).
- Onboarding que checa/instala `pi`, extensão `remote-pi` e supervisor.
- Agendamento de daemons e conectividade (pareamento via relay).
