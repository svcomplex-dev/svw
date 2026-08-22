<p align="right">
  <a href="./README.md">English</a> | <a href="./README.zh-CN.md">中文</a>
</p>

# svw — Simple Virtual Wave

**svw** 为人类、自动化任务和 AI agent 提供快速、专注的终端波形调试体验。

打开仿真波形后，可以在本机终端、SSH、CI 容器或编辑器旁使用同一套专注的
终端调试工作流。

<p align="center">
  <img src="./showcase.gif"
       alt="svw 交互式 TUI 综合录屏" width="100%">
</p>

## svw 是什么？

svw 无需额外设置即可打开 VCD、EVCD 和 FST 波形，并在终端中清晰呈现数字
信号、总线、未知状态和实数轨迹。

交互界面提供模糊信号选择器、marker、边沿导航、缩放历史、鼠标操作、主题、
`:` 命令行和 `Space` leader 菜单。颜色与字符会根据终端能力自动适配。

## 为什么选择 svw？

- **纯终端：** 在本机 shell、SSH 会话和容器中使用同一套专注的调试体验。
- **Vim 风格工作流：** 支持模式快捷键、`:` 命令、模糊搜索和可发现的
  leader 菜单。
- **自动化优先：** 同一套工作流可通过脚本或聚焦的 JSON/TUI 查询重复执行。
- **比较与分析：** 在统一物理时间轴上比较波形，并在终端中查看报表、断言、
  transaction 和覆盖率。

## 安装

安装脚本目前仅支持 **macOS（Apple silicon）** 和 **Linux（x86_64）**。
运行下面的命令安装最新版本：

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/svcomplex-dev/svw/main/install.sh | sh
```

打开波形：

```sh
svw wave.vcd
svw wave.fst
```

为获得最清晰的显示效果，建议使用字符覆盖完整的现代等宽终端字体。项目截图与
录屏采用相同的推荐设置。

## 常用命令

在 TUI 中按 `:`，输入命令后按 Enter。下面这些命令可以覆盖一次常见的初步
调试流程：

| 命令 | 用途 |
| --- | --- |
| `:open wave.fst` | 打开另一个波形文件。 |
| `:add top.cpu.clk` | 按完整层次名添加信号。 |
| `:add top.cpu.*` | 添加符合 `*` glob 的信号。 |
| `:addall top.cpu` | 添加某个 scope 下的全部信号。 |
| `:find 'clk\|reset'` | 使用 POSIX 正则搜索信号名。 |
| `:goto 100ns` | 将光标和视图移动到指定时刻。 |
| `:mark 100ns` / `:bmark 150ns` | 放置主 marker 和基准 marker。 |
| `:zoom fit` | 将视图适配到两个 marker 之间。 |
| `:save debug.svw` | 保存当前会话。 |
| `:source debug.svw` | 恢复已保存的会话，或运行命令脚本。 |
| `:help add` | 查看某条命令的用法；`:help` 打开完整帮助页。 |

Headless 模式可以在 CI 或 shell 管道中执行相同的 `:` 命令；命令文件中的
开头冒号可以省略：

```sh
printf 'add top.cpu.*\nmark 100ns\nmarks\nq\n' |
  svw --headless wave.vcd

svw --headless --session debug.svw < checks.svwcmd
```

svw 还提供非交互式波形工具：

```sh
# 比较全部同名信号；退出码 0 表示相同，1 表示存在差异
svw diff golden.vcd dut.vcd
```

## 不只为人类，也为 Agent

AI agent 可以检查波形上下文，并返回范围明确的 JSON 或可视化 TUI 证据，方便
人类直接复核：

<p align="center">
  <img src="./features-pi-agent.gif"
       alt="AI agent 使用 svw 检查并渲染波形的综合录屏" width="100%">
</p>

```sh
svw agent wave.fst info
svw agent wave.fst signals clk 10
svw agent wave.fst render 0 200 top.clk top.state --color ansi --view wave
```

对于长连接集成，`svw mcp [waveform]` 会启动严格 schema 的 MCP stdio server，
`svw rpc [waveform]` 会启动 JSON-RPC 2.0 stdio server。安装包同时包含 agent
集成示例与 svw waveform skill。

## 文档

完整命令参考、教程、键盘与鼠标操作、波形工具、设计调试、报表、覆盖率和
agent 集成，请访问 **[svw.run/docs](https://svw.run/docs)**。
