<h1 align='center'>Better Term</h1>

<h4 align='center'>🔥 The improved vscode terminal for Neovim written in pure lua 🔥</h4>

https://user-images.githubusercontent.com/34254373/196014979-fdf2f741-1b72-4810-9e85-2b2cbe5287f6.mp4

# Introduction

I like the concept of vscode terminal, if you are like me, this complement will be the best of your options.
Normally I like to stay inside the editor, if I can make coffee in the editor, believe me I would do it. So having an integrated terminal is the most sensible option, however I tried for a long time to use the integrated terminal of neovim and I didn't get used to write so much to do what I wanted, so I tried and tried plugins, which were not for me, I just wanted something simple and usable, without so many complications. Then as other times I started to program and from that Saturday afternoon came out this plugin. I hope you enjoy it and make all your PR's.

By the way, it's called betterTerm, because it's the best for me. But for you it could very well suck.

https://user-images.githubusercontent.com/34254373/196015142-39895e93-eacd-4c48-9246-f4b7c6fbf076.mp4

### Requirements

- Neovim (>= 0.8)

### Install

- With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 'CRAG666/betterTerm.nvim' }
```

- With [paq-nvim](https://github.com/savq/paq-nvim)

```lua
require "paq"{'CRAG666/betterTerm.nvim';}
```

### Quick start

Add the following line to your init.lua

```lua
require('betterTerm').setup()
```

#### Features

- Toggle term
- Multi term
- Close the terminal as always, no rare mapping were added, just use :q to close
- Send command
- Select the terminal you need, with Neovim's native selector
- If you want you could have HotReload easily
- Bring the terminal focus to your current tab, no matter if the terminal is open in tab 100 and you need it in tab 1.

### Functions

- `:lua require("config.betterTerm").open(num)` - Show or hide a specific terminal(num: terminal id).
- `:lua require("config.betterTerm").send(cmd, num, interrupt)` - Send a command to a specific terminal(cmd: command, num: terminal id, interrupt: close any command that is currently in execution).
- `:lua require("config.betterTerm").select()` -Select any terminal.Whether you want to show or hide(use: vim.ui.select as backend).

### Recommended keymaps

No keymaps is assigned by default.It is better that you do it yourself, I will show my preferred keymaps:

```lua
local betterTerm = require('betterTerm')
-- toggle firts term
vim.keymap.set({"n", "t"}, "<C-ñ>", betterTerm.open, { desc = "Open terminal"})
-- Select term focus
vim.keymap.set({"n", "t"}, "<leader>tt", betterTerm.select, { desc = "Select terminal"})
-- Create new term
local current = 2
vim.keymap.set(
    {"n", "t"}, "<leader>tn",
    function()
        betterTerm.open(current)
        current = current + 1
    end,
    { desc = "New terminal"}
)
```

### Options

- `prefix`: It is used to create the names and a autocmd(default: `Term_`).
- `position`: Integrated terminal position(for option `:h opening-window`, default: `bot`)
- `size`: Size of the terminal window (default: `18`)

### Setup

```lua
-- this is a config example
require('betterTerm').setup {
  prefix = "CRAG_",
  position = "vsplit",
  size = 45
}
```

#### Default values

```lua
require('betterTerm').setup {
  prefix = "Term_",
  position = "",
  size = 25
}
```

# Integration with [code_runner.nvim](https://github.com/CRAG666/code_runner.nvim)

```lua
-- use the best keymap for you
vim.keymap.set("n", "<leader>e", function()
  -- change 1 for other terminal id
  require('betterTerm').send(require("code_runner.commands").get_filetype_command(), 1, true)
end, { desc = "Excute File"})
```

You can have Hotreload for any language if instead of assigning a `keymap`, create an `autocmd` for the language you want to add Hotreload

# Contributing

Your help is needed to make this plugin the best of its kind, be free to contribute, criticize (don't be soft) or contribute ideas. All PR's are welcome.

## :warning: Important!

If you have any ideas to improve this project, do not hesitate to make a request, if problems arise, try to solve them and publish them. Don't be so picky I did this in one afternoon
