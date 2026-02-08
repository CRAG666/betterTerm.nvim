local api, fn, cmd, uv = vim.api, vim.fn, vim.cmd, vim.uv

-- Default configuration
local options = {
	prefix = "Term",
	position = "bot",
	size = math.floor(vim.o.lines / 2),
	startInserted = true,
	show_tabs = true,
	new_tab_mapping = "<C-t>",
	jump_tab_mapping = "<C-$tab>",
	active_tab_hl = "TabLineSel",
	inactive_tab_hl = "TabLine",
	new_tab_hl = "BetterTermSymbol",
	new_tab_icon = "+",
	index_base = 0,
	predefined = {}, -- Terminales pre-creadas: {index = 0, name = "Main"}, ...
}

-- Global state
local State = {
	terms = {}, -- Keyed by numerical index
	term_lookup = {}, -- Keyed by bufname, value is index
	sorted_keys = {}, -- Holds bufnames for ordered display
	last_term_id = 0,  -- For opening whole window with terminals. Fallback value, otherwise is set in setup (in initialize_predefined_terminals).
	last_normal = nil, -- Last non-terminal window view for cursor restore
}
local ft = "better_term"
local term_current = options.index_base
local last_winbar_text = nil

local clickable_new = ""
local M = {}
local open_buf = ""
local startinsert = function() end
_G.BetterTerm = _G.BetterTerm or {}
_G.BetterTerm.switch_funcs = _G.BetterTerm.switch_funcs or {}

-- Get inactive clickable tab string
---@param bufname string
local function get_inactive_clickable_tab(bufname)
	local func_name = "switch_" .. fn.substitute(bufname, "[^A-Za-z0-9_]", "_", "g")
	_G.BetterTerm.switch_funcs[func_name] = function()
		M.switch_to(bufname)
	end
	return string.format(
		"%%#%s#%%@v:lua._G.BetterTerm.switch_funcs.%s@  %s  %%X",
		options.inactive_tab_hl,
		func_name,
		bufname
	)
end

