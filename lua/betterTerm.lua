local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.uv

-- Cache of most frequently used API functions to avoid repeated lookups
local api_buf_get_name = api.nvim_buf_get_name
local api_create_augroup = api.nvim_create_augroup
local api_create_autocmd = api.nvim_create_autocmd
local api_get_current_win = api.nvim_get_current_win
local api_get_current_tabpage = api.nvim_get_current_tabpage
local api_buf_is_valid = api.nvim_buf_is_valid
local api_win_set_width = api.nvim_win_set_width
local api_win_set_height = api.nvim_win_set_height
local api_win_get_width = api.nvim_win_get_width
local api_win_get_height = api.nvim_win_get_height
local api_win_hide = api.nvim_win_hide
local api_tabpage_list_wins = api.nvim_tabpage_list_wins
local api_win_get_buf = api.nvim_win_get_buf
local api_create_buf = api.nvim_create_buf
local api_buf_get_number = api.nvim_buf_get_number
local api_tabpage_is_valid = api.nvim_tabpage_is_valid
local api_chan_send = api.nvim_chan_send
local api_replace_termcodes = api.nvim_replace_termcodes
local api_create_namespace = api.nvim_create_namespace
local api_buf_set_lines = api.nvim_buf_set_lines
local api_buf_add_highlight = api.nvim_buf_add_highlight
local api_open_win = api.nvim_open_win

-- Global state
local terms = {}
local ft = "better_term"
local tab_buffer = nil -- Buffer for terminal tabs
local tab_window = nil -- Window for terminal tabs
local tab_namespace = api_create_namespace("BetterTermTabs")
local term_current = 0

-- Default configuration options
local options = {
  prefix = "Term_",
  position = "bot",
  size = 18,
  startInserted = true,
  show_tabs = true,
  tab_height = 1,               -- Height of the tabs bar
  active_tab_hl = "TabLineSel", -- Highlight group for active tab
  inactive_tab_hl = "TabLine",  -- Highlight group for inactive tabs
  new_tab_mapping = "<C-t>",
  jump_tab_mapping = "<C-$tab>"
}

local M = {}

-- Precomputed values
local open_buf = ""
local pos = ""
local startinsert = function() end

-- Caches for performance
local term_key_cache = {}
local keys_cache = {}

---@class UserOptions
---@field prefix string Prefix used to identify created terminals
---@field position string Terminal window position
---@field size string Window size
---@field startInserted boolean Start in insert mode
---@field show_tabs boolean Show terminal tabs
---@field tab_height number Height of the tabs bar
---@field active_tab_hl string Highlight group for active tab
---@field inactive_tab_hl string Highlight group for inactive tabs

-- Update terminal tabs display
local function update_term_tabs()
  if not options.show_tabs then return end

  local keys = vim.tbl_keys(terms)
  if vim.tbl_isempty(keys) then
    if tab_buffer and api_buf_is_valid(tab_buffer) then
      api.nvim_buf_delete(tab_buffer, { force = true })
      tab_buffer = nil
    end
    return
  end

  -- Create tab buffer if it doesn't exist
  if not tab_buffer or not api_buf_is_valid(tab_buffer) then
    tab_buffer = api_create_buf(false, true)
    vim.bo[tab_buffer].modifiable = true
    vim.bo[tab_buffer].buftype = "nofile"
    vim.bo[tab_buffer].filetype = "better_term_tabs"
  end

  -- Sort keys numerically
  table.sort(keys, function(a, b)
    local num_a = tonumber(string.match(a, "%d+"))
    local num_b = tonumber(string.match(b, "%d+"))
    return num_a < num_b
  end)
  keys_cache = keys

  -- Build tab content
  local tabs_text = "  "
  local highlights = {}
  local active_term = vim.bo.ft == ft and fn.bufname("%") or nil

  for _, key in ipairs(keys) do
    local term = terms[key]
    if api_buf_is_valid(term.bufid) then
      local tab_name = key
      local start_col = #tabs_text
      tabs_text = tabs_text .. tab_name .. "  "
      table.insert(highlights, {
        start_col = start_col,
        end_col = start_col + #tab_name,
        hl_group = (key == active_term) and options.active_tab_hl or options.inactive_tab_hl,
        term_key = key
      })
    end
  end

  -- Update tab buffer
  api_buf_set_lines(tab_buffer, 0, -1, false, { tabs_text })
  for _, hl in ipairs(highlights) do
    api_buf_add_highlight(tab_buffer, tab_namespace, hl.hl_group, 0, hl.start_col, hl.end_col)
  end

  -- Manage tab window
  if tab_window and api.nvim_win_is_valid(tab_window) then
    api.nvim_win_close(tab_window, true)
    tab_window = nil
  end

  local current_win = api_get_current_win()
  local config = {
    relative = "win",
    win = current_win,
    width = api_win_get_width(current_win),
    height = options.tab_height,
    row = -options.tab_height,
    col = 0,
    style = "minimal",
    focusable = false,
    noautocmd = true,
  }
  tab_window = api_open_win(tab_buffer, false, config)
  vim.wo[tab_window].winhl = "Normal:TabLine"
  vim.wo[tab_window].cursorline = false
  vim.wo[tab_window].foldenable = false
  vim.wo[tab_window].signcolumn = "no"
  vim.wo[tab_window].statuscolumn = ""
