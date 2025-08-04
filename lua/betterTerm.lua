local api, fn, cmd, uv = vim.api, vim.fn, vim.cmd, vim.uv

-- Cached API functions
local api_funcs = {
  buf_get_name = api.nvim_buf_get_name,
  create_augroup = api.nvim_create_augroup,
  create_autocmd = api.nvim_create_autocmd,
  get_current_win = api.nvim_get_current_win,
  get_current_tabpage = api.nvim_get_current_tabpage,
  buf_is_valid = api.nvim_buf_is_valid,
  win_set_width = api.nvim_win_set_width,
  win_set_height = api.nvim_win_set_height,
  win_get_width = api.nvim_win_get_width,
  win_get_height = api.nvim_win_get_height,
  win_hide = api.nvim_win_hide,
  tabpage_list_wins = api.nvim_tabpage_list_wins,
  win_get_buf = api.nvim_win_get_buf,
  create_buf = api.nvim_create_buf,
  buf_get_number = api.nvim_buf_get_number,
  tabpage_is_valid = api.nvim_tabpage_is_valid,
  chan_send = api.nvim_chan_send,
  replace_termcodes = api.nvim_replace_termcodes,
  buf_delete = api.nvim_buf_delete,
  win_is_valid = api.nvim_win_is_valid,
  win_close = api.nvim_win_close,
  win_get_tabpage = api.nvim_win_get_tabpage,
  win_set_option = api.nvim_win_set_option,
}

-- Default configuration
local options = {
  prefix = "Term_",
  position = "bot",
  size = 18,
  startInserted = true,
  show_tabs = true,
  new_tab_mapping = "<C-t>",
  jump_tab_mapping = "<C-$tab>",
  active_tab_hl = "TabLineSel",
  inactive_tab_hl = "TabLine",
  new_tab_hl = "BetterTermSymbol",
  new_tab_icon = "+",
  index_base = 0,
}

-- Global state
local terms = {}
local ft = "better_term"
local term_current = options.index_base
local last_winbar_text = nil

local clickable_new = ""
local M = {}
local open_buf = ""
local startinsert = function() end
local term_key_cache = {}
local sorted_keys = {}
_G.BetterTerm = _G.BetterTerm or {}
_G.BetterTerm.switch_funcs = _G.BetterTerm.switch_funcs or {}

--- Get inactive clickable tab string
---@param key string
local function get_inactive_clickable_tab(key)
  -- local func_name = "switch_" .. fn.substitute(key, "[^A-Za-z0-9_]", "_", "g")
  local func_name = "switch_" .. key
  _G.BetterTerm.switch_funcs[func_name] = function()
    M.switch_to(key)
  end
  return string.format("%%#%s#%%@v:lua._G.BetterTerm.switch_funcs.%s@  %s  %%X", options.inactive_tab_hl, func_name, key)
end

