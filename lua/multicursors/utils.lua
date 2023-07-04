local api = vim.api

local ns_id = api.nvim_create_namespace 'multicursors'
local main_ns_id = api.nvim_create_namespace 'multicursorsmaincursor'

---@class Utils
local M = {}

---@enum ActionPosition
M.position = {
    before = true,
    after = false,
}

--- @enum Namespace
M.namespace = {
    Main = 'MultiCursorMain',
    Multi = 'MultiCursor',
}

--- creates a extmark for the the match
--- doesn't create a duplicate mark
---@param match Match
---@param namespace Namespace
---@return integer id of created mark
M.create_extmark = function(match, namespace)
    local ns = ns_id
    if namespace == M.namespace.Main then
        ns = main_ns_id
    end

    local marks = api.nvim_buf_get_extmarks(
        0,
        ns,
        { match.row, match.start },
        { match.row, match.finish },
        {}
    )
    if #marks > 0 then
        M.debug('found ' .. #marks .. ' duplicate marks:')
        return marks[1][1]
    end

    local s = api.nvim_buf_set_extmark(0, ns, match.row, match.start, {
        end_row = match.row,
        end_col = match.finish,
        hl_group = namespace,
    })
    vim.cmd [[ redraw! ]]
    return s
end

--- Deletes the extmark in current buffer in range of match
---@param match Match
---@param namespace Namespace
M.delete_extmark = function(match, namespace)
    local ns = ns_id
    if namespace == M.namespace.Main then
        ns = main_ns_id
    end

    local marks = api.nvim_buf_get_extmarks(
        0,
        ns,
        { match.row, match.start },
        { match.row, match.finish },
        {}
    )
    if #marks > 0 then
        api.nvim_buf_del_extmark(0, ns, marks[1][1])
    end
end

--- clears the namespace in current buffer
---@param namespace  Namespace
M.clear_namespace = function(namespace)
    local ns = ns_id
    if namespace == M.namespace.Main then
        ns = main_ns_id
    end
    api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

---@param any any
M.debug = function(any)
    if vim.g.MultiCursorDebug then
        vim.notify(vim.inspect(any), vim.log.levels.DEBUG)
    end
end

--- returns selected range in visual mode
---@return Range?
M.get_visual_range = function()
    local start_pos = api.nvim_buf_get_mark(0, '<')
    local end_pos = api.nvim_buf_get_mark(0, '>')

    if start_pos[1] == end_pos[1] and start_pos[2] == end_pos[2] then
        return nil
    end

    -- when in visual line mode nvim returns v:maxcol instead of line length
    -- so we have to find line length ourselves
    local row = api.nvim_buf_get_lines(0, end_pos[1] - 1, end_pos[1], true)[1]
    return {
        start_row = start_pos[1] - 1,
        start_col = start_pos[2],
        end_row = end_pos[1] - 1,
        end_col = #row,
    }
end

--- returns text inside selected range
---@param whole_buffer boolean
---@param range Range?
---@return string[]?
M.get_buffer_content = function(whole_buffer, range)
    if whole_buffer then
        return api.nvim_buf_get_lines(
            0,
            0,
            api.nvim_buf_line_count(0) - 1,
            true
        )
    end

    if not range then
        return {}
    end

    return api.nvim_buf_get_text(
        0,
        range.start_row,
        range.start_col,
        range.end_row,
        range.end_col,
        {}
    )
end

---@param details boolean
---@return any
M.get_main_selection = function(details)
    return api.nvim_buf_get_extmarks(
        0,
        main_ns_id,
        0,
        -1,
        { details = details }
    )[1]
end

--- returns the list of cursors extmarks
---@param details boolean
---@return any[]  [extmark_id, row, col] tuples in "traversal order".
M.get_all_selections = function(details)
    local extmarks =
        api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = details })
    return extmarks
end

--- Creates a extmark for current match and
--- updates the main selection
---@param match Match match to mark
---@param skip boolean wheter or not skip current match
M.mark_found_match = function(match, skip)
    -- first clear the main selection
    -- then create a selection in place of main one
    local main = M.get_main_selection(true)
    M.clear_namespace(M.namespace.Main)

    if not skip then
        M.create_extmark(
            { row = main[2], start = main[3], finish = main[4].end_col },
            M.namespace.Multi
        )
    end
    --create the main selection
    M.create_extmark(match, M.namespace.Main)
    --deletes the selection when there was a selection there
    M.delete_extmark(match, M.namespace.Multi)

    M.move_cursor({ match.row + 1, match.start }, nil)
end

--- Swaps the next selection with main selection
--- wraps around the buffer
M.goto_next_selection = function()
    local main = M.get_main_selection(true)
    local selections = api.nvim_buf_get_extmarks(
        0,
        ns_id,
        { main[4].end_row, main[4].end_col },
        -1,
        { details = true }
    )
    if #selections > 0 then
        M.mark_found_match({
            row = selections[1][4].end_row,
            start = selections[1][3],
            finish = selections[1][4].end_col,
        }, false)
        return
    end
    selections = api.nvim_buf_get_extmarks(
        0,
        ns_id,
        0,
        { main[4].end_row, main[4].end_col },
        { details = true }
    )
    if #selections > 0 then
        M.mark_found_match({
            row = selections[1][4].end_row,
            start = selections[1][3],
            finish = selections[1][4].end_col,
        }, false)
    end
end

