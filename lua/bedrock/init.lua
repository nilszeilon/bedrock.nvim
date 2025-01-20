local M = {}

-- Core utility functions
local function ensure_bedrock_dir()
	local bedrock_dir = vim.fn.expand("~/bedrock")
	if vim.fn.isdirectory(bedrock_dir) == 0 then
		vim.fn.mkdir(bedrock_dir, "p")
	end
	return bedrock_dir
end

local embeddings = require("bedrock.embeddings")

local function ensure_file_exists(filepath)
	if vim.fn.filereadable(filepath) == 0 then
		local dir = vim.fn.fnamemodify(filepath, ":h")
		if vim.fn.isdirectory(dir) == 0 then
			vim.fn.mkdir(dir, "p")
		end
		local f = io.open(filepath, "w")
		if f then
			f:write("# " .. vim.fn.fnamemodify(filepath, ":t:r") .. "\n\n")
			f:write("\n## Linked From\n")
			f:close()
		end
		-- Only update embedding if file creation was successful
		if vim.fn.filereadable(filepath) == 1 then
			pcall(embeddings.update_file_embedding, filepath)
		end
	end
end

local function add_backlink(filepath, from_file)
	local content = vim.fn.readfile(filepath)
	local bedrock_dir = vim.fn.expand("~/bedrock")
	local from_relative = from_file:gsub(bedrock_dir .. "/", ""):gsub("%.md$", "")
	local backlink = "[[" .. from_relative .. "]]"

	local linked_from_index = nil
	for i, line in ipairs(content) do
		if line == "## Linked From" then
			linked_from_index = i
			break
		end
	end

	if not linked_from_index then
		table.insert(content, "\n## Linked From")
		linked_from_index = #content
	end

	local backlink_exists = false
	for i = linked_from_index + 1, #content do
		if content[i]:match(vim.pesc(backlink)) then
			backlink_exists = true
			break
		end
	end

	if not backlink_exists then
		table.insert(content, linked_from_index + 1, backlink)
	end

	vim.fn.writefile(content, filepath)
end

