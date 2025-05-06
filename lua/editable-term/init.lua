local M = {}
local function term_codes(keys)
    return vim.api.nvim_replace_termcodes(keys, true, false, true)
end
local function update_line(buf, chan, ln)
    local bufinfo = M.buffers[buf]
    local cursor = vim.api.nvim_win_get_cursor(0)
    if not bufinfo.promt_cursor or cursor[1] ~= bufinfo.promt_cursor[1] then
        return
    end
    vim.fn.chansend(chan, term_codes(bufinfo.keybinds.clear_current_line))
    local line = ln or vim.api.nvim_get_current_line()
    vim.fn.chansend(chan, line:sub(bufinfo.promt_cursor[2] + 1))
    local p = term_codes(bufinfo.keybinds.goto_line_start) ..
        vim.fn['repeat'](term_codes(bufinfo.keybinds.forward_char),
            cursor[2] - bufinfo.promt_cursor[2])
    vim.fn.chansend(chan, p)
    M.buffers[buf].waiting = true
    vim.defer_fn(function()
        M.buffers[buf].waiting = false
    end, M.wait_for_keys_delay)
end
local function get_term_cursor()
    local prevcursor = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_feedkeys('i', 'x', false)
    vim.schedule(function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        vim.api.nvim_input('<C-\\><C-N>')
    end)
end
local function set_term_cursor(cursor)
    local bufinfo = M.buffers[vim.api.nvim_get_current_buf()]
    local p = term_codes(bufinfo.keybinds.goto_line_start) ..
        vim.fn['repeat'](term_codes(bufinfo.keybinds.forward_char),
            cursor - bufinfo.promt_cursor[2])
    vim.fn.chansend(vim.bo.channel, p)
end

---@class Promt
---@field keybinds? Keybinds

---@class Keybinds
---@field clear_current_line string
---@field forward_char string
---@field goto_line_start string

---@class EditableTermConfig
---@field default_keybinds? Keybinds
---@field promts? {[string]: Promt}
---@field wait_for_keys_delay integer

