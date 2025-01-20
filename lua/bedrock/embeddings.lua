local M = {}

-- Dependencies
local sqlite = require("sqlite")
local curl = require("plenary.curl")

-- Configuration
local OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
local EMBEDDING_MODEL = "text-embedding-3-small"
local VECTOR_SIZE = 1536 -- Size of OpenAI embeddings

local sqlite = require("sqlite.db")
local tbl = require("sqlite.tbl")

-- Database setup
local db = nil

local function setup_database()
	if db then
		return db
	end

	-- Ensure the bedrock directory exists
	local bedrock_dir = vim.fn.expand("~/bedrock")
	if vim.fn.isdirectory(bedrock_dir) == 0 then
		vim.fn.mkdir(bedrock_dir, "p")
	end

	local db_path = vim.fn.expand("~/bedrock/.bedrock.db")

	-- Define tables
	local files = tbl("files", {
		id = true, -- INTEGER PRIMARY KEY
		path = { "text", required = true, unique = true },
		content = "text",
		last_modified = "integer",
	})

	local embeddings = tbl("embeddings", {
		id = true,
		file_id = {
			type = "integer",
			reference = "files.id",
			on_delete = "cascade",
		},
		embedding = "blob",
	})

	-- Create database with tables
	db = sqlite({
		uri = db_path,
		files = files,
		embeddings = embeddings,
	})

	return db
end

-- OpenAI API helpers
local function get_embedding(text)
	if not OPENAI_API_KEY then
		error("OPENAI_API_KEY environment variable not set")
	end

	local response = curl.post("https://api.openai.com/v1/embeddings", {
		headers = {
			Authorization = "Bearer " .. OPENAI_API_KEY,
			["Content-Type"] = "application/json",
		},
		body = vim.json.encode({
			input = text,
			model = EMBEDDING_MODEL,
		}),
	})

	if response.status ~= 200 then
		error("Failed to get embedding: " .. response.body)
	end

	local data = vim.json.decode(response.body)
	return data.data[1].embedding
end

-- File processing
local function get_file_content(filepath)
	local lines = vim.fn.readfile(filepath)
	return table.concat(lines, "\n")
end

local function get_file_modified_time(filepath)
	return vim.fn.getftime(filepath)
end

-- Embedding storage and retrieval
local function store_embedding(filepath, content, embedding)
	local db = setup_database()
	local modified_time = get_file_modified_time(filepath)

	-- Convert embedding to binary blob
	local embedding_blob = table.concat(embedding, ",")

	-- Insert or update file record
	local file = db.files:where({ path = filepath })
	local file_id

	if file then
		-- Update existing file
		db.files:update({
			where = { id = file.id },
			set = {
				content = content,
				last_modified = modified_time,
			},
		})
		file_id = file.id
	else
		-- Insert new file
		file_id = db.files:insert({
			path = filepath,
			content = content,
			last_modified = modified_time,
		})
	end

	-- Insert or update embedding
	local existing_embedding = db.embeddings:where({ file_id = file_id })
	if existing_embedding then
		db.embeddings:update({
			where = { id = existing_embedding.id },
			set = { embedding = embedding_blob },
		})
	else
		db.embeddings:insert({
			file_id = file_id,
			embedding = embedding_blob,
		})
	end
end

-- Main functions
function M.update_file_embedding(filepath)
	local content = get_file_content(filepath)
	local embedding = get_embedding(content)
	store_embedding(filepath, content, embedding)
end

-- Core semantic search function that works with any embedding vector
local function semantic_search(query_embedding, exclude_path, limit)
	local db = setup_database()
	limit = limit or 5

	local query_blob = table.concat(query_embedding, ",")

	-- Build the SQL query with optional path exclusion
	local sql_query = [[
        WITH RECURSIVE
        query_split(word, str, n) AS (
            SELECT '', ? || ',', 1
            UNION ALL
            SELECT
                substr(str, 1, instr(str, ',') - 1),
                substr(str, instr(str, ',') + 1),
                n + 1
            FROM query_split 
            WHERE str != ''
        ),
        query_nums(num, n) AS (
            SELECT CAST(word AS FLOAT), n
            FROM query_split 
            WHERE word != ''
        ),
        file_split(word, str, n, path) AS (
            SELECT '', e.embedding || ',', 1, f.path
            FROM files f
            JOIN embeddings e ON f.id = e.file_id
    ]]

	if exclude_path then
		sql_query = sql_query .. " WHERE f.path != ? "
	end

	sql_query = sql_query
		.. [[
            UNION ALL
            SELECT
                substr(str, 1, instr(str, ',') - 1),
                substr(str, instr(str, ',') + 1),
                n + 1,
                path
            FROM file_split
            WHERE str != ''
        ),
        file_nums(num, n, path) AS (
            SELECT CAST(word AS FLOAT), n, path
            FROM file_split
            WHERE word != ''
        ),
        dot_products AS (
            SELECT 
                f.path,
                SUM(q.num * f.num) as dot_product,
                SQRT(SUM(q.num * q.num)) as q_magnitude,
                SQRT(SUM(f.num * f.num)) as f_magnitude
            FROM query_nums q
            JOIN file_nums f ON q.n = f.n
            GROUP BY f.path
        )
        SELECT 
            path,
            dot_product / (q_magnitude * f_magnitude) as similarity
        FROM dot_products
        ORDER BY similarity DESC
        LIMIT ?
    ]]

	local params = exclude_path and { query_blob, exclude_path, limit } or { query_blob, limit }

	local results = {}
	local rows = db:with_open(function(db0)
		return db0:eval(sql_query, params)
	end)

	for _, row in ipairs(rows) do
		table.insert(results, {
			path = row.path,
			similarity = row.similarity,
		})
	end

	return results
end

-- Search using a text query
function M.search_by_text(query_text, limit)
	local query_embedding = get_embedding(query_text)
	return semantic_search(query_embedding, "this path does not exists nil nil", limit)
end

-- Search for similar files to a given file
function M.find_similar(filepath, limit)
	local content = get_file_content(filepath)
	local query_embedding = get_embedding(content)
	return semantic_search(query_embedding, filepath, limit)
end

function M.setup(opts)
	opts = opts or {}
	if opts.openai_api_key then
		OPENAI_API_KEY = opts.openai_api_key
	end
	if opts.embedding_model then
		EMBEDDING_MODEL = opts.embedding_model
	end

	-- Initialize database
	setup_database()
end

-- Cleanup
function M.close()
	if db then
		db:close()
		db = nil
	end
end

return M
