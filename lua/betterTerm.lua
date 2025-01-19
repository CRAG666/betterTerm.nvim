local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.uv

local terms = {}
local autocmd = api.nvim_create_autocmd

local options = {
	prefix = "Term_",
	position = "bot",
	size = 18,
	startInserted = true,
}

local ft = "better_term"

local M = {}

local open_buf = ""
local pos = ""
local startinsert = function() end

---@class UserOptions
---@field prefix string Prefix used to identify the terminals created
---@field position string Terminal window position
---@field size string Window size
---@field startInserted boolean Start in insert mode

--- Setup
---@param user_options UserOptions | nil
function M.setup(user_options)
	options = vim.tbl_deep_extend("force", options, user_options or {})
	startinsert = options.startInserted and cmd.startinsert or function() end
	open_buf = options.position .. " sb "
	pos = options.position

	local group = api.nvim_create_augroup("BetterTerm", { clear = true })

	autocmd("BufWipeout", {
		group = group,
		pattern = options.prefix .. "*",
		callback = function()
			local bufname = fn.bufname("%")
			terms[bufname] = nil
		end,
	})

	-- FileType handler
	autocmd("FileType", {
		group = group,
		pattern = { ft },
		callback = function()
			local opt_local = vim.opt_local
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
				opt_local[key] = value
			end

			vim.bo.buflisted = false
			startinsert()
		end,
	})
end

--- Generate key for terminal
---@param num number
---@return string?
local function get_term_key(num)
	return num and string.format(options.prefix .. "%d", num)
end

--- Insert new configuration
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

--- Show terminal
---@param key_term string
---@param tabpage number
local function show_term(key_term, tabpage)
	local term = terms[key_term]
	term.tabpage = tabpage
	cmd(open_buf .. term.bufid)
	local win = api.nvim_get_current_win()
	api.nvim_win_set_height(win, options.size)
	api.nvim_win_set_width(win, options.size)
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

	local buf = api.nvim_create_buf(true, false)
	cmd(open_buf .. buf)

	if opts.cwd and opts.cwd ~= "." and opts.cwd ~= uv.cwd() then
		local stat = uv.fs_stat(opts.cwd)
		if not stat then
			print(("betterTerm: path '%s' does not exist"):format(opts.cwd))
		elseif stat.type ~= "directory" then
			print(("betterTerm: path '%s' is not a directory"):format(opts.cwd))
		else
			cmd.lcd(opts.cwd)
		end
	end

	cmd.terminal()
	local win = api.nvim_get_current_win()
	api.nvim_win_set_height(win, options.size)
	api.nvim_win_set_width(win, options.size)
	vim.bo.ft = ft
	cmd.file(key_term)
	term.bufid = api.nvim_buf_get_number(0)
	term.jobid = vim.b.terminal_job_id
end

--- Hide current terminal in tab
local function hide_current_term_in_tab(index)
	if vim.bo.ft == ft then
		api.nvim_win_hide(0)
		return
	end

	local term = terms[index]
	if not api.nvim_tabpage_is_valid(term.tabpage) then
		term.tabpage = 0
	end

	for _, win in ipairs(api.nvim_tabpage_list_wins(term.tabpage)) do
		if api.nvim_win_get_buf(win) == term.bufid then
			api.nvim_win_hide(win)
			return
		end
	end
end

--- Create key for terminal
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
	local current_tab = api.nvim_get_current_tabpage()

	if api.nvim_buf_is_valid(term.bufid) then
		local bufinfo = fn.getbufinfo(term.bufid)[1]
		if bufinfo.hidden == 1 then
			hide_current_term_in_tab(index)
			show_term(index, current_tab)
		else
			api.nvim_win_hide(bufinfo.windows[1])
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

--- Send command to terminal
---@param cmd string
---@param num number | nil
---@param press Press | nil
function M.send(cmd, num, press)
	num = num or 1
	local keys_press = vim.tbl_deep_extend("force", { clean = false, interrupt = true }, press or {})
	local key_term = get_term_key(num)
	local current_term = terms[key_term]

	if not current_term then
		M.open(key_term)
		uv.sleep(100)
		current_term = terms[key_term]
	end

	if api.nvim_buf_is_valid(current_term.bufid) then
		if keys_press.interrupt or keys_press.clean then
			local binds = ""
			if keys_press.interrupt then
				binds = binds .. "<C-c> "
			end
			if keys_press.clean then
				binds = binds .. "<C-l> "
			end
			uv.sleep(100)
			api.nvim_chan_send(current_term.jobid, api.nvim_replace_termcodes(binds, true, true, true))
		end
		api.nvim_chan_send(current_term.jobid, cmd .. "\n")
	else
		api.nvim_chan_send(current_term.jobid, cmd .. "\n")
	end
end

--- Select terminal
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
	}, function(term)
		if term then
			M.open(term)
		else
			print("Term not valid")
		end
	end)
end

return M