---@param config EditableTermConfig
M.setup = function(config)
    M.buffers = {}
    M.promts = (config or {}).promts
    M.default_keybinds = (config or {}).default_keybinds or {
        clear_current_line = '<C-e><C-u>',
        forward_char = '<C-f>',
        goto_line_start = '<C-a>',
        goto_line_end = '<C-e>',
    }
    M.wait_for_keys_delay = (config or {}).wait_for_keys_delay or 50
    vim.api.nvim_create_autocmd('TermOpen', {
        group = vim.api.nvim_create_augroup('editable-term', {}),
        callback = function(args)
            local editgroup = vim.api.nvim_create_augroup('editable-term-text-change' .. args.buf, { clear = true })
            M.buffers[args.buf] = { leaving_term = true, keybinds = M.default_keybinds }
            vim.keymap.set('n', 'A', function()
                local bufinfo = M.buffers[args.buf]
                if bufinfo.promt_cursor then
                    local cursor_row, cursor_col = unpack(bufinfo.promt_cursor)
                    local line = vim.api.nvim_buf_get_lines(args.buf, cursor_row - 1, cursor_row, false)[1]
                    line = line:sub(cursor_col)
                    local start, _ = line:find('%s*$')
                    local p = term_codes(bufinfo.keybinds.goto_line_start) ..
                        vim.fn['repeat'](term_codes(bufinfo.keybinds.forward_char),
                            start - 2)
                    vim.fn.chansend(vim.bo.channel, p)
                end
                vim.cmd [[ startinsert ]]
            end, { buffer = args.buf })
            vim.keymap.set('n', 'I', function()
                local bufinfo = M.buffers[args.buf]
                if bufinfo.promt_cursor then
                    local cursor_row, cursor_col = unpack(bufinfo.promt_cursor)
                    local line = vim.api.nvim_buf_get_lines(args.buf, cursor_row - 1, cursor_row, false)[1]
                    line = line:sub(cursor_col)
                    local _, ent = line:find('[^%s]')
                    local p = term_codes(bufinfo.keybinds.goto_line_start) ..
                        vim.fn['repeat'](term_codes(bufinfo.keybinds.forward_char),
                            ent - 2)
                    vim.fn.chansend(vim.bo.channel, p)
                end
                vim.cmd [[ startinsert ]]
            end, { buffer = args.buf })
            vim.keymap.set('n', 'i', function()
                local bufinfo = M.buffers[args.buf]
                local cursor = vim.api.nvim_win_get_cursor(0)
                if bufinfo.promt_cursor then
                    if cursor[1] == bufinfo.promt_cursor[1] then
                        set_term_cursor(cursor[2])
                    else
                        vim.fn.chansend(vim.bo.channel, term_codes(bufinfo.keybinds.goto_line_end))
                    end
                end
                vim.cmd [[ startinsert ]]
            end, { buffer = args.buf })
            vim.keymap.set('n', 'a', function()
                local bufinfo = M.buffers[args.buf]
                if bufinfo.promt_cursor then
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    if cursor[1] == bufinfo.promt_cursor[1] then
                        local p = term_codes(bufinfo.keybinds.goto_line_start) ..
                            vim.fn['repeat'](term_codes(bufinfo.keybinds.forward_char),
                                cursor[2] - bufinfo.promt_cursor[2] + 1)
                        vim.fn.chansend(vim.bo.channel, p)
                    else 
                        vim.fn.chansend(vim.bo.channel, term_codes(bufinfo.keybinds.goto_line_end))
                    end
                end
                vim.cmd [[ startinsert ]]
            end, { buffer = args.buf })
            vim.keymap.set('n', 'dd', function()
                local bufinfo = M.buffers[args.buf]
                bufinfo.leaving_term = true
                vim.fn.chansend(vim.bo.channel,
                    vim.api.nvim_replace_termcodes(
                        bufinfo.keybinds.clear_current_line .. bufinfo.keybinds.goto_line_start, true, false, true))
                set_term_cursor(0)
            end, { buffer = args.buf })
            vim.api.nvim_create_autocmd('TextYankPost', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    local start = vim.api.nvim_buf_get_mark(args.buf, '[')
                    local ent = vim.api.nvim_buf_get_mark(args.buf, ']')
                    if start[1] ~= ent[1] then
                        vim.fn.chansend(vim.bo.channel, term_codes('<C-C>'))
                    elseif vim.v.event.operator == 'c' then
                        local line = vim.api.nvim_get_current_line()
                        line = line:sub(1, start[2]) .. line:sub(ent[2] + 2)
                        update_line(args.buf, vim.bo.channel, line)
                        if start[1] == ent[1] and start[2] == ent[2] then
                            set_term_cursor(start[2] - 1)
                        else
                            set_term_cursor(start[2])
                        end
                    end
                end
            })
            vim.api.nvim_create_autocmd('TextChanged', {
                buffer = args.buf,
                group = editgroup,
                callback = function(args)
                    local bufinfo = M.buffers[args.buf]
                    if not bufinfo.leaving_term and not bufinfo.waiting then
                        update_line(args.buf, vim.bo.channel)
                    else
                        bufinfo.leaving_term = false
                    end
                end
            })
            vim.api.nvim_create_autocmd('TermLeave', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    local bufinfo = M.buffers[args.buf]
                    bufinfo.leaving_term = true
                    local ln = vim.api.nvim_get_current_line()
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    vim.api.nvim_win_set_cursor(0, cursor);
                    line_num = cursor[1]
                    if M.promts ~= nil and ln ~= nil then
                        for pattern, promt in pairs(M.promts) do
                            start, ent = ln:find(pattern)
                            if start ~= nil then
                                bufinfo.promt_cursor = { line_num, ent }
                                bufinfo.keybinds = promt.keybinds or M.default_keybinds
                                break
                            end
                        end
                    end
                end
            })
            vim.api.nvim_create_autocmd('TermRequest', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    if string.match(args.data.sequence, '^\027]133;B') then
                        M.buffers[args.buf].promt_cursor = args.data.cursor
                    end
                end,
            })
            vim.api.nvim_create_autocmd('BufDelete', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    vim.api.nvim_del_augroup_by_id(editgroup)
                end,
            })
            vim.api.nvim_create_autocmd('CursorMoved', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local bufinfo = M.buffers[args.buf]
                    vim.bo.modifiable = bufinfo.promt_cursor ~= nil and cursor[1] == bufinfo.promt_cursor[1]
                end,
            })
        end
    })
end
return M
