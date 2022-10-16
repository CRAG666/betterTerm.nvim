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

local function getIndex(num)
  return string.format(options.prefix .. "%d", num)
end

--- Save characteristic of new term
---@param num number of terminal
local function newTermcConfig(num)
  local bufname = getIndex(num)
  terms[bufname] = {
    bufname = bufname,
    jobid = -1,
    bufid = -1,
    terminal_opened_win_id = -1,
  }
 end

--- Show terminal for id
---@param num number
---@param wind_id number
local function showTerm(num, wind_id)
  local index = getIndex(num)
  terms[index].terminal_opened_win_id = wind_id
  vim.cmd(options.buffer_pos .. "| buffer " .. terms[index].bufname)
  vim.cmd("startinsert")
end

--- Create new terminal
---@param num number
---@param wind_id number
local function newTerm(num, wind_id)
  local index = getIndex(num)
  terms[index].terminal_opened_win_id = wind_id
  vim.cmd(options.buffer_pos .. "| term")
  vim.bo.ft = "better_term"
  vim.cmd("file " .. terms[index].bufname)
  vim.wo.relativenumber = false
  vim.o.number = false
  vim.bo.buflisted = false
  vim.wo.foldcolumn = '0'
  vim.bo.readonly = true
  terms[index].bufid = vim.api.nvim_buf_get_number(0)
  terms[index].jobid = vim.b.terminal_job_id
  vim.cmd("startinsert")
end

local function getLastTerm()
  local name = vim.fn.bufname("%")
  if name:find('^' .. options.prefix) ~= nil then
    local index = name:gsub(options.prefix, "")
    return tonumber(index)
  end
  return 0
end

--- Hide current Term
local function hideLastTerm(num)
  local last = getLastTerm()
  if last == 0 then
    return
  elseif last ~= num then
    vim.cmd(":hide")
  end
end

local function validateTerm(num)
  num = num or 1
  if vim.tbl_isempty(terms) then
    newTermcConfig(num)
    return num
  elseif not terms[getIndex(num)] then
    newTermcConfig(num)
    return num
  end
  return num
end

--- Show or hide Term
---@param num number
function M.open(num)
  num = validateTerm(num)
  local index = getIndex(num)
  local buf_exist = vim.api.nvim_buf_is_valid(terms[index].bufid)
  local current_wind_id = vim.api.nvim_get_current_win()
  if buf_exist then
    local bufinfo = vim.fn.getbufinfo(terms[index].bufid)[1]
    if bufinfo.hidden == 1 then
      hideLastTerm(num)
      showTerm(num, current_wind_id)
    else
      vim.fn.win_gotoid(bufinfo.windows[1])
      vim.cmd(":hide")
      if current_wind_id ~= terms[index].terminal_opened_win_id and current_wind_id ~= bufinfo.windows[1] then
        vim.fn.win_gotoid(current_wind_id)
        hideLastTerm(num)
        showTerm(num, current_wind_id)
      end
    end
  else
    hideLastTerm(num)
    newTerm(num, current_wind_id)
  end
end

--- Send command to Term
---@param cmd string
---@param num number
---@param interrupt boolean
function M.send(cmd, num, interrupt)
  if vim.tbl_isempty(terms) or (num == nil) then
    return
  end
  interrupt = interrupt or false
  local index = getIndex(num)
  local buf_exist = vim.api.nvim_buf_is_valid(terms[index].bufid)
  if buf_exist then
    if interrupt then
      M.open(num)
      vim.api.nvim_chan_send(terms[index].jobid, vim.api.nvim_replace_termcodes('<C-c> <C-l>', true, true, true))
      vim.loop.sleep(100)
    end
    vim.api.nvim_chan_send(terms[index].jobid, cmd .. "\n")
  else
    M.open(num)
    vim.api.nvim_chan_send(terms[index].jobid, cmd .. "\n")
  end
end

--- Select term and show or hide
function M.select()
  if vim.tbl_isempty(terms) then
    print("Empy betterTerms")
    return
  end
  vim.ui.select(vim.tbl_keys(terms), {
    prompt = "Select a Term",
    format_item = function(term)
      return term
    end,
  }, function(term, _)
    if term then
      term = term:gsub(options.prefix, "")
      M.open(tonumber(term))
    else
      print("Term not valid")
    end
  end)
end

return M
