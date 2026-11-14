rex.bind("cmd+shift+h", "pane.focus", { direction = "left" })
rex.bind("cmd+shift+j", "pane.focus", { direction = "down" })
rex.bind("cmd+shift+k", "pane.focus", { direction = "up" })
rex.bind("cmd+shift+l", "pane.focus", { direction = "right" })
rex.unbind("alt+cmd+m")
rex.bind("cmd+shift+m", "pane.minimize_floating")

local pane_bounds = {
    prompt = { 0.25, 0.39, 0.5, 0.22 },
    work = { 0.15, 0, 0.85, 1 },
}

local worktree_prompt = [=[
function cancel
    rex block close -s "$REX_SESSION" "$REX_BLOCK"
    exit 0
end
trap cancel INT

set -l payload "$argv[2]"
set -l operation (printf '%s' "$payload" | jq -er '.operation')
or exit $status
if test "$operation" = create
    set -l branch (printf '%s' "$payload" | jq -r '.branch // ""')
    if test -z "$branch"
        printf 'New worktree\n\nEnter a Git branch name. Empty input or Ctrl+C cancels.\n\n'
        read -l -P 'Branch: ' branch
        or cancel
        test -n "$branch"
        or cancel
        set payload (printf '%s' "$payload" | jq -c --arg branch "$branch" '. + {branch: $branch}')
        or exit $status
    end
else
    printf 'Remove worktree at: %s\n\n' (printf '%s' "$payload" | jq -r '.cwd')
    printf 'This runs tilt down if a Tiltfile exists, closes every pane in this tab,\nand removes the checkout. The Git branch is kept.\n\n'
    read -l -P 'Continue? [y/N] ' confirm
    or cancel
    contains -- "$confirm" y Y
    or cancel
end

rex do "$argv[1]" --args "$payload"
]=]

local function open_worktree_prompt(ctx, operation, branch)
    if not ctx.session_id or not ctx.block_id then
        error("Run this action from a terminal in a Rex session", 0)
    end
    local process, err = rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id })
    if err ~= nil then error(err, 0) end
    local cwd = process.foreground and process.foreground.cwd
    if not cwd then error("Cannot determine the focused terminal's working directory", 0) end
    local source, source_err = rex.session.describe_block({ block_id = ctx.block_id })
    if source_err ~= nil then error(source_err, 0) end
    local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
    local payload, payload_err = rex.json.encode({
        operation = operation, branch = branch, cwd = cwd, config_home = config_home,
    })
    if payload_err ~= nil then error(payload_err, 0) end

    local prompt, prompt_err = rex.session.new_layer({
        window_id = source.block.window_id,
        bounds = pane_bounds.prompt,
        focus = true,
        layout = rex.layout.block({
            flavor = "com.superlogical.terminal.shell",
            label = operation == "create" and "New worktree" or "Clean up worktree",
            options = {
                cwd = config_home,
                -- Keep checkout and Tilt commands outside the action's 30-second limit.
                command = { "fish", "-c", worktree_prompt, config_home .. "/rex/worktree.lua", payload },
                exit = { on_completion = false },
            },
        }),
    })
    if prompt_err ~= nil then error(prompt_err, 0) end
    return prompt
end

rex.action({
    name = "new_worktree",
    title = "New Worktree Tab",
    args = { branch = "string?" },
    run = function(ctx, args)
        return open_worktree_prompt(ctx, "create", args.branch)
    end,
})
rex.bind("cmd+shift+t", "new_worktree")

rex.action({
    name = "cleanup_worktree",
    title = "Clean Up Worktree",
    run = function(ctx)
        return open_worktree_prompt(ctx, "close")
    end,
})
rex.bind("cmd+shift+c", "cleanup_worktree")
