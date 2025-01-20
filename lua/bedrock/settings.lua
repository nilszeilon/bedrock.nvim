local M = {}

M.defaults = {
	-- Directory settings
	notes_path = vim.fn.expand("~/bedrock"),

	-- File settings
	default_extension = ".md",
	template = {
		-- Default template for new notes
		header = "# %title%\n\n",
		footer = "\n## Linked From\n",
	},

	-- UI settings
	window = {
		width = 0.9, -- 90% of screen width
		height = 0.9, -- 90% of screen height
		border = "rounded",
		preview = {
			layout = "vertical",
			vertical = "up:50%",
		},
	},

	-- Search settings
	search = {
		max_results = 1,
		min_similarity = 0.1, -- Minimum similarity score (0-1)
	},

	-- Keymaps
	keymaps = {
		-- Set to false to disable
		follow_link = "<CR>",
		create_link = "<leader>brl",
		search = "<leader>brs",
		find_similar = "<leader>brf",
		open_file = "<leader>brn",
	},
}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
	return M.options
end

return M