end

-- Helper to find index in table
local function indexOf(tbl, value)
  for i, v in ipairs(tbl) do
    if v == value then return i end
  end
  return nil
end

--- Generate terminal key with caching
---@param num number
---@return string?
local function get_term_key(num)
  if not num then return nil end
  term_key_cache[num] = term_key_cache[num] or string.format(options.prefix .. "%d", num)
  return term_key_cache[num]
end

-- Open terminal smoothly
local function smooth_open(term_key, current_tab)
  current_tab = current_tab or api_get_current_tabpage()
  local term = terms[term_key]
  term.tabpage = current_tab
  cmd.b(term.bufid)
  term.bufid = api_buf_get_number(0)
  term.jobid = vim.b.terminal_job_id
  vim.bo.ft = ft
  term.winid = api_get_current_win()
end

--- Insert new terminal configuration
---@param bufname string
---@return string
local function insert_new_term_config(bufname, index)
  terms[bufname] = {
    jobid = -1,
    bufid = -1,
    winid = -1,
    tabpage = 0,
    index = index,
  }
  vim.keymap.set(
    { "t" },
    options.jump_tab_mapping:gsub("$tab", index),
    function()
      if vim.bo.ft == ft then
        local bname = fn.bufname("%")
        local key = get_term_key(index)
        if key ~= bname then smooth_open(key) end
      end
    end,
    { desc = "Goto BetterTerm #" .. index, silent = true }
  )
  return bufname
end

-- Cached editor dimensions
local editor_dims = { width = 0, height = 0, last_check = 0 }

--- Get editor dimensions with caching
local function get_editor_dimensions()
  local current_time = uv.now()
  if current_time - editor_dims.last_check > 500 then
    editor_dims.width = vim.o.columns
    editor_dims.height = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
    editor_dims.last_check = current_time
  end
  return editor_dims.width, editor_dims.height
end

--- Resize terminal window
local function resize_terminal()
  local win = api_get_current_win()
  local editor_width, editor_height = get_editor_dimensions()
  local win_width, win_height = api_win_get_width(win), api_win_get_height(win)
  if win_width < editor_width then api_win_set_width(win, options.size) end
  if win_height < editor_height then api_win_set_height(win, options.size) end
end

--- Show terminal with resizing
---@param key_term string
---@param tabpage number
local function show_term(key_term, tabpage)
  local term = terms[key_term]
  term.tabpage = tabpage
  cmd(open_buf .. term.bufid)
  term.winid = api_get_current_win()
  resize_terminal()
  startinsert()
end