--- Generate winbar with clickable tabs
local function generate_winbar_tabs()
  if not options.show_tabs or vim.tbl_isempty(terms) or vim.tbl_isempty(sorted_keys) then
    return ""
  end

  local tabs = {}
  local active_term = vim.bo.ft == ft and fn.bufname("%") or nil
  for _, key in ipairs(sorted_keys) do
    local term = terms[key]
    if api_funcs.buf_is_valid(term.bufid) then
      if key == active_term then
        tabs[#tabs + 1] = term.on_click_active
      else
        tabs[#tabs + 1] = term.on_click_inactive
      end
    end
  end
  tabs[#tabs + 1] = clickable_new
  return table.concat(tabs)
end

--- Update winbar for terminal windows
local function update_term_winbar()
  if not options.show_tabs then
    return
  end
  local winbar_text = generate_winbar_tabs()
  if last_winbar_text == winbar_text then
    return
  end
  last_winbar_text = winbar_text

  local cur_tab = api_funcs.get_current_tabpage()
  for _, term in pairs(terms) do
    if term.winid and api_funcs.win_is_valid(term.winid) then
      local p, term_tab = pcall(api_funcs.win_get_tabpage, term.winid)
      if p and term_tab == cur_tab then
        api_funcs.win_set_option(term.winid, "winbar", winbar_text)
      end
    end
  end
end

--- Find index in table
---@param tbl table
---@param value any
---@return number?
local function indexOf(tbl, value)
  for i, v in ipairs(tbl) do
    if v == value then
      return i
    end
  end
end

--- Generate terminal key
---@param num number
---@return string
local function get_term_key(num)
  if not num then
    return options.prefix .. options.index_base
  end
  term_key_cache[num] = term_key_cache[num] or (options.prefix .. num)
  return term_key_cache[num]
end

--- Open terminal
---@param term_key string
---@param current_tab number?
local function smooth_open(term_key, current_tab)
  current_tab = current_tab or api_funcs.get_current_tabpage()
  local term = terms[term_key]
  term.tabpage = current_tab
  cmd.b(term.bufid)
  term.winid = api_funcs.get_current_win()
  term.jobid = vim.b.terminal_job_id
  vim.bo.ft = ft
  update_term_winbar()
end

--- Insert new terminal configuration
---@param bufname string
---@param index number
---@return string
local function insert_new_term_config(bufname, index)
  local on_click_inactive = get_inactive_clickable_tab(bufname)
  terms[bufname] = {
    jobid = -1,
    bufid = -1,
    winid = -1,
    tabpage = 0,
    index = index,
    on_click_inactive = on_click_inactive,
    on_click_active = on_click_inactive:gsub(options.inactive_tab_hl, options.active_tab_hl),
  }
  sorted_keys[#sorted_keys + 1] = bufname
  vim.keymap.set({ "t" }, options.jump_tab_mapping:gsub("$tab", index), function()
    if vim.bo.ft == ft then
      local bname = fn.bufname("%")
      local key = get_term_key(index)
      if key ~= bname then
        smooth_open(key)
      end
    end
  end, { desc = "Goto BetterTerm #" .. index, silent = true })
  return bufname
end

--- Cached editor dimensions
local editor_dims = { width = 0, height = 0, last_check = 0 }

--- Get editor dimensions
---@return number, number
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
  local win = api_funcs.get_current_win()
  local editor_width, editor_height = get_editor_dimensions()
  local win_width, win_height = api_funcs.win_get_width(win), api_funcs.win_get_height(win)
  if win_width < editor_width then
    api_funcs.win_set_width(win, options.size)
  end
  if win_height < editor_height then
    api_funcs.win_set_height(win, options.size)
  end
end

--- Show terminal
---@param key_term string
---@param tabpage number
local function show_term(key_term, tabpage)
  local term = terms[key_term]
  term.tabpage = tabpage
  cmd(open_buf .. term.bufid)
  term.winid = api_funcs.get_current_win()
  resize_terminal()
  update_term_winbar()
  startinsert()
end

---@class BetterTermOpenOptions
---@field cwd? string

--- Create new terminal
---@param key_term string
---@param tabpage number
---@param cmd_buf string | nil
---@param opts? BetterTermOpenOptions
local function smooth_new_terminal(key_term, tabpage, cmd_buf, opts)
  local term = terms[key_term]
  term.tabpage = tabpage
  opts = opts or {}
  cmd_buf = cmd_buf or "b"

  local buf = api_funcs.create_buf(true, false)
  cmd(cmd_buf .. buf)
  term.winid = api_funcs.get_current_win()

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
  -- using the :file command like this creates a duplicate alternate buffer with
  -- the buffer's old name, so we clean it up here to avoid having *two* terminals
  -- for every *one* we wanted to create
  term.bufid = api_funcs.buf_get_number(0)
  term.jobid = vim.b.terminal_job_id
  update_term_winbar()
  cmd("bwipeout! #")
end

--- Create terminal
---@param key_term string
---@param tabpage number
---@param opts? BetterTermOpenOptions
local function create_new_term(key_term, tabpage, opts)
  smooth_new_terminal(key_term, tabpage, open_buf, opts)
  resize_terminal()
end

--- Hide terminal in tab
---@param index string
local function hide_current_term_in_tab(index)
  if vim.bo.ft == ft then
    api_funcs.win_hide(0)
    return
  end
  local term = terms[index]
  if not api_funcs.tabpage_is_valid(term.tabpage) then
    term.tabpage = 0
    return
  end

  for _, win in ipairs(api_funcs.tabpage_list_wins(term.tabpage)) do
    local bid = api_funcs.win_get_buf(win)
    if vim.bo[bid].ft == ft then
      api_funcs.win_hide(win)
    end
  end
end

--- Create terminal key
---@param index string | number | nil
---@return string
local function create_term_key(index)
  local i = type(index) == "number" and index or options.index_base
  local default = options.prefix .. options.index_base
  index = type(index) == "number" and get_term_key(index) or (index or default)
  if i >= term_current then term_current = i + 1 end
  return terms[index] and index or insert_new_term_config(index, i)
end

--- Open terminal
---@param index string | number | nil
---@param opts? BetterTermOpenOptions
function M.open(index, opts)
  index = create_term_key(index)
  local term = terms[index]
  local cur_tab = api_funcs.get_current_tabpage()

  local function switch_tab()
    hide_current_term_in_tab(index)
    show_term(index, cur_tab)
  end

  if not (term and api_funcs.buf_is_valid(term.bufid)) then
    hide_current_term_in_tab(index)
    return create_new_term(index, cur_tab, opts)
  end

  local bufinfo = fn.getbufinfo(term.bufid)[1]
  if bufinfo.hidden == 1 then
    if vim.bo.ft == ft then return smooth_open(index, cur_tab) end
    return switch_tab()
  end

  api_funcs.win_hide(bufinfo.windows[1])
  if cur_tab ~= term.tabpage then switch_tab() end
end

--- Switch to terminal
function M.switch_to(term_key)
  smooth_open(term_key)
end

--- Create new terminal from winbar
local function new_term_from_winbar()
  local key_term = create_term_key(term_current)
  smooth_new_terminal(key_term, api_funcs.get_current_tabpage(), nil, {})
  update_term_winbar()
end
_G.BetterTerm.new_term_from_winbar = new_term_from_winbar

---@class Press
---@field clean boolean
---@field interrupt boolean

--- Precompiled termcodes
local termcodes = {}

--- Initialize termcodes
local function init_termcodes()
  if not termcodes.ctrl_c then
    termcodes.ctrl_c = api_funcs.replace_termcodes("<C-c> ", true, true, true)
    termcodes.ctrl_l = api_funcs.replace_termcodes("<C-l> ", true, true, true)
    termcodes.ctrl_c_l = api_funcs.replace_termcodes("<C-c> <C-l> ", true, true, true)
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
      api_funcs.chan_send(current_term.jobid, termcodes.ctrl_c_l)
    elseif press.interrupt then
      uv.sleep(100)
      api_funcs.chan_send(current_term.jobid, termcodes.ctrl_c)
    elseif press.clean then
      uv.sleep(100)
      api_funcs.chan_send(current_term.jobid, termcodes.ctrl_l)
    end
  end
  api_funcs.chan_send(current_term.jobid, command .. "\n")
end

--- Select terminal
function M.select()
  if vim.tbl_isempty(terms) then
    print("Empty betterTerm's")
    return
  end
  vim.ui.select(sorted_keys, {
    prompt = "Select a Term",
    format_item = function(term) return term end,
  }, function(term)
    if term then M.open(term) else print("Term not valid") end
  end)
end

--- Toggle tab visibility
function M.toggle_tabs()
  options.show_tabs = not options.show_tabs
  if options.show_tabs then
    update_term_winbar()
  else
    for _, term in pairs(terms) do
      local bufinfo = fn.getbufinfo(term.bufid)[1]
      if bufinfo and not bufinfo.hidden then
        for _, win in ipairs(bufinfo.windows) do
          if api_funcs.win_is_valid(win) then
            api.nvim_win_set_option(win, "winbar", "")
          end
        end
      end
    end
  end
end

---@class UserOptions
---@field prefix string
---@field position string
---@field size string
---@field startInserted boolean
---@field show_tabs boolean
---@field new_tab_mapping string
---@field jump_tab_mapping string
---@field active_tab_hl string
---@field inactive_tab_hl string
---@field new_tab_hl string
---@field new_tab_icon string

--- Configuration
---@param user_options UserOptions | nil
function M.setup(user_options)
  if user_options then
    options = vim.tbl_deep_extend("force", options, user_options)
  end
  startinsert = options.startInserted and cmd.startinsert or function() end
  open_buf = options.position .. " sb "

  local group = api_funcs.create_augroup("BetterTerm", { clear = true })

  api_funcs.create_autocmd("BufWipeout", {
    group = group,
    pattern = options.prefix .. "*",
    callback = function(args)
      local bufname = fn.bufname(args.buf)
      vim.keymap.del({ "t" }, tostring(options.jump_tab_mapping:gsub("$tab", terms[bufname].index)))
      local index = indexOf(sorted_keys, bufname)
      terms[bufname] = nil
      table.remove(sorted_keys, index)
      vim.defer_fn(function()
        if index and index > 1 then
          M.open(sorted_keys[index - 1])
        elseif index and #sorted_keys >= 1 then
          M.open(sorted_keys[1])
        else
          update_term_winbar()
        end
      end, 10)
    end,
  })

  api_funcs.create_autocmd("FileType", {
    group = group,
    pattern = ft,
    callback = function()
      local opts = {
        swapfile = false,
        buflisted = false,
        relativenumber = false,
        number = false,
        readonly = true,
        scl = "no",
        statuscolumn = "",
        cursorline = false,
        cursorcolumn = false,
      }
      for key, value in pairs(opts) do vim.opt_local[key] = value end
      vim.bo.buflisted = false
      startinsert()
      vim.keymap.set("t", options.new_tab_mapping, function()
        local key_term = create_term_key(term_current)
        smooth_new_terminal(key_term, api_funcs.get_current_tabpage(), nil, {})
      end, { buffer = true })
    end,
  })

  clickable_new = string.format(
    "%%#%s#%%@v:lua._G.BetterTerm.new_term_from_winbar@%%#%s# %s %%#%s#%%X",
    options.inactive_tab_hl,
    options.new_tab_hl,
    options.new_tab_icon,
    options.inactive_tab_hl
  )
  term_key_cache = {}
end

return M