--- Swaps the previous selection with main selection
--- wraps around the buffer
M.goto_prev_selection = function()
    local main = M.get_main_selection(true)
    local selections = api.nvim_buf_get_extmarks(
        0,
        ns_id,
        { main[4].end_row, main[4].end_col },
        0,
        { details = true }
    )
    if #selections > 0 then
        M.mark_found_match({
            row = selections[1][4].end_row,
            start = selections[1][3],
            finish = selections[1][4].end_col,
        }, false)
        return
    end
    selections = api.nvim_buf_get_extmarks(
        0,
        ns_id,
        -1,
        { main[4].end_row, main[4].end_col },
        { details = true }
    )
    if #selections > 0 then
        M.mark_found_match({
            row = selections[1][4].end_row,
            start = selections[1][3],
            finish = selections[1][4].end_col,
        }, false)
    end
end

--- gets a single char from user
--- when intrupted returns nil
---@return string?
M.get_char = function()
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok then
        return nil
    end

    return key
end

--- calls a callback on all selections
---@param callback function function to call
---@param on_main boolean execute the callback on main selesction
---@param with_details boolean get the selection details
M.call_on_selections = function(callback, on_main, with_details)
    local marks = M.get_all_selections(with_details)
    for _, selection in pairs(marks) do
        -- get each mark again cause inserting text might moved the other marks
        local mark = api.nvim_buf_get_extmark_by_id(
            0,
            ns_id,
            selection[1],
            { details = true }
        )

        callback(mark)
    end

    if on_main then
        local main = M.get_main_selection(true)
        callback { main[2], main[3], main[4] }
    end
end

--- updates each selection to a single char
---@param before ActionPosition
M.update_selections = function(before)
    local marks = M.get_all_selections(true)
    local main = M.get_main_selection(true)
    M.exit()

    local col = main[4].end_col - 1
    if before then
        col = main[3] - 1
    else
        M.move_cursor { main[4].end_row + 1, main[4].end_col }
    end

    M.create_extmark(
        { row = main[4].end_row, start = col, finish = col + 1 },
        M.namespace.Main
    )

    for _, mark in pairs(marks) do
        col = mark[4].end_col - 1
        if before then
            col = mark[3] - 1
        end

        M.create_extmark(
            { row = mark[4].end_row, start = col, finish = col + 1 },
            M.namespace.Multi
        )
    end
end

---
---@param length integer
M.move_selections_horizontal = function(length)
    local marks = M.get_all_selections(true)
    local main = M.get_main_selection(true)
    M.exit()

    local get_position = function(mark)
        local col = mark[4].end_col + length - 1
        local row = mark[4].end_row

        local line =
            string.len(api.nvim_buf_get_lines(0, row, row + 1, true)[1])
        if col < 0 then
            col = -1
        elseif col >= line then
            col = line - 1
        end
        return row, col
    end

    local row, col = get_position(main)
    M.create_extmark(
        { start = col, finish = col + 1, row = row },
        M.namespace.Main
    )
    M.move_cursor { row + 1, col + 1 }

    for _, mark in pairs(marks) do
        row, col = get_position(mark)

        M.create_extmark(
            { start = col, finish = col + 1, row = row },
            M.namespace.Multi
        )
    end
end

---
---@param length integer
M.move_selections_vertical = function(length)
    local marks = M.get_all_selections(true)
    local main = M.get_main_selection(true)

    M.exit()

    local get_position = function(mark)
        local col = mark[3]
        local row = mark[2] + length
        local buf_length = api.nvim_buf_line_count(0)

        if row < 1 then
            row = 0
        elseif row >= buf_length then
            row = buf_length - 1
        end

        local line_length =
            string.len(api.nvim_buf_get_lines(0, row, row + 1, true)[1])

        if col < 0 then
            col = -1
        elseif col >= line_length then
            col = line_length - 1
        end
        return row, col
    end

    local row, col = get_position(main)
    M.create_extmark(
        { start = col, finish = col + 1, row = row },
        M.namespace.Main
    )
    M.move_cursor { row + 1, col + 1 }

    for _, mark in pairs(marks) do
        row, col = get_position(mark)
        M.create_extmark(
            { start = col, finish = col + 1, row = row },
            M.namespace.Multi
        )
    end
end

---
---@param text string
M.insert_text = function(text)
    M.call_on_selections(function(selection)
        local col = selection[3].end_col
        local row = selection[3].end_row
        api.nvim_buf_set_text(0, row, col, row, col, { text })
    end, false, false)

    M.move_selections_horizontal(#text)
end

--- Aligns selections by adding space
---@param line_start boolean add spaces before selection or at the start of line
M.align_text = function(line_start)
    local max_col = -1
    M.call_on_selections(function(selection)
        if selection[2] > max_col then
            max_col = selection[2]
        end
    end, true, false)

    M.call_on_selections(function(selection)
        local col = selection[2]
        local row = selection[1]
        local count = max_col - col
        if line_start then
            col = 0
        end

        if count > 0 then
            api.nvim_buf_set_text(
                0,
                row,
                col,
                row,
                col,
                { string.rep(' ', count) }
            )
        end
    end, true, false)
end

M.delete_char = function()
    M.call_on_selections(function(mark)
        local col = mark[3].end_col - 1
        if col < 0 then
            return
        end

        api.nvim_win_set_cursor(0, { mark[3].end_row + 1, col })
        vim.cmd [[normal x]]
    end, true, false)

    M.move_selections_horizontal(0)
end

--- Moves the cursor to pos and marks current cursor position in jumplist
--- htpps://github.com/neovim/neovim/issues/20793
---@param pos any[]
---@param current any[]?
M.move_cursor = function(pos, current)
    if not current then
        current = api.nvim_win_get_cursor(0)
    end

    api.nvim_buf_set_mark(0, "'", current[1], current[2], {})
    api.nvim_win_set_cursor(0, { pos[1], pos[2] })
end

M.exit = function()
    M.clear_namespace(M.namespace.Main)
    M.clear_namespace(M.namespace.Multi)
end

return M