-- Generate winbar with clickable tabs
local function generate_winbar_tabs()
	if not options.show_tabs or vim.tbl_isempty(State.terms) or vim.tbl_isempty(State.sorted_keys) then
		return ""
	end

	local tabs = {}
	local active_term_bufname = vim.bo.ft == ft and fn.bufname("%") or nil
	for _, bufname in ipairs(State.sorted_keys) do
		local index = State.term_lookup[bufname]
		if index then
			local term = State.terms[index]
			-- Show tab if buffer is valid OR if it's a predefined terminal without a buffer yet
			if api.nvim_buf_is_valid(term.bufid) or term.bufid == -1 then
				if bufname == active_term_bufname then
					tabs[#tabs + 1] = term.on_click_active
				else
					tabs[#tabs + 1] = term.on_click_inactive
				end
			end
		end
	end
	tabs[#tabs + 1] = clickable_new
	return table.concat(tabs)
end

-- Update winbar for terminal windows
local function update_term_winbar()
	if not options.show_tabs then
		return
	end
	local winbar_text = generate_winbar_tabs()
	if last_winbar_text == winbar_text then
		return
	end
	last_winbar_text = winbar_text

	local cur_tab = api.nvim_get_current_tabpage()
	for _, term in pairs(State.terms) do
		if term.winid and api.nvim_win_is_valid(term.winid) then
			local p, term_tab = pcall(api.nvim_win_get_tabpage, term.winid)
			if p and term_tab == cur_tab then
				api.nvim_win_set_option(term.winid, "winbar", winbar_text)
			end
		end
	end
end

-- Find index in table
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

-- Get bufname by index
---@param index number
---@return string
local function get_bufname_by_index(index)
	if State.terms[index] then
		return State.terms[index].bufname
	end
	return options.prefix .. " (" .. index .. ")"
end

-- Open terminal
---@param bufname string
---@param current_tab number?
local function smooth_open(bufname, current_tab)
	current_tab = current_tab or api.nvim_get_current_tabpage()
	local index = State.term_lookup[bufname]
	if not index then
		return
	end
	local term = State.terms[index]
	term.tabpage = current_tab
	cmd.b(term.bufid)
	term.winid = api.nvim_get_current_win()
	term.jobid = vim.bo.channel
	vim.bo.ft = ft
	update_term_winbar()
end

-- Insert new terminal configuration
---@param index number
---@return string bufname
local function insert_new_term_config(index)
	local name = options.prefix
	local bufname = name .. " (" .. index .. ")"
	local on_click_inactive = get_inactive_clickable_tab(bufname)

	State.terms[index] = {
		name = name,
		bufname = bufname,
		jobid = -1,
		bufid = -1,
		winid = -1,
		tabpage = 0,
		on_click_inactive = on_click_inactive,
		on_click_active = on_click_inactive:gsub(options.inactive_tab_hl, options.active_tab_hl),
	}
	State.term_lookup[bufname] = index
	State.sorted_keys[#State.sorted_keys + 1] = bufname

	vim.keymap.set({ "t" }, options.jump_tab_mapping:gsub("$tab", index), function()
		if vim.bo.ft == ft then
			local bname = fn.bufname("%")
			local key = get_bufname_by_index(index)
			if key ~= bname then
				smooth_open(key)
			end
		end
	end, { desc = "Goto BetterTerm #" .. index, silent = true })
	return bufname
end

-- Cached editor dimensions
local editor_dims = { width = 0, height = 0, last_check = 0 }

-- Get editor dimensions
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

-- Resize terminal window
local function resize_terminal()
	local win = api.nvim_get_current_win()
	local editor_width, editor_height = get_editor_dimensions()
	local win_width, win_height = api.nvim_win_get_width(win), api.nvim_win_get_height(win)
	if win_width < editor_width then
		api.nvim_win_set_width(win, options.size)
	end
	if win_height < editor_height then
		api.nvim_win_set_height(win, options.size)
	end
end

-- Show terminal
---@param bufname string
---@param tabpage number
local function show_term(bufname, tabpage)
	local index = State.term_lookup[bufname]
	if not index then
		return
	end
	local term = State.terms[index]
	term.tabpage = tabpage
	cmd(open_buf .. term.bufid)
	term.winid = api.nvim_get_current_win()
	resize_terminal()
	update_term_winbar()
	startinsert()
end

--@class BetterTermOpenOptions
---@field cwd? string

-- Create new terminal
---@param bufname string
---@param tabpage number
---@param cmd_buf string | nil
---@param opts? BetterTermOpenOptions
local function smooth_new_terminal(bufname, tabpage, cmd_buf, opts)
	local index = State.term_lookup[bufname]
	if not index then
		return
	end
	local term = State.terms[index]
	term.tabpage = tabpage
	opts = opts or {}
	cmd_buf = cmd_buf or "b"

	local buf = api.nvim_create_buf(true, false)
	cmd(cmd_buf .. buf)
	term.winid = api.nvim_get_current_win()

	if opts.cwd and opts.cwd ~= "." then
		local current_dir = uv.cwd()
		if opts.cwd ~= current_dir then
			local stat = uv.fs_stat(opts.cwd)
			if not stat then
				print(("betterTerm: path '%%s' does not exist"):format(opts.cwd))
			elseif stat.type ~= "directory" then
				print(("betterTerm: path '%%s' is not a directory"):format(opts.cwd))
			else
				cmd.lcd(opts.cwd)
			end
		end
	end

	cmd.terminal()
	vim.bo.ft = ft
	cmd.file(bufname)
	-- using the :file command like this creates a duplicate alternate buffer with
	-- the buffer's old name, so we clean it up here to avoid having *two* terminals
	-- for every *one* we wanted to create
	term.bufid = api.nvim_buf_get_number(0)
	term.jobid = vim.bo.channel
	update_term_winbar()
	cmd("bwipeout! #")
end

-- Create terminal
---@param bufname string
---@param tabpage number
---@param opts? BetterTermOpenOptions
local function create_new_term(bufname, tabpage, opts)
	smooth_new_terminal(bufname, tabpage, open_buf, opts)
	resize_terminal()
end

-- Hide terminal in tab
---@param bufname string
local function hide_current_term_in_tab(bufname)
	if vim.bo.ft == ft then
		api.nvim_win_hide(0)
		return
	end
	local index = State.term_lookup[bufname]
	if not index then
		return
	end
	local term = State.terms[index]
	if not api.nvim_tabpage_is_valid(term.tabpage) then
		term.tabpage = 0
		return
	end

	for _, win in ipairs(api.nvim_tabpage_list_wins(term.tabpage)) do
		local bid = api.nvim_win_get_buf(win)
		if vim.bo[bid].ft == ft then
			api.nvim_win_hide(win)
		end
	end
end

-- Get or create terminal config and return its bufname
---@param index number
---@return string bufname
local function get_or_create_term(index)
	if index >= term_current then
		term_current = index + 1
	end
	if State.terms[index] then
		return State.terms[index].bufname
	end
	return insert_new_term_config(index)
end

-- Open terminal
--@param id string | number | nil
--@param opts? BetterTermOpenOptions
function M.open(id, opts)
	local index
	if type(id) == "number" then
		index = id
	elseif type(id) == "string" then
		index = State.term_lookup[id]
		if not index then
			print("Term not valid: " .. id)
			return
		end
	else
		index = options.index_base
	end

	if vim.bo.ft ~= ft then
		State.last_normal = {
			winid = api.nvim_get_current_win(),
			tabpage = api.nvim_get_current_tabpage(),
			view = fn.winsaveview(),
		}
	end

	local bufname = get_or_create_term(index)
	local term = State.terms[index]
	local cur_tab = api.nvim_get_current_tabpage()

	local function switch_tab()
		hide_current_term_in_tab(bufname)
		show_term(bufname, cur_tab)
	end

	if not api.nvim_buf_is_valid(term.bufid) then
		hide_current_term_in_tab(bufname)
		return create_new_term(bufname, cur_tab, opts)
	end

	local bufinfo = fn.getbufinfo(term.bufid)[1]
	--If terminal is hidden
	if bufinfo.hidden == 1 then
		--Terminal window showing, term is not focused. Then focus on it
		if vim.bo.ft == ft then
			return smooth_open(bufname, cur_tab)
		end
		--Terminal window not showing. Then show terminal window and focus on terminal.
		return switch_tab()
	end

	--Terminal window is showing, but out of focus: focus on the main terminal.
	if (bufinfo.hidden == 0) and (vim.bo.ft ~= ft) then
		return switch_tab()
	end

	--Else: terminal window is showing and we are focused on the current terminal: close terminal.
	State.last_term_id = State.term_lookup[term.bufname]  --Save last open terminal
	local term_winid = bufinfo.windows[1]
	local last = State.last_normal
	if last and last.winid and api.nvim_win_is_valid(last.winid) then
		local ok, last_tab = pcall(api.nvim_win_get_tabpage, last.winid)
		if ok and last_tab == cur_tab then
			api.nvim_set_current_win(last.winid)
			if last.view then
				fn.winrestview(last.view)
			end
		else
			vim.cmd("wincmd p")
		end
	else
		vim.cmd("wincmd p")
	end
	api.nvim_win_hide(term_winid)
	if cur_tab ~= term.tabpage then
		switch_tab()
	end
end

-- Close terminal
--@param id string | number | nil
function M.close(id)
	local index
	if type(id) == "number" then
		index = id
	elseif type(id) == "string" then
		index = State.term_lookup[id]
		if not index then
			print("Term not valid: " .. id)
			return
		end
	else
		index = options.index_base
	end

	local term = State.terms[index]
	if not term or not api.nvim_buf_is_valid(term.bufid) then
		print("Term not valid or already closed: " .. get_bufname_by_index(index))
		return
	end

	cmd("bwipeout! " .. term.bufid)
end

-- Switch to terminal
function M.switch_to(bufname)
	smooth_open(bufname)
end

-- Switch to the (current term + shift)th terminal
--@param shift_in number | nil
function M.cycle(shift_in)
	local shift
	if type(shift_in) == "number" then
		shift = shift_in
	else
		shift = 1
	end

	local active_term_bufname = vim.bo.ft == ft and fn.bufname("%") or nil

	--Do nothing if no terminal is active
	if not (type(active_term_bufname) == "string") then
		return
	end

	local active_term_display_index  = indexOf(State.sorted_keys, active_term_bufname)
	--Next index wraps around
	local next_display_index   = (active_term_display_index-1 + shift) % #State.sorted_keys + 1
	local next_bufname      = State.sorted_keys[next_display_index]
	local next_global_index = State.term_lookup[next_bufname]

	M.open(next_global_index)
end

-- Toggles the window with all terminals
function M.toggle_termwindow()
	local active_term_bufname = vim.bo.ft == ft and fn.bufname("%") or nil

	if active_term_bufname == nil then
		M.open(State.last_term_id)
		return
	end

	M.open(active_term_bufname)
end

-- Create new terminal from winbar
local function new_term_from_winbar()
	local bufname = get_or_create_term(term_current)
	smooth_new_terminal(bufname, api.nvim_get_current_tabpage(), nil, {})
	update_term_winbar()
end
_G.BetterTerm.new_term_from_winbar = new_term_from_winbar

--@class Press
--@field clean boolean
--@field interrupt boolean

-- Precompiled termcodes
local termcodes = {}

-- Initialize termcodes
local function init_termcodes()
	if not termcodes.ctrl_c then
		termcodes.ctrl_c = api.nvim_replace_termcodes("<C-c> ", true, true, true)
		termcodes.ctrl_l = api.nvim_replace_termcodes("<C-l> ", true, true, true)
		termcodes.ctrl_c_l = api.nvim_replace_termcodes("<C-c> <C-l> ", true, true, true)
	end
end

-- Send command to terminal
--@param command string
--@param index number | nil
--@param press Press | nil
function M.send(command, index, press)
	index = index or 1
	local current_term = State.terms[index]

	if not current_term then
		M.open(index)
		uv.sleep(100)
		current_term = State.terms[index]
	end

	init_termcodes()
	if press then
		if press.interrupt and press.clean then
			uv.sleep(100)
			api.nvim_chan_send(current_term.jobid, termcodes.ctrl_c_l)
		elseif press.interrupt then
			uv.sleep(100)
			api.nvim_chan_send(current_term.jobid, termcodes.ctrl_c)
		elseif press.clean then
			uv.sleep(100)
			api.nvim_chan_send(current_term.jobid, termcodes.ctrl_l)
		end
	end
	api.nvim_chan_send(current_term.jobid, command .. "\n")
end

-- Select terminal
function M.select()
	if vim.tbl_isempty(State.terms) then
		print("Empty betterTerm's")
		return
	end
	vim.ui.select(State.sorted_keys, {
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

-- Rename current terminal
function M.rename()
	if vim.bo.ft ~= ft then
		print("Not in a betterTerm window")
		return
	end

	local old_bufname = fn.bufname("%")
	local index = State.term_lookup[old_bufname]
	if not index then
		print("Could not find terminal info for " .. old_bufname)
		return
	end

	local term = State.terms[index]
	vim.ui.input({ prompt = "New name for terminal (" .. index .. "):", default = term.name }, function(new_base_name)
		if not new_base_name or new_base_name == "" then
			print("Rename cancelled.")
			return
		end

		local new_bufname = new_base_name .. " (" .. index .. ")"

		if State.term_lookup[new_bufname] then
			print("Terminal with name '" .. new_bufname .. "' already exists.")
			return
		end

		-- Update the key in sorted_keys
		local old_key_index = indexOf(State.sorted_keys, old_bufname)
		if old_key_index then
			State.sorted_keys[old_key_index] = new_bufname
		end

		-- Update the lookup table
		State.term_lookup[new_bufname] = index
		State.term_lookup[old_bufname] = nil

		-- Update term object
		term.name = new_base_name
		term.bufname = new_bufname

		-- Update clickable callbacks
		local on_click_inactive = get_inactive_clickable_tab(new_bufname)
		term.on_click_inactive = on_click_inactive
		term.on_click_active = on_click_inactive:gsub(options.inactive_tab_hl, options.active_tab_hl)

		-- Update buffer name
		cmd.file(new_bufname)

		-- Update winbar for all terminals
		update_term_winbar()
	end)
end

-- Toggle tab visibility
function M.toggle_tabs()
	options.show_tabs = not options.show_tabs
	if options.show_tabs then
		update_term_winbar()
	else
		for _, term in pairs(State.terms) do
			local bufinfo = fn.getbufinfo(term.bufid)[1]
			if bufinfo and not bufinfo.hidden then
				for _, win in ipairs(bufinfo.windows) do
					if api.nvim_win_is_valid(win) then
						api.nvim_win_set_option(win, "winbar", "")
					end
				end
			end
		end
	end
end

-- Initialize predefined terminals
local function initialize_predefined_terminals()
	if vim.tbl_isempty(options.predefined) then
		return
	end

	for _, term_config in ipairs(options.predefined) do
		if term_config.index ~= nil then
			-- Create terminal configuration without creating the actual buffer
			get_or_create_term(term_config.index)
			local index = term_config.index
			local term = State.terms[index]

			-- If a custom name is provided, use it; otherwise keep the default
			if term_config.name then
				local new_bufname = term_config.name .. " (" .. index .. ")"

				-- Update the key in sorted_keys
				local old_key_index = indexOf(State.sorted_keys, term.bufname)
				if old_key_index then
					State.sorted_keys[old_key_index] = new_bufname
				end

				-- Update the lookup table
				State.term_lookup[new_bufname] = index
				State.term_lookup[term.bufname] = nil

				-- Update term object
				term.name = term_config.name
				term.bufname = new_bufname

				-- Update clickable callbacks
				local on_click_inactive = get_inactive_clickable_tab(new_bufname)
				term.on_click_inactive = on_click_inactive
				term.on_click_active = on_click_inactive:gsub(options.inactive_tab_hl, options.active_tab_hl)
			end
		end
	end
	State.last_term_id = State.term_lookup[State.sorted_keys[1]] --Setting the default value of last_term_id on startup
end

-- Setup keymaps for predefined terminals (available globally, not just in terminal mode)
local function setup_predefined_keymaps()
	if vim.tbl_isempty(options.predefined) then
		return
	end

	for _, term_config in ipairs(options.predefined) do
		if term_config.index ~= nil then
			local index = term_config.index
			local keymap = options.jump_tab_mapping:gsub("$tab", index)

			-- Create a global keymap that works in both normal and terminal mode
			vim.keymap.set({ "n", "t" }, keymap, function()
				M.open(index)
			end, { desc = "Toggle BetterTerm #" .. index, silent = true, noremap = true })
		end
	end
end

--@class UserOptions
--@field prefix string
--@field position string
--@field size string
--@field startInserted boolean
--@field show_tabs boolean
--@field new_tab_mapping string
--@field jump_tab_mapping string
--@field active_tab_hl string
--@field inactive_tab_hl string
--@field new_tab_hl string
--@field new_tab_icon string

-- Configuration
--@param user_options UserOptions | nil
function M.setup(user_options)
	if user_options then
		options = vim.tbl_deep_extend("force", options, user_options)
	end
	startinsert = options.startInserted and cmd.startinsert or function() end
	open_buf = options.position .. " sb "

	-- Initialize predefined terminals
	initialize_predefined_terminals()

	-- Setup keymaps for predefined terminals
	setup_predefined_keymaps()

	local group = api.nvim_create_augroup("BetterTerm", { clear = true })

	api.nvim_create_autocmd("BufWipeout", {
		group = group,
		pattern = "*",
		callback = function(args)
			local bufname = fn.bufname(args.buf)
			local index = State.term_lookup[bufname]
			if not index then
				return
			end

			vim.keymap.del({ "t" }, tostring(options.jump_tab_mapping:gsub("$tab", index)))
			local sorted_index = indexOf(State.sorted_keys, bufname)
			State.terms[index] = nil
			State.term_lookup[bufname] = nil
			if sorted_index then
				table.remove(State.sorted_keys, sorted_index)
			end

			vim.defer_fn(function()
				if sorted_index and sorted_index > 1 then
					M.open(State.sorted_keys[sorted_index - 1])
				elseif sorted_index and #State.sorted_keys >= 1 then
					M.open(State.sorted_keys[1])
				else
					update_term_winbar()
				end
			end, 10)
		end,
	})

	api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = ft,
		callback = function()
			local opts = {
				swapfile = false,
				buflisted = false,
				relativenumber = false,
				number = false,
				readonly = true,
				wrap = true,
				scl = "no",
				statuscolumn = "",
				cursorline = false,
				cursorcolumn = false,
				spell = false,
			}
			for key, value in pairs(opts) do
				vim.opt_local[key] = value
			end
			vim.bo.buflisted = false
			startinsert()
			vim.keymap.set("t", options.new_tab_mapping, function()
				local bufname = get_or_create_term(term_current)
				smooth_new_terminal(bufname, api.nvim_get_current_tabpage(), nil, {})
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
end

return M