---@param key_term string
---@param tabpage number
---@param cmd_buf string | nil
---@param opts? BetterTermOpenOptions
local function smooth_new_terminal(key_term, tabpage, cmd_buf, opts)
  local term = terms[key_term]
  term.tabpage = tabpage
  opts = opts or {}
  cmd_buf = cmd_buf or "b"

  local buf = api_create_buf(true, false)
  cmd(cmd_buf .. buf)

  if opts.cwd and opts.cwd ~= "." then
    local current_dir = uv.cwd()
    if opts.cwd ~= current_dir then
      local stat = uv.fs_stat(opts.cwd)
      if not stat then
        print(("betterTerm: path '%s' does not exist"):format(opts.cwd))
      elseif stat.type ~= "directory" then
        print(("betterTerm: path '%s' is not a directory"):format(opts.cwd))
      else
        cmd.lcd(opts.cwd)
      end
    end
  end

  cmd.terminal()
  vim.bo.ft = ft
  cmd.file(key_term)
  term.bufid = api_buf_get_number(0)
  term.jobid = vim.b.terminal_job_id
  term.winid = api_get_current_win()
end

--- Create a new terminal
---@param key_term string
---@param tabpage number
---@param opts? BetterTermOpenOptions
local function create_new_term(key_term, tabpage, opts)
  smooth_new_terminal(key_term, tabpage, open_buf, opts)
  resize_terminal()
  update_term_tabs()
end

--- Hide current terminal in tab
local function hide_current_term_in_tab(index)
  if vim.bo.ft == ft then
    api_win_hide(0)
    return
  end
  local term = terms[index]
  if not api_tabpage_is_valid(term.tabpage) then
    term.tabpage = 0
    return
  end
  for _, v in pairs(terms) do
    if v.winid ~= -1 and api.nvim_win_is_valid(v.winid) then
      api_win_hide(v.winid)
      break
    end
  end
end

--- Create terminal key
---@param index string | number | nil
---@return string
local function create_term_key(index)
  local default = options.prefix .. "0"
  local i = 0
  if type(index) == "number" then
    i = index
    index = get_term_key(index) or default
  else
    index = index or default
  end
  if i >= term_current then term_current = i + 1 end
  return terms[index] and index or insert_new_term_config(index, i)
end

---@class BetterTermOpenOptions
---@field cwd? string

--- Open terminal
---@param index string | number | nil
---@param opts? BetterTermOpenOptions
function M.open(index, opts)
  index = create_term_key(index)
  local term = terms[index]
  local current_tab = api_get_current_tabpage()

  if api_buf_is_valid(term.bufid) then
    local bufinfo = fn.getbufinfo(term.bufid)[1]
    if bufinfo.hidden == 1 then
      if vim.bo.ft == ft then
        smooth_open(index, current_tab)
      else
        hide_current_term_in_tab(index)
        show_term(index, current_tab)
      end
    else
      api_win_hide(bufinfo.windows[1])
      if tab_window then
        api.nvim_win_close(tab_window, true)
        tab_window = nil
      end
      if current_tab ~= term.tabpage then
        hide_current_term_in_tab(index)
        show_term(index, current_tab)
      end
    end
  else
    hide_current_term_in_tab(index)
    create_new_term(index, current_tab, opts)
  end
end

---@class Press
---@field clean boolean
---@field interrupt boolean

-- Precompiled termcodes
local termcodes = { ctrl_c = nil, ctrl_l = nil, ctrl_c_l = nil }

local function init_termcodes()
  if not termcodes.ctrl_c then
    termcodes.ctrl_c = api_replace_termcodes("<C-c> ", true, true, true)
    termcodes.ctrl_l = api_replace_termcodes("<C-l> ", true, true, true)
    termcodes.ctrl_c_l = api_replace_termcodes("<C-c> <C-l> ", true, true, true)
  end
end

