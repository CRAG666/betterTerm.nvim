<h1 align='center'>Better Term</h1>

<h4 align='center'>🔥 The improved vscode terminal for Neovim written in pure lua 🔥</h4>

![Image](https://github.com/user-attachments/assets/17645559-68c4-4b6e-a048-427954703779)

https://user-images.githubusercontent.com/34254373/196014979-fdf2f741-1b72-4810-9e85-2b2cbe5287f6.mp4

# Introduction

I like the concept of vscode terminal, if you are like me, this complement will be the best of your options.
Normally I like to stay inside the editor, if I can make coffee in the editor, believe me I would do it. So having an integrated terminal is the most sensible option, however I tried for a long time to use the integrated terminal of neovim and I didn't get used to write so much to do what I wanted, so I tried and tried plugins, which were not for me, I just wanted something simple and usable, without so many complications. Then as other times I started to program and from that Saturday afternoon came out this plugin. I hope you enjoy it and make all your PR's.

By the way, it's called betterTerm, because it's the best for me. But for you it could very well suck. Plugin of just 486 lines!!!.

https://user-images.githubusercontent.com/34254373/196015142-39895e93-eacd-4c48-9246-f4b7c6fbf076.mp4

## Requirements

- Neovim (>= 0.10)

## Install

- With [Lazy](https://github.com/folke/lazy.nvim)

```lua
{
  "CRAG666/betterTerm.nvim",
  opts = {
    position = "bot",
    size = 15,
  },
}
```

- With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 'CRAG666/betterTerm.nvim' }
```


## Quick start

Add the following line to your init.lua(If not use *Lazy*)

```lua
require('betterTerm').setup()
```

### Features

- Tabs bar
- Mouse support
- Toggle term
- Multi term
- Close the terminal as always, no rare mapping were added, just use :q! to close
- Send command
- Select the terminal you need, with Neovim's native selector
- If you want you could have HotReload easily
- Bring the terminal focus to your current tab, no matter if the terminal is open in tab 100 and you need it in tab 1.

### Functions

- `:lua require("config.betterTerm").open(num)` - Show or hide a specific terminal(num: terminal id).
- `:lua require("config.betterTerm").send(cmd, num, press)` - Send a command to a specific terminal(cmd: command, num: terminal id, press: Press clean and/or interrupt).
- `:lua require("config.betterTerm").select()` -Select any terminal.Whether you want to show or hide(use: vim.ui.select as backend).

### Recommended keymaps

No keymaps is assigned by default.It is better that you do it yourself, I will show my preferred keymaps:

```lua
local betterTerm = require('betterTerm')
-- toggle firts term
vim.keymap.set({"n", "t"}, "<C-;>", betterTerm.open, { desc = "Open terminal"})
-- Select term focus
vim.keymap.set({"n"}, "<leader>tt", betterTerm.select, { desc = "Select terminal"})
```

### Options

- `prefix`: It is used to create the names and a autocmd (default: `Term_`).
- `position`: Integrated terminal position (for option `:h opening-window`, default: `bot`)
- `size`: Size of the terminal window (default: `18`)
- `startInserted`: Should the terminal be in insert mode when opened (default: `true`)
- `show_tabs`: Enable/Disable the tabs bar (default: `true`)
- `new_tab_mapping`: Mapping for create new terminal (default: `<C-t>`)
- `jump_tab_mapping`: Mapping for jump to tab terminal (default: `<C-$tab>`)
- `active_tab_hl`: Highlight group for active tab (default: `TabLineSel`)
- `inactive_tab_hl`: Highlight group for inactive tabs (default: `TabLine`)
- `new_tab_hl`: Highlight group for icon new term (default: `BetterTermSymbol`)
- `new_tab_icon`: Icon for new term (default: `+`)
- `index_base`: The starting index number for terminal tabs. (Default: `0`)


### Setup

```lua
-- this is a config example
require('betterTerm').setup {
  prefix = "CRAG_",
  startInserted = false,
  position = "bot",
  size = 25
  jump_tab_mapping = "<A-$tab>", -- Alt+1 , Alt+2, ...
}
```

#### Default values

```lua
require('betterTerm').setup {
  prefix = "Term_",
  position = "bot",
  size = 18,
  startInserted = true,
  show_tabs = true,
  new_tab_mapping = "<C-t>",       -- Create new terminal
  jump_tab_mapping = "<C-$tab>",   -- Jump to tab terminal
  active_tab_hl = "TabLineSel",    -- Highlight group for active tab
  inactive_tab_hl = "TabLine",     -- Highlight group for inactive tabs
  new_tab_hl = "BetterTermSymbol", -- Highlight group for new term
  new_tab_icon = "+",              -- Icon for new term
  index_base = 0                   -- Index number for terminals 
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

# Contributing

Your help is needed to make this plugin the best of its kind, be free to contribute, criticize (don't be soft) or contribute ideas. All PR's are welcome.

## :warning: Important!

If you have any ideas to improve this project, do not hesitate to make a request, if problems arise, try to solve them and publish them. Don't be so picky I did this in one afternoon
