local worktree = {}

local function checked(result, err)
    if err ~= nil then error(err, 0) end
    return result
end

function worktree.open_prompt(ctx, operation, branch)
    if not ctx.session_id or not ctx.block_id then
        error("Run this action from a terminal in a Rex session", 0)
    end
    local process = checked(rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id }))
    local cwd = process.foreground and process.foreground.cwd
    if not cwd then error("Cannot determine the focused terminal's working directory", 0) end
    if operation == "create" then
        local git_dirs = {}
        for _, flag in ipairs({ "--git-dir", "--git-common-dir" }) do
            local result = checked(rex.exec({ "git", "rev-parse", "--path-format=absolute", flag }, { cwd = cwd }))
            if not result.ok then error(result.stderr, 0) end
            git_dirs[#git_dirs + 1] = result.stdout
        end
        if git_dirs[1] ~= git_dirs[2] then
            error("Create worktrees from the main checkout, not another worktree.", 0)
        end
    end
    local source = checked(rex.session.describe_block({ block_id = ctx.block_id }))
    local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
    local pane_bounds = dofile(config_home .. "/rex/pane-bounds.lua")
    local payload = checked(rex.json.encode({
        operation = operation, branch = branch, cwd = cwd, config_home = config_home,
    }))

    return checked(rex.session.new_layer({
        window_id = source.block.window_id,
        bounds = pane_bounds.prompt,
        focus = true,
        layout = rex.layout.block({
            flavor = "com.superlogical.terminal.shell",
            label = operation == "create" and "New worktree" or "Clean up worktree",
            options = {
                cwd = config_home,
                -- Keep checkout and Tilt commands outside the action's 30-second limit.
                command = { "fish", config_home .. "/rex/worktree-prompt.fish", payload },
                exit = { on_completion = false },
            },
        }),
    }))
end

function worktree.run(args)
    local pane_bounds = dofile(args.config_home .. "/rex/pane-bounds.lua")

    local function run_script(name, script_args, cwd)
        local command = { "fish", args.config_home .. "/fish/scripts/" .. name .. ".fish" }
        for _, arg in ipairs(script_args) do command[#command + 1] = arg end
        local result = checked(rex.exec(command, { cwd = cwd }))
        if result.stderr ~= "" then io.stderr:write(result.stderr) end
        if not result.ok then error(name .. " failed (exit " .. result.code .. ")", 0) end
        return checked(rex.json.decode(result.stdout))
    end

    local source = checked(rex.session.describe_block({ block_id = rex.block_id }))
    local window_id = source.block.window_id

    if args.operation == "create" then
        local checkout = run_script("worktree-create", { args.branch }, args.cwd)
        local window = checked(rex.session.new_window({
            window_label = checkout.project .. "/" .. checkout.branch,
            focus = false,
            layout = rex.layout.block({
                flavor = "com.superlogical.terminal.shell",
                options = { cwd = checkout.worktree },
            }),
        }))
        for _, app in ipairs({
            { label = "Lazygit", command = { "lazygit" } },
            { label = "Neovim", command = { "nvim", "." } },
        }) do
            local layer = checked(rex.session.new_layer({
                window_id = window.window_id,
                bounds = pane_bounds.work,
                focus = false,
                layout = rex.layout.block({
                    flavor = "com.superlogical.terminal.shell",
                    label = app.label,
                    options = { cwd = checkout.worktree, command = app.command },
                }),
            }))
            checked(rex.call("session.set_layer_state", {
                session_id = rex.session_id, layer_id = layer.layer_id, state = "minimized",
            }))
        end
        -- Dismiss the prompt before switching tabs so its closure cannot restore the old focus.
        checked(rex.session.detach_block({ block_id = rex.block_id }))
        checked(rex.session.focus_window({ window_id = window.window_id }))
        checked(rex.call("block.close", { session_id = rex.session_id, block_id = rex.block_id }))
    elseif args.operation == "close" then
        local checkout = run_script("worktree-close", { "--prepare", args.cwd }, args.config_home)
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
        run_script("worktree-close", { "--remove", checkout.worktree }, checkout.main_repo)
        checked(rex.session.close_window({ window_id = window_id }))
    else
        error("Unknown worktree operation: " .. tostring(args.operation), 0)
    end
end

return worktree