--- Send command to terminal
---@param command string
---@param num number | nil
---@param press Press | nil
function M.send(command, num, press)
  num = num or 1
  local key_term = get_term_key(num)
  local current_term = terms[key_term]

  if not current_term then
    M.open(num)
    uv.sleep(100)
    current_term = terms[key_term]
  end

  init_termcodes()
  if press then
    if press.interrupt and press.clean then
      uv.sleep(100)
      api_chan_send(current_term.jobid, termcodes.ctrl_c_l)
    elseif press.interrupt then
      uv.sleep(100)
      api_chan_send(current_term.jobid, termcodes.ctrl_c)
    elseif press.clean then
      uv.sleep(100)
      api_chan_send(current_term.jobid, termcodes.ctrl_l)
    end
  end
  api_chan_send(current_term.jobid, command .. "\n")
end

--- Select terminal
function M.select()
  if vim.tbl_isempty(terms) then
    print("Empty betterTerm's")
    return
  end
  local keys = keys_cache
  vim.ui.select(keys, {
    prompt = "Select a Term",
    format_item = function(term) return term end,
  }, function(term)
    if term then M.open(term) else print("Term not valid") end
  end)
end

--- Toggle tab visibility
function M.toggle_tabs()
  options.show_tabs = not options.show_tabs
  if not options.show_tabs and tab_window and api.nvim_win_is_valid(tab_window) then
    api.nvim_win_close(tab_window, true)
    tab_window = nil
  elseif options.show_tabs then
    update_term_tabs()
  end
end

--- Configuration
---@param user_options UserOptions | nil
function M.setup(user_options)
  if user_options then
    options = vim.tbl_deep_extend("force", options, user_options)
  end
  startinsert = options.startInserted and cmd.startinsert or function() end
  open_buf = options.position .. " sb "
  pos = options.position

  local group = api_create_augroup("BetterTerm", { clear = true })

  api_create_autocmd("BufWipeout", {
    group = group,
    pattern = options.prefix .. "*",
    callback = function()
      local bufname = fn.bufname("%")
      vim.keymap.del({ 't' }, tostring(options.jump_tab_mapping:gsub("$tab", terms[bufname].index)))
      local keys = keys_cache
      local index = indexOf(keys, bufname)
      terms[bufname] = nil
      vim.defer_fn(function()
        if index and index > 1 then
          M.open(keys[index - 1])
        elseif index and #keys > 1 and index == 1 then
          M.open(keys[index + 1])
        else
          update_term_tabs()
        end
      end, 10)
    end,
  })

  api_create_autocmd("FileType", {
    group = group,
    pattern = { ft },
    callback = function()
      local opts = {
        swapfile = false,
        buflisted = false,
        relativenumber = false,
        number = false,
        readonly = true,
        scl = "no",
        statuscolumn = "",
      }
      for key, value in pairs(opts) do vim.opt_local[key] = value end
      vim.bo.buflisted = false
      startinsert()
      vim.keymap.set('t', options.new_tab_mapping, function()
        local key_term = create_term_key(term_current)
        smooth_new_terminal(key_term, api_get_current_tabpage(), nil, opts)
        update_term_tabs()
      end, { buffer = true })
    end,
  })

  api_create_autocmd("FileType", {
    group = group,
    pattern = "better_term_tabs",
    callback = function()
      local opts = {
        swapfile = false,
        buflisted = false,
        relativenumber = false,
        number = false,
        readonly = false,
        modifiable = true,
        scl = "no",
        statuscolumn = "",
      }
      for key, value in pairs(opts) do vim.opt_local[key] = value end
    end,
  })

  api_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if tab_window and api.nvim_win_is_valid(tab_window) then
        api.nvim_win_set_config(tab_window, { width = api_win_get_width(api_get_current_win()) })
        update_term_tabs()
      end
    end,
  })

  api_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    callback = function()
      if vim.bo.ft == ft then
        update_term_tabs()
      elseif tab_window and api.nvim_win_is_valid(tab_window) then
        api.nvim_win_close(tab_window, true)
        tab_window = nil
      end
    end,
  })

  api_create_autocmd("BufLeave", {
    group = group,
    pattern = options.prefix .. "*",
    callback = function()
      if tab_window and api.nvim_win_is_valid(tab_window) then
        api.nvim_win_close(tab_window, true)
        tab_window = nil
      end
    end,
  })

  term_key_cache = {}
end

return M
