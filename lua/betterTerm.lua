local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.uv

-- Cache of most frequently used functions to avoid repeated lookups
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

local terms = {}
local ft = "better_term"

local options = {
  prefix = "Term_",
  position = "bot",
  size = 18,
  startInserted = true,
}

local M = {}

-- Precompute frequently used values
local open_buf = ""
local pos = ""
local startinsert = function() end

-- Terminal key cache to reduce repeated string formatting
local term_key_cache = {}

---@class UserOptions
---@field prefix string Prefix used to identify created terminals
---@field position string Terminal window position
---@field size string Window size
---@field startInserted boolean Start in insert mode

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
      terms[bufname] = nil
    end,
  })

  -- FileType handler
  api_create_autocmd("FileType", {
    group = group,
    pattern = { ft },
    callback = function()
      -- Use predefined table to avoid creating multiple tables per call
      local opts = {
        swapfile = false,
        buflisted = false,
        relativenumber = false,
        number = false,
        readonly = true,
        scl = "no",
        statuscolumn = "",
      }

      for key, value in pairs(opts) do
        vim.opt_local[key] = value
      end

      vim.bo.buflisted = false
      startinsert()
    end,
  })

  -- Initialize term_key cache
  term_key_cache = {}
end

--- Generate terminal key
---@param num number
---@return string?
local function get_term_key(num)
  if not num then return nil end

  -- Use cache for frequently accessed terminal keys
  if not term_key_cache[num] then
    term_key_cache[num] = string.format(options.prefix .. "%d", num)
  end

  return term_key_cache[num]
end

--- Insert new terminal configuration
---@param bufname string
---@return string
local function insert_new_term_config(bufname)
  terms[bufname] = {
    jobid = -1,
    bufid = -1,
    tabpage = 0,
  }
  return bufname
end

-- Calculate screen dimensions once and reuse
local editor_dims = { width = 0, height = 0, last_check = 0 }

--- Optimized function to get editor dimensions
local function get_editor_dimensions()
  local current_time = uv.now()

  -- Only recalculate dimensions if more than 500ms have passed since last check
  if current_time - editor_dims.last_check > 500 then
    editor_dims.width = vim.o.columns
    editor_dims.height = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
    editor_dims.last_check = current_time
  end

  return editor_dims.width, editor_dims.height
end

--- Resize terminal
local function resize_terminal()
  local win = api_get_current_win()
  local editor_width, editor_height = get_editor_dimensions()
  local win_width, win_height = api_win_get_width(win), api_win_get_height(win)

  -- Only resize if needed
  if win_width < editor_width then
    api_win_set_width(win, options.size)
  end

  if win_height < editor_height then
    api_win_set_height(win, options.size)
  end
end

--- Show terminal with smart size adjustment
---@param key_term string
---@param tabpage number
local function show_term(key_term, tabpage)
  local term = terms[key_term]
  term.tabpage = tabpage
  cmd(open_buf .. term.bufid)
  resize_terminal()
  startinsert()
end

--- Create new terminal
---@param key_term string
---@param tabpage number
---@param opts? BetterTermOpenOptions
local function create_new_term(key_term, tabpage, opts)
  local term = terms[key_term]
  term.tabpage = tabpage
  opts = opts or {}

  local buf = api_create_buf(true, false)
  cmd(open_buf .. buf)

  -- Optimized: more efficient directory verification
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
  resize_terminal()
  vim.bo.ft = ft
  cmd.file(key_term)
  term.bufid = api_buf_get_number(0)
  term.jobid = vim.b.terminal_job_id
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

  local wins = api_tabpage_list_wins(term.tabpage)
  for i = 1, #wins do
    if api_win_get_buf(wins[i]) == term.bufid then
      api_win_hide(wins[i])
      return
    end
  end
end

--- Create terminal key
---@param index string | number | nil
---@return string
local function create_term_key(index)
  local default = options.prefix .. "1"
  if type(index) == "number" then
    index = get_term_key(index) or default
  else
    index = index or default
  end
  return terms[index] and index or insert_new_term_config(index)
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
      hide_current_term_in_tab(index)
      show_term(index, current_tab)
    else
      api_win_hide(bufinfo.windows[1])
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

-- Precompile common termcodes
local termcodes = {
  ctrl_c = nil,
  ctrl_l = nil,
  ctrl_c_l = nil,
}

local function init_termcodes()
  if not termcodes.ctrl_c then
    termcodes.ctrl_c = api_replace_termcodes("<C-c> ", true, true, true)
    termcodes.ctrl_l = api_replace_termcodes("<C-l> ", true, true, true)
    termcodes.ctrl_c_l = api_replace_termcodes("<C-c> <C-l> ", true, true, true)
  end
end

--- Send command to terminal
---@param cmd string
---@param num number | nil
---@param press Press | nil
function M.send(cmd, num, press)
  num = num or 1
  local key_term = get_term_key(num)
  local current_term = terms[key_term]

  if not current_term then
    M.open(key_term)
    uv.sleep(100)
    current_term = terms[key_term]
  end

  if not api_buf_is_valid(current_term.bufid) then
    api_chan_send(current_term.jobid, cmd .. "\n")
    return
  end

  -- Initialize termcodes if needed
  init_termcodes()

  -- Optimize special key sending
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

  api_chan_send(current_term.jobid, cmd .. "\n")
end

--- Select terminal
function M.select()
  if vim.tbl_isempty(terms) then
    print("Empty betterTerm's")
    return
  end

  local keys = vim.tbl_keys(terms)
  vim.ui.select(keys, {
    prompt = "Select a Term",
    format_item = function(term)
      return term
    end,
  }, function(term)
    if term then
      M.open(term)
    else
      print("Term not valid")
    end
  end)
end

return M
