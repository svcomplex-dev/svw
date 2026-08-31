<p align="right">
  <a href="./README.md">English</a> | <a href="./README.zh-CN.md">中文</a>
</p>

# svw — Simple Virtual Wave

**svw** brings fast, focused waveform debugging to the terminal for people,
automation, and AI agents.

Open a simulation dump and debug wherever you already work—locally, over SSH,
inside a CI container, or next to your editor—with the same focused terminal
workflow.

<p align="center">
  <img src="./showcase.gif"
       alt="svw interactive TUI showcase" width="100%">
</p>

## What is svw?

svw opens VCD, EVCD, and FST waveforms without extra setup. It presents
digital signals, buses, unknown states, and real-valued traces clearly in the
terminal. Gzip-compressed VCD/EVCD files (`.vcd.gz`) open transparently.

The interactive interface provides a fuzzy signal picker, markers, edge
navigation, zoom history, mouse controls, themes, a `:` command line, and a
`Space` leader menu. Color and glyph output automatically adapt to the
terminal.

## Why svw?

- **Pure terminal:** use the same focused workflow in local shells, SSH
  sessions, and containers.
- **Vim-style workflow:** use modal shortcuts, `:` commands, fuzzy search, and
  a discoverable leader menu.
- **Automation-ready:** repeat the same workflows through scripts or focused
  JSON/TUI queries.
- **Compare and analyze:** diff waveforms on a shared physical timeline and
  inspect reports, assertions, transactions, and coverage from the terminal.

## Install

The installer supports **macOS (Apple silicon)** through Homebrew and
**Linux (x86_64)** through verified GitHub Release archives. Install the latest
release with:

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/svcomplex-dev/svw/main/install.sh | sh
```

The zero-argument command follows the newest immutable release; currently
`0.1.0`. On macOS this installs `svcomplex-dev/tap/svw`. To select an immutable
release on either platform, pass its version to the same installer:

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/svcomplex-dev/svw/main/install.sh | sh -s -- --version 0.1.0
```

To explicitly install the replaceable rolling build, pass `--version latest`.

Open a waveform:

```sh
svw wave.vcd
svw wave.fst
```

### User-activated FSDB bridge

Distributed svw archives contain neither a reader SDK nor a bridge library,
and `bin/svw` does not link to either one. Users who are entitled to use a
compatible local reader can build the separate MIT-licensed SVW Wave Bridge
and activate that local dynamic library explicitly:

```sh
export SVW_FSDB_BRIDGE=/absolute/path/to/libsvw-wave-bridge.so
svw wave.fsdb
```

On Linux, build the independent public bridge against a reader SDK that you
obtained and are entitled to use:

```sh
./build-svw-wave-bridge.sh --reader-root /absolute/path/to/FsdbReader
```

The helper clones the public bridge source and writes
`./libsvw-wave-bridge.so` plus `./svw-wave-bridge-host`. Keep the two files in
the same directory, or set `SVW_WAVE_BRIDGE_HOST` to the absolute host path.
The helper neither downloads nor copies any reader SDK.

The bridge client and its commands are always present in svw; there is no
FSDB-specific build switch. `SVW_FSDB_BRIDGE` activates only the local library
chosen by the user. Without it, opening an FSDB reports how to activate the
bridge, while every built-in waveform and design workflow remains available.

svw never searches for a bridge or reader library. Its main process creates a
bounded read-only channel and starts the adjacent user-built host (or the
explicit `SVW_WAVE_BRIDGE_HOST`). Only that child loads the absolute bridge
path with local symbol visibility and resolves the single versioned C ABI
entry. This lets the fully static musl Linux executable interoperate with a
glibc reader stack without linking or loading it itself. The bridge then uses
the reader installed on that user's machine. Distribution gates reject bridge
or reader dependencies, reader symbols and paths, runtime search paths, and
dynamic libraries or archives inside the svw package.

For the clearest display, use a modern monospaced terminal font with broad
symbol coverage. The screenshots and recordings use the same recommended
setup.

## Common commands

Press `:` in the TUI, type a command, and press Enter. These commands cover a
typical first debugging session:

| Command | Use |
| --- | --- |
| `:open wave.fst` | Open another waveform. |
| `:add top.cpu.clk` | Add a signal by its full hierarchical name. |
| `:add top.cpu.*` | Add signals matching a `*` glob. |
| `:addall top.cpu` | Add every signal below a scope. |
| `:find 'clk\|reset'` | Search signal names with a POSIX regular expression. |
| `:goto 100ns` | Move the cursor and view to a time. |
| `:mark 100ns` / `:bmark 150ns` | Place the primary and baseline markers. |
| `:zoom fit` | Fit the view between the two markers. |
| `:save debug.svw` | Save the current session. |
| `:source debug.svw` | Restore a saved session or run a command script. |
| `:help add` | Show usage for a command; `:help` opens the full help view. |

Use headless mode to run the same `:` commands in CI or shell pipelines. A
leading colon is optional in command files:

```sh
printf 'add top.cpu.*\nmark 100ns\nmarks\nq\n' |
  svw --headless wave.vcd

svw --headless --session debug.svw < checks.svwcmd
```

svw also provides non-interactive waveform utilities:

```sh
# Compare all same-named signals; exit 0 means equal, 1 means different
svw diff golden.vcd dut.vcd
```

Whole-file reports show differing signals only. Add `--all` when a verbose
section for every compared signal is required.

## Performance

VCD is plain text: a full eager parse costs RAM many times the file size,
so opening a VCD larger than 100 MB automatically stream-converts it to a
temporary KBX first (bounded memory, lazy queries; `SVW_VCD_EAGER=1`
forces the legacy eager parse). For big or frequently reopened waves,
convert to the KBX container (KBX, "Kuai Bo Xing" 快波形, is svw's own
compressed waveform format) once—opening becomes an mmap map and queries
go through on-disk indexes:

```sh
svw extract wave.vcd wave.kbx
```

### Large VCD loads

Measured on a real 1.1 GB VCD (93M value changes, `svw --headless`,
`/usr/bin/time` peak RSS, same machine):

| open path | wall time | peak memory |
|---|---|---|
| eager parse (legacy) | 119 s | 34 GB |
| streaming auto-convert (default for >100 MB) | 68 s | **59 MB** |

`svw extract` uses the same streaming writer, so conversion is bounded in
memory too (89 MB VCD: 60 MB peak vs 2.8 GB with the former eager path).

## Made for agents, not just humans

AI agents can inspect waveform context and return bounded JSON or visual TUI
evidence that remains easy for people to review:

<p align="center">
  <img src="./features-pi-agent.gif"
       alt="AI agent inspecting and rendering a waveform with svw" width="100%">
</p>

```sh
svw agent wave.fst info
svw agent wave.fst signals clk 10
svw agent wave.fst render 0 200 top.clk top.state --color ansi --view wave
```

For long-lived integrations, `svw mcp [waveform]` starts a strict-schema MCP
stdio server and `svw rpc [waveform]` starts a JSON-RPC 2.0 stdio server. The
installation also includes agent integration examples and the svw waveform
skill.

## Documentation

For the complete command reference, tutorials, keyboard and mouse controls,
waveform utilities, design debug, reports, coverage, and agent integrations,
visit **[svw.run/docs](https://svw.run/docs)**.
