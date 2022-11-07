local terms = {}

local options = {
  prefix = "Term_",
  position = "",
  size = 25,
  buffer_pos = ""
}

local M = {}

--- Set user options
---@param user_options table
M.setup = function(user_options)
  options = vim.tbl_deep_extend("force", options, user_options or {})
  options.buffer_pos = string.format("%d%s new", options.size, options.position)
  vim.api.nvim_create_autocmd('BufWipeout', {
    pattern = options.prefix .. '*',
    callback = function()
      bufname = vim.fn.bufname("%")
      terms[bufname] = nil
    end
  })
end

--- Get table index for id term
---@param num number
---@return string?
local function get_term_key(num)
  if num == nil then return nil end
  return string.format(options.prefix .. "%d", num)
end

--- Save information of new term
---@param bufname string of terminal
---@return string
local function insert_new_term_config(bufname)
  terms[bufname] = {
    bufname = bufname,
    jobid = -1,
    bufid = -1,
    winid = -1,
    before_wind_id = -1,
  }
  return bufname
 end

--- Show terminal for id
---@param key_term string
---@param wind_id number
local function show_term(key_term, wind_id)
  terms[key_term].before_wind_id = wind_id
  vim.cmd(options.buffer_pos .. "| buffer " .. terms[key_term].bufid)
  vim.wo.scl='no'
  terms[key_term].winid = vim.api.nvim_get_current_win()
  vim.cmd("startinsert")
end

--- Create new terminal
---@param key_term string
---@param wind_id number
local function create_new_term(key_term, wind_id)
  terms[key_term].before_wind_id = wind_id
  vim.cmd(options.buffer_pos .. "| term")
  vim.bo.ft = "better_term"
  vim.cmd("file " .. terms[key_term].bufname)
  vim.wo.relativenumber = false
  vim.o.number = false
  vim.bo.buflisted = false
  vim.wo.foldcolumn = '0'
  vim.bo.readonly = true
  vim.wo.scl='no'
  terms[key_term].bufid = vim.api.nvim_buf_get_number(0)
  terms[key_term].jobid = vim.b.terminal_job_id
  terms[key_term].winid = vim.api.nvim_get_current_win()
  vim.cmd("startinsert")
end

--- get term id
---@return boolean
local function is_cbuffer_term()
  local name = vim.fn.bufname("%")
  if name:find('^' .. options.prefix) ~= nil then
    return true
  end
  return false
end

--- Hide current Term
local function hide_current_term_on_win()
  if is_cbuffer_term() then
    vim.cmd(":hide")
    return
  end
  local all_terms = vim.tbl_keys(terms)
  for _, term_name in pairs(all_terms) do
    if vim.fn.bufwinnr(term_name) > 0 then
      vim.fn.win_gotoid(terms[term_name].winid)
      vim.cmd(":hide")
      return
    end
  end
end

--- Validate if exist the terminal
---@param index string? | number?
---@return string
local function create_term_key(index)
  local default = options.prefix .. "1"
  if type(index) == "number" then
    index = get_term_key(index) or default
  else
  index = index or default
  end
  if vim.tbl_isempty(terms) then
    return insert_new_term_config(index)
  elseif not terms[index] then
    return insert_new_term_config(index)
  end
  return index
end

--- Show or hide Term
---@param index string? | number?
function M.open(index)
  index = create_term_key(index)
  local buf_exist = vim.api.nvim_buf_is_valid(terms[index].bufid)
  local current_wind_id = vim.api.nvim_get_current_win()
  if buf_exist then
    local bufinfo = vim.fn.getbufinfo(terms[index].bufid)[1]
    if bufinfo.hidden == 1 then
      hide_current_term_on_win()
      show_term(index, current_wind_id)
    else
      vim.fn.win_gotoid(bufinfo.windows[1])
      vim.cmd(":hide")
      if current_wind_id ~= terms[index].before_wind_id and current_wind_id ~= bufinfo.windows[1] then
        vim.fn.win_gotoid(current_wind_id)
        hide_current_term_on_win()
        show_term(index, current_wind_id)
      end
    end
  else
    hide_current_term_on_win()
    create_new_term(index, current_wind_id)
  end
end

--- Send command to Term
---@param cmd string
---@param num number
---@param interrupt boolean
function M.send(cmd, num, interrupt)
  num = num or 1
  local key_term = get_term_key(num)
  local current_term = terms[key_term];
  if current_term == nil then
    M.open(key_term)
    vim.loop.sleep(60)
    current_term = terms[key_term]
  end
  interrupt = interrupt or false
  local buf_exist = vim.api.nvim_buf_is_valid(current_term.bufid)
  if buf_exist then
    if interrupt then
      vim.api.nvim_chan_send(current_term.jobid, vim.api.nvim_replace_termcodes('<C-c> <C-l>', true, true, true))
      vim.loop.sleep(100)
    end
    vim.api.nvim_chan_send(current_term.jobid, cmd .. "\n")
  else
    vim.api.nvim_chan_send(current_term.jobid, cmd .. "\n")
  end
end

--- Select term and show or hide
function M.select()
  if vim.tbl_isempty(terms) then
    print("Empty betterTerm's")
    return
  end
  vim.ui.select(vim.tbl_keys(terms), {
    prompt = "Select a Term",
    format_item = function(term)
      return term
    end,
  }, function(term, _)
    if term then
      M.open(term)
    else
      print("Term not valid")
    end
  end)
end

return M
