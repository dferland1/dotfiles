local function checked(result, err)
    if err ~= nil then error(err, 0) end
    return result
end

local function run_script(name, args, cwd)
    local command = { "fish", rex.args.config_home .. "/fish/scripts/" .. name .. ".fish" }
    for _, arg in ipairs(args) do command[#command + 1] = arg end
    local result = checked(rex.exec(command, { cwd = cwd }))
    if result.stderr ~= "" then io.stderr:write(result.stderr) end
    if not result.ok then error(name .. " failed (exit " .. result.code .. ")", 0) end
    return checked(rex.json.decode(result.stdout))
end

local source = checked(rex.session.describe_block({ block_id = rex.block_id }))
local window_id = source.block.window_id

if rex.args.operation == "create" then
    local worktree = run_script("worktree-create", { rex.args.branch }, rex.args.cwd)
    checked(rex.session.set_window_label({
        window_id = window_id, label = worktree.project .. "/" .. worktree.branch,
    }))
    local shell = checked(rex.session.new_split({
        anchor_id = rex.block_id,
        direction = "horizontal",
        side = "after",
        focus = true,
        layout = rex.layout.block({
            flavor = "com.superlogical.terminal.shell",
            options = { cwd = worktree.worktree },
        }),
    }))
    for _, app in ipairs({
        { label = "Lazygit", command = { "lazygit" } },
        { label = "Neovim", command = { "nvim", "." } },
    }) do
        local layer = checked(rex.session.new_layer({
            window_id = window_id,
            bounds = { 0.1, 0.1, 0.8, 0.8 },
            focus = false,
            layout = rex.layout.block({
                flavor = "com.superlogical.terminal.shell",
                label = app.label,
                options = { cwd = worktree.worktree, command = app.command },
            }),
        }))
        checked(rex.call("session.set_layer_state", {
            session_id = rex.session_id, layer_id = layer.layer_id, state = "minimized",
        }))
    end
    checked(rex.session.focus_block({ block_id = shell.block_ids[1] }))
    checked(rex.call("block.close", { session_id = rex.session_id, block_id = rex.block_id }))
elseif rex.args.operation == "close" then
    local worktree = run_script("worktree-close", { "--prepare", rex.args.cwd }, rex.args.config_home)
    local view = checked(rex.session.view({}))
    for _, window in ipairs(view.windows) do
        if window.window_id == window_id then
            for _, layer in ipairs(window.layers) do
                for _, block in ipairs(layer.blocks) do
                    if block.block_id ~= rex.block_id then
                        checked(rex.call("block.close", {
                            session_id = rex.session_id, block_id = block.block_id,
                        }))
                    end
                end
            end
        end
    end
    run_script("worktree-close", { "--remove", worktree.worktree }, worktree.main_repo)
    checked(rex.session.close_window({ window_id = window_id }))
else
    error("Unknown worktree operation: " .. tostring(rex.args.operation), 0)
end
