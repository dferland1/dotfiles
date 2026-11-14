rex.bind("cmd+shift+h", "pane.focus", { direction = "left" })
rex.bind("cmd+shift+j", "pane.focus", { direction = "down" })
rex.bind("cmd+shift+k", "pane.focus", { direction = "up" })
rex.bind("cmd+shift+l", "pane.focus", { direction = "right" })
rex.unbind("alt+cmd+m")
rex.bind("cmd+shift+m", "pane.minimize_floating")

local worktree_command = [=[
set -euo pipefail

IFS= read -r -d '' main_record < <(git worktree list --porcelain -z)
main_repo=${main_record#worktree }
project=$(basename "$main_repo")

branch=$1
case "$branch" in
    -*) printf 'Branch names cannot start with a dash.\n' >&2; exit 1 ;;
esac
git check-ref-format "refs/heads/$branch"

worktree="$(dirname "$main_repo")/.worktrees/$project/$branch"
if [[ -e "$worktree" || -L "$worktree" ]]; then
    printf 'Worktree path already exists: %s\n' "$worktree" >&2
    exit 1
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add -- "$worktree" "$branch"
else
    status=$?
    [[ "$status" -eq 1 ]] || exit "$status"
    git worktree add -b "$branch" -- "$worktree" HEAD
fi

cd "$worktree"
window_id=$(rex block inspect "$REX_BLOCK" --json | jq -er '.block.window_id')
rex window rename -s "$REX_SESSION" "$window_id" "$project/$branch"
exec "${SHELL:-/bin/sh}" -l
]=]

local worktree_prompt = [=[
set -euo pipefail

show_error() {
    osascript - "$1" <<'APPLESCRIPT'
on run argv
    display alert "Cannot Create Worktree" message (item 1 of argv) as critical
end run
APPLESCRIPT
}

if branch=$(osascript 2>&1 <<'APPLESCRIPT'
try
    activate
    set response to display dialog "Worktree name (Git branch):" default answer "" with title "New Worktree" buttons {"Cancel", "Create"} default button "Create" cancel button "Cancel"
    return text returned of response
on error messageText number errorNumber
    if errorNumber is -128 then return ""
    error messageText number errorNumber
end try
APPLESCRIPT
); then
    [[ -n "$branch" ]] || exit 0
else
    show_error "$branch"
    exit 1
fi

if output=$(rex do -s "$1" -b "$2" new_worktree "branch=$branch" 2>&1); then
    exit 0
else
    show_error "$output"
    exit 1
fi
]=]

rex.action({
    name = "new_worktree",
    title = "New Worktree Tab",
    args = { branch = "string?" },
    run = function(ctx, args)
        if not args.branch or args.branch == "" then
            if not ctx.session_id or not ctx.block_id then
                error("Run this action from a terminal in a Rex session", 0)
            end
            -- A dialog may outlive Rex's 30-second action limit.
            local prompt, prompt_err = rex.exec.start({
                "bash", "-c", worktree_prompt, "worktree-prompt", ctx.session_id, ctx.block_id,
            }, { detach = true })
            if not prompt then error(prompt_err, 0) end
            return
        end

        local process, err = rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id })
        if err ~= nil then error(err, 0) end
        local cwd = process.foreground and process.foreground.cwd
        if not cwd then error("Cannot determine the focused terminal's working directory", 0) end

        local window, window_err = rex.session.new_window({
            window_label = "New worktree",
            layout = rex.layout.block({
                flavor = "com.superlogical.terminal.shell",
                options = {
                    cwd = cwd,
                    shell = "none",
                    command = { "bash", "-c", worktree_command, "new-worktree", args.branch },
                    exit = { on_completion = false },
                },
            }),
        })
        if window_err ~= nil then error(window_err, 0) end
        return window
    end,
})

rex.bind("cmd+shift+t", "new_worktree")
