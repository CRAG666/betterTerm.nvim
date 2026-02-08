<h1 align='center'>Better Term</h1>

<h4 align='center'>🔥 The improved vscode/jetbrains terminal for Neovim written in pure lua 🔥</h4>

![Image](https://github.com/user-attachments/assets/17645559-68c4-4b6e-a048-427954703779)

https://user-images.githubusercontent.com/34254373/196014979-fdf2f741-1b72-4810-9e85-2b2cbe5287f6.mp4

# Introduction

I like the concept of vscode terminal, if you are like me, this complement will be the best of your options.
Normally I like to stay inside the editor, if I can make coffee in the editor, believe me I would do it. So having an integrated terminal is the most sensible option, however I tried for a long time to use the integrated terminal of neovim and I didn't get used to write so much to do what I wanted, so I tried and tried plugins, which were not for me, I just wanted something simple and usable, without so many complications. Then as other times I started to program and from that Saturday afternoon came out this plugin. I hope you enjoy it and make all your PR's.

By the way, it's called betterTerm, because it's the best for me. But for you it could very well suck. Plugin of just ~700 lines!!!.

https://user-images.githubusercontent.com/34254373/196015142-39895e93-eacd-4c48-9246-f4b7c6fbf076.mp4

## Requirements

- Neovim (>= 0.10)

## Install


- With **Native installer** (*Neovim >= 0.12*)

```lua
vim.pack.add({"https://github.com/CRAG666/betterTerm.nvim"})
require('betterTerm').setup()
```

- With [Lazy](https://github.com/folke/lazy.nvim)

```lua
{
  "CRAG666/betterTerm.nvim",
  opts = {
    -- your options
  },
}
```

- With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 'CRAG666/betterTerm.nvim' }
```


## Quick start

### Features

- **Tabbed Interface**: Manage multiple terminals in a tabbed view within the winbar.
- **Mouse Support**: Clickable tabs for easy navigation.
- **Toggle Terminals**: Quickly open and hide terminals.
- **Rename Terminals**: Easily rename terminals like jetbrains.
- **Multi-Terminal Management**: Easily create, switch between, rename, and manage several terminals.
- **Send Commands**: Send commands to any terminal directly from Neovim.
- **Terminal Selector**: Use `vim.ui.select` to pick a terminal from a list.
- **Dynamic Tab Focus**: Bring any terminal to your current tab page, no matter where it was opened.
- **Customizable**: Extensive options to tailor the look and feel.

### API

The following functions are exposed for you to use:

- `open({id}, {opts})`: Opens, focuses, or creates a terminal. If the terminal is already visible, it hides it.
  - `{id}` (string|number|nil): The (global) terminal index (number) or buffer name (string) to open. Defaults to `index_base`.
  - `{opts}` (table|nil): Options for opening.
    - `cwd` (string): Set the working directory for a new terminal.

- `close({id})`: Closes a terminal by id or buffer name.
  - `{id}` (string|number|nil): The (global) terminal index (number) or buffer name (string) to close. Defaults to `index_base`.

- `send({command}, {index}, {press})`: Sends a command to a specific terminal.
  - `{command}` (string): The command to execute.
  - `{index}` (number|nil): The terminal index. Defaults to `1`.
  - `{press}` (table|nil):
    - `clean` (boolean): Sends `<C-l>` to clear the screen before the command.
    - `interrupt` (boolean): Sends `<C-c>` to interrupt any running process.

- `select()`: Shows a list of open terminals using `vim.ui.select` to switch to or focus one.

- `rename()`: Renames the current active terminal. It will prompt for a new name.

- `toggle_tabs()`: Toggles the visibility of the terminal tabs in the winbar.

- `cycle({shift_in})`: Switches focus to a terminal `shift_in` to the right of the current displayed terminal (wraps around).
  - `{shift_in}` (number): the distance of the shift. Defaults to `1`.

- `toggle_termwindow()`: Toggles the visibility of the the window with all terminals. Remembers last active terminal.

### Recommended keymaps

No keymaps are set by default. Here are some recommendations:

```lua
local betterTerm = require('betterTerm')

-- Toggle the first terminal (ID defaults to index_base, which is 0)
vim.keymap.set({"n", "t"}, "<C-;>", function() betterTerm.open() end, { desc = "Toggle terminal" })

-- Open a specific terminal
vim.keymap.set({"n", "t"}, "<C-/>", function() betterTerm.open(1) end, { desc = "Toggle terminal 1" })

-- Cycle to the right
vim.keymap.set({"n", "t"}, "<C-PageUp>", function() betterTerm.cycle(1) end, { desc = "Cycle terminals to the right" })

-- Cycle to the left
vim.keymap.set({"n", "t"}, "<C-PageDown>", function() betterTerm.cycle(-1) end, { desc = "Cycle terminals to the left" })

-- Select a terminal to focus
vim.keymap.set("n", "<leader>tt", betterTerm.select, { desc = "Select terminal" })

-- Rename the current terminal
vim.keymap.set("n", "<leader>tr", betterTerm.rename, { desc = "Rename terminal" })

-- Toggle the tabs bar
vim.keymap.set("n", "<leader>tb", betterTerm.toggle_tabs, { desc = "Toggle terminal tabs" })
```

### Configuration

You can configure the plugin by passing a table to the `setup` function.

```lua
-- Example configuration
require('betterTerm').setup {
  prefix = "CRAG",
  startInserted = false,
  position = "right",
  size = 80,
  jump_tab_mapping = "<A-$tab>", -- Alt+1, Alt+2, ...
  predefined = {
    { index = 0, name = "Main" },
    { index = 1, name = "Server" },
    { index = 2, name = "Tests" },
  },
}
```

#### Options

- `prefix` (string, default: `Term`): Prefix for terminal buffer names. The final name will be `prefix (index)`.
- `position` (string, default: `bot`): Position to open the terminal (`:h opening-window`).
- `size` (number, default: `vim.o.lines / 2`): Size of the terminal window.
- `startInserted` (boolean, default: `true`): Start in insert mode when a terminal is opened.
- `show_tabs` (boolean, default: `true`): Enable/Disable the tabs bar.
- `new_tab_mapping` (string, default: `<C-t>`): Mapping to create a new terminal from within a terminal buffer.
- `jump_tab_mapping` (string, default: `<C-$tab>`): Mapping to jump to a specific terminal tab. `$tab` is replaced with the terminal index.
- `active_tab_hl` (string, default: `TabLineSel`): Highlight group for the active tab.
- `inactive_tab_hl` (string, default: `TabLine`): Highlight group for inactive tabs.
- `new_tab_hl` (string, default: `BetterTermSymbol`): Highlight group for the new tab icon.
- `new_tab_icon` (string, default: `+`): Icon for the new tab button.
- `index_base` (number, default: `0`): The starting index number for terminals.
- `predefined` (table, default: `{}`): Pre-configured terminals that will be initialized when the plugin starts.

#### Default values

```lua
require('betterTerm').setup {
	prefix = "Term",
	position = "bot",
	size = math.floor(vim.o.lines/ 2),
	startInserted = true,
	show_tabs = true,
	new_tab_mapping = "<C-t>",
	jump_tab_mapping = "<C-$tab>",
	active_tab_hl = "TabLineSel",
	inactive_tab_hl = "TabLine",
	new_tab_hl = "BetterTermSymbol",
	new_tab_icon = "+",
	index_base = 0,
	predefined = {},
}
```

Integration with [code_runner.nvim](https://github.com/CRAG666/code_runner.nvim), see for more info.

#### My lazy.nvim config

```lua
return {
  'CRAG666/betterTerm.nvim',
  keys = {
    {
      mode = { 'n', 't' },
      '<C-;>',
      function()
        require('betterTerm').open()
      end,
      desc = 'Open BetterTerm 0',
    },
    {
      mode = { 'n', 't' },
      '<C-/>',
      function()
        require('betterTerm').open(1)
      end,
      desc = 'Open BetterTerm 1',
    },
    {
      '<leader>tt',
      function()
        require('betterTerm').select()
      end,
      desc = 'Select terminal',
    }
  },
  opts = {
    position = 'bot',
    size = 20,
    jump_tab_mapping = "<A-$tab>"
  },
}
```

#### My native config
```python
  vim.pack.add({"https://github.com/CRAG666/betterTerm.nvim"})
  require('betterTerm').setup({
    position = 'vert',
    size = math.floor(vim.o.columns / 2),
    jump_tab_mapping = '<A-$tab>',
  })
```

# Contributing

Your help is needed to make this plugin the best of its kind, be free to contribute, criticize (don't be soft) or contribute ideas. All PR's are welcome.

## :warning: Important!

If you have any ideas to improve this project, do not hesitate to make a request, if problems arise, try to solve them and publish them. Don't be so picky I did this in one afternoon
