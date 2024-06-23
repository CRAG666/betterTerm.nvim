local terms = {}
local autocmd = vim.api.nvim_create_autocmd

local options = {
	prefix = "Term_",
	position = "bot",
	size = 18,
	startInserted = true,
}

ft = "better_term"

local M = {}

local open_buf = ""
local pos = ""
local startinsert = function() end

---@class UserOptions
---@field prefix string Prefix used to identify the terminals created
---@field position string Terminal window position
---@field size string Window size
---@field startInserted boolean Start in insert mode

--- Set user options
---@param user_options UserOptions | nil Table of options
function M.setup(user_options)
	options = vim.tbl_deep_extend("force", options, user_options or {})

	if options.startInserted then
		startinsert = vim.cmd.startinsert
	end
	open_buf = options.position .. " sb "
	pos = options.position
	autocmd("BufWipeout", {
		pattern = options.prefix .. "*",
		callback = function()
			bufname = vim.fn.bufname("%")
			terms[bufname] = nil
		end,
	})

	autocmd("FileType", {
		pattern = {
			ft,
		},
		callback = function()
			vim.opt_local.swapfile = false
			vim.opt_local.buflisted = false
			-- vim.opt_local.modified = false
			vim.opt_local.relativenumber = false
			vim.opt_local.number = false
			vim.bo.buflisted = false
			-- vim.opt_local.foldcolumn = "0"
			vim.opt_local.readonly = true
			vim.opt_local.scl = "no"
			vim.opt_local.statuscolumn = ""
			startinsert()
		end,
	})
end

--- Get table index for id term
---@param num number
---@return string?
local function get_term_key(num)
	if num == nil then
		return nil
	end
	return string.format(options.prefix .. "%d", num)
end

--- Save information of new term
---@param bufname string of terminal
---@return string
local function insert_new_term_config(bufname)
	terms[bufname] = {
		jobid = -1,
		bufid = -1,
		tabpage = 0,
	}
	return bufname
end

--- Show terminal for id
---@param key_term string
---@param tabpage number
local function show_term(key_term, tabpage)
	terms[key_term].tabpage = tabpage
	vim.cmd(open_buf .. terms[key_term].bufid)
	vim.api.nvim_win_set_height(0, options.size)
	vim.api.nvim_win_set_width(0, options.size)
	startinsert()
end

--- Create new terminal
---@param key_term string
---@param tabpage number
---@param opts? BetterTermOpenOptions
local function create_new_term(key_term, tabpage, opts)
	opts = opts or {}
	terms[key_term].tabpage = tabpage
	-- Skip if opts.cwd is the current directory
	if opts.cwd and opts.cwd ~= "." and opts.cwd ~= vim.uv.cwd() then
		local stat = vim.uv.fs_stat(opts.cwd)
		if not stat then
			print(("betterTerm: path '%s' does not exist"):format(opts.cwd))
		elseif stat.type ~= "directory" then
			print(("betterTerm: path '%s' is not a directory"):format(opts.cwd))
		else
			-- Change the window's directory to the desired directory
			vim.cmd.lcd(opts.cwd)
		end
	end
	vim.cmd(pos .. " te")
	vim.api.nvim_win_set_height(0, options.size)
	vim.api.nvim_win_set_width(0, options.size)
	vim.bo.ft = ft
	vim.cmd.file(key_term)
	terms[key_term].bufid = vim.api.nvim_buf_get_number(0)
	terms[key_term].jobid = vim.b.terminal_job_id
end

--- Hide current Term
local function hide_current_term_in_tab(index)
	if vim.bo.ft == ft then
		vim.api.nvim_win_hide(0)
		return
	end
	if vim.api.nvim_tabpage_is_valid(terms[index].tabpage) == false then
		terms[index].tabpage = 0
	end
	local all_wins = vim.api.nvim_tabpage_list_wins(terms[index].tabpage)
	for _, win in pairs(all_wins) do
		local cbuf = vim.api.nvim_win_get_buf(win)
		if cbuf == terms[index].bufid then
			vim.api.nvim_win_hide(win)
			return
		end
	end
end

--- Validate if exist the terminal
---@param index string | number | nil
---@return string
local function create_term_key(index)
	local default = options.prefix .. "1"
	if type(index) == "number" then
		index = get_term_key(index) or default
	else
		index = index or default
	end
	if not terms[index] then
		return insert_new_term_config(index)
	end
	return index
end

---@class BetterTermOpenOptions
---The working directory of the terminal.
---Note: Only takes effect on new terminals.
---@field cwd? string

--- Show or hide Term
---@param index string | number | nil Terminal id
---@param opts? BetterTermOpenOptions
function M.open(index, opts)
	index = create_term_key(index)
	local term = terms[index]
	local current_tab = vim.api.nvim_tabpage_get_number(0)
	local buf_exist = vim.api.nvim_buf_is_valid(term.bufid)
	if buf_exist then
		local bufinfo = vim.fn.getbufinfo(term.bufid)[1]
		if bufinfo.hidden == 1 then
			hide_current_term_in_tab(index)
			show_term(index, current_tab)
		else
			local target_win_id = bufinfo.windows[1]
			vim.api.nvim_win_hide(target_win_id)
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
---@field clean boolean Enable <C-l> key for clean
---@field interrupt boolean Enable <C-c> key for close current comand

--- Send command to Term
---@param cmd string Command to execute
---@param num number | nil Terminal id
---@param press Press | nil Key to pressesd before execute command
function M.send(cmd, num, press)
	num = num or 1
	local keys_press = vim.tbl_deep_extend("force", { clean = false, interrupt = true }, press or {})
	local key_term = get_term_key(num)
	local current_term = terms[key_term]
	if current_term == nil then
		M.open(key_term)
		vim.uv.sleep(100)
		current_term = terms[key_term]
	end
	local buf_exist = vim.api.nvim_buf_is_valid(current_term.bufid)
	if buf_exist then
		if keys_press.interrupt or keys_press.clean then
			local binds = ""
			if keys_press.interrupt then
				binds = binds .. "<C-c> "
			end
			if keys_press.clean then
				binds = binds .. "<C-l> "
			end
			vim.uv.sleep(100)
			vim.api.nvim_chan_send(current_term.jobid, vim.api.nvim_replace_termcodes(binds, true, true, true))
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
