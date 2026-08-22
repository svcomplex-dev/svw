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
terminal.

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

The installer currently supports **macOS (Apple silicon)** and
**Linux (x86_64)**. Install the latest release with:

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/svcomplex-dev/svw/main/install.sh | sh
```

Open a waveform:

```sh
svw wave.vcd
svw wave.fst
```

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
| `:find 'clk|reset'` | Search signal names with a POSIX regular expression. |
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