local function add_file_link(from_file, to_file)
	ensure_file_exists(from_file)
	ensure_file_exists(to_file)

	local bedrock_dir = vim.fn.expand("~/bedrock")
	local to_relative = to_file:gsub(bedrock_dir .. "/", "")
	local display_path = to_relative:gsub("%.md$", "")
	local link = "[[" .. display_path .. "]]"

	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor_pos[1]
	local current_col = cursor_pos[2]
	local line_content = vim.api.nvim_get_current_line()

	local before_cursor = line_content:sub(1, current_col + 1)
	local after_cursor = line_content:sub(current_col + 2)
	local new_line_content = before_cursor .. link .. after_cursor

	vim.api.nvim_set_current_line(new_line_content)
	vim.api.nvim_win_set_cursor(0, { current_line, current_col + #link })
end

-- Main functions
function M.create_link()
	local current_file = vim.fn.expand("%:p")
	if not current_file:match("^" .. vim.fn.expand("~/bedrock")) then
		vim.notify("Current file is not in bedrock directory", vim.log.levels.ERROR)
		return
	end

	local bedrock_dir = ensure_bedrock_dir()
	local fzf = require("fzf-lua")

	fzf.fzf_exec("find " .. bedrock_dir .. " -type f", {
		prompt = "Link to File> ",
		actions = {
			["default"] = function(selected)
				if #selected == 0 then
					local current_input = fzf.get_last_query()
					local target_file

					local matching_files = vim.fn.glob(bedrock_dir .. "/**/" .. current_input .. "*.md", false, true)
					if #matching_files > 0 then
						target_file = matching_files[1]
					else
						local filename = current_input
						if not filename:match("%.md$") then
							filename = filename .. ".md"
						end
						target_file = bedrock_dir .. "/" .. filename
					end

					add_file_link(current_file, target_file)
					add_backlink(target_file, current_file)
					vim.notify("Created link to " .. vim.fn.fnamemodify(target_file, ":t"), vim.log.levels.INFO)
				else
					local target_file = selected[1]
					add_file_link(current_file, target_file)
					add_backlink(target_file, current_file)
					vim.notify("Created link to " .. vim.fn.fnamemodify(target_file, ":t"), vim.log.levels.INFO)
				end
			end,
		},
	})
end

function M.open_bedrock_file()
	local bedrock_dir = ensure_bedrock_dir()
	local fzf = require("fzf-lua")

	local function create_new_file(filename)
		if not filename:match("%.md$") then
			filename = filename .. ".md"
		end
		local filepath = bedrock_dir .. "/" .. filename
		ensure_file_exists(filepath)
		vim.cmd("edit " .. filepath)
		vim.api.nvim_buf_set_option(0, "filetype", "markdown")
	end

	fzf.fzf_exec("find " .. bedrock_dir .. " -type f", {
		prompt = "Bedrock Files> ",
		actions = {
			["default"] = function(selected)
				if #selected == 0 then
					create_new_file(fzf.get_last_query())
				else
					vim.cmd("edit " .. selected[1])
				end
			end,
			["ctrl-e"] = function(_)
				create_new_file(fzf.get_last_query())
			end,
		},
		winopts = {
			height = 0.9,
			width = 0.9,
			preview = {
				layout = "vertical",
				vertical = "up:50%",
			},
		},
	})
end

function M.follow_link()
	local line = vim.api.nvim_get_current_line()
	local link_target = line:match("%[%[(.-)%]%]")

	if link_target then
		local bedrock_dir = ensure_bedrock_dir()
		if not link_target:match("%.md$") then
			link_target = link_target .. ".md"
		end

		local full_path = bedrock_dir .. "/" .. link_target
		ensure_file_exists(full_path)
		vim.cmd("edit " .. full_path)
	else
		vim.notify("No link found under cursor", vim.log.levels.WARN)
	end
end

-- Setup function

function M.setup(opts)
	-- Load and merge settings
	local settings = require("bedrock.settings").setup(opts)

	-- Initialize embeddings with provided options
	embeddings.setup(settings)

	-- Ensure notes directory exists
	vim.fn.mkdir(settings.notes_path, "p")

	-- Set up keymaps if enabled
	if settings.keymaps then
		for action, key in pairs(settings.keymaps) do
			if key then -- Only set if not false
				if action == "follow_link" then
					vim.keymap.set("n", key, ":BedrockFollow<CR>", { silent = true })
				elseif action == "create_link" then
					vim.keymap.set("n", key, ":BedrockLink<CR>", { silent = true })
				elseif action == "search" then
					vim.keymap.set("n", key, ":BedrockSearch<CR>", { silent = true })
				elseif action == "find_similar" then
					vim.keymap.set("n", key, ":BedrockSimilar<CR>", { silent = true })
				elseif action == "open_file" then
					vim.keymap.set("n", key, ":Bedrock<CR>", { silent = true })
				end
			end
		end
	end

	-- Create commands
	vim.api.nvim_create_user_command("Bedrock", M.open_bedrock_file, {})
	vim.api.nvim_create_user_command("BedrockLink", M.create_link, {})
	vim.api.nvim_create_user_command("BedrockFollow", M.follow_link, {})
	vim.api.nvim_create_user_command("BedrockSearch", function()
		local fzf = require("fzf-lua")

		-- Create a temporary buffer for the query
		local buf = vim.api.nvim_create_buf(false, true)
		local width = 60
		local height = 10

		-- Calculate centered position
		local ui = vim.api.nvim_list_uis()[1]
		local win_opts = {
			relative = "editor",
			width = width,
			height = height,
			col = (ui.width - width) / 2,
			row = (ui.height - height) / 2,
			style = "minimal",
			border = "rounded",
		}

		-- Set buffer content with instructions
		local instructions = {
			"Enter your semantic search query below",
			"Press <Enter> to search",
			"Press <Esc> to cancel",
			"",
			"Query: ",
		}
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, instructions)

		-- Create window
		local win = vim.api.nvim_open_win(buf, true, win_opts)

		-- Set cursor position after "Query: "
		vim.api.nvim_win_set_cursor(win, { 5, 7 })

		-- Enter insert mode
		vim.cmd("startinsert!")

		-- Set buffer local keymaps
		local opts = { noremap = true, silent = true, buffer = buf }
		vim.keymap.set("i", "<CR>", function()
			-- Get the query text
			local lines = vim.api.nvim_buf_get_lines(buf, 4, 5, false)
			local query = lines[1]:sub(7) -- Remove "Query: "

			-- Close the query window
			vim.api.nvim_win_close(win, true)
			vim.api.nvim_buf_delete(buf, { force = true })

			if query ~= "" then
				local settings = require("bedrock.settings").options
				-- Perform semantic search
				local ok, similar_files =
					pcall(require("bedrock.embeddings").search_by_text, query, settings.search.max_results)

				if ok then
					-- Format results
					local formatted_results = {}
					local file_map = {}
					for _, result in ipairs(similar_files) do
						local similarity = string.format("%.2f", result.similarity * 100)
						local relative_path = result.path:gsub(vim.fn.expand("~/bedrock/"), "")
						local display_string = string.format("%s%% - %s", similarity, relative_path)
						table.insert(formatted_results, display_string)
						file_map[display_string] = result.path
					end

					-- Show results in fzf window
					fzf.fzf_exec(formatted_results, {
						prompt = "Search Results> ",
						actions = {
							["default"] = function(selected)
								if #selected > 0 then
									local target_file = file_map[selected[1]]
									vim.cmd("edit " .. target_file)
								end
							end,
						},
						winopts = {
							height = 0.9,
							width = 0.9,
							preview = {
								layout = "vertical",
								vertical = "up:50%",
							},
						},
					})
				else
					vim.notify("Search failed: " .. tostring(similar_files), vim.log.levels.ERROR)
				end
			end
		end, opts)

		vim.keymap.set("i", "<Esc>", function()
			vim.api.nvim_win_close(win, true)
			vim.api.nvim_buf_delete(buf, { force = true })
		end, opts)

		-- Set buffer options
		vim.api.nvim_buf_set_option(buf, "modifiable", true)
		vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	end, {})

	vim.api.nvim_create_user_command("BedrockSimilar", function()
		local current_file = vim.fn.expand("%:p")
		local fzf = require("fzf-lua")

		local settings = require("bedrock.settings").options
		-- Add error handling for embeddings search
		local ok, similar_files = pcall(embeddings.find_similar, current_file, settings.search.max_results)
		if not ok then
			vim.notify("Failed to find similar files: " .. tostring(similar_files), vim.log.levels.ERROR)
			return
		end

		-- Format the results for fzf
		local formatted_results = {}
		local file_map = {}
		for _, result in ipairs(similar_files) do
			local similarity = string.format("%.2f", result.similarity * 100)
			local relative_path = result.path:gsub(vim.fn.expand("~/bedrock/"), "")
			local display_string = string.format("%s%% - %s", similarity, relative_path)
			table.insert(formatted_results, display_string)
			file_map[display_string] = result.path
		end

		-- Show results in fzf
		fzf.fzf_exec(formatted_results, {
			prompt = "Similar Files> ",
			actions = {
				["default"] = function(selected)
					if #selected > 0 then
						local target_file = file_map[selected[1]]
						vim.cmd("edit " .. target_file)
					end
				end,
			},
			winopts = {
				height = 0.9,
				width = 0.9,
				preview = {
					layout = "vertical",
					vertical = "up:50%",
				},
			},
		})
	end, {})

	-- Set up autocommands
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = vim.fn.expand("~/bedrock") .. "/*.md",
		callback = function()
			local filepath = vim.fn.expand("%:p")
			-- Add error handling for embedding updates
			local ok, err = pcall(embeddings.update_file_embedding, filepath)
			if not ok then
				vim.notify("Failed to update embeddings: " .. tostring(err), vim.log.levels.WARN)
			end
		end,
	})

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "markdown",
		callback = function()
			local current_file = vim.fn.expand("%:p")
			if current_file:match("^" .. vim.fn.expand("~/bedrock")) then
				vim.api.nvim_buf_set_keymap(0, "n", "<CR>", ":BedrockFollow<CR>", { noremap = true, silent = true })
			end
		end,
	})
end

return M
