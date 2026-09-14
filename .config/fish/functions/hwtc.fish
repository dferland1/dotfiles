function hwtc --description 'herdr worktree close: tilt down, then remove the worktree + its workspace'
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: not a git repository."
        return 1
    end

    set -l current (git rev-parse --show-toplevel)
    set -l main (git worktree list --porcelain | awk '/^worktree / {print $2; exit}')

    if test "$current" = "$main"
        echo "Error: not in a worktree."
        return 1
    end

    set -l workspace (herdr worktree list --json | python3 -c '
import sys, json
target = sys.argv[1]
for wt in json.load(sys.stdin).get("result", {}).get("worktrees", []):
    if wt.get("path") == target and wt.get("open_workspace_id"):
        print(wt["open_workspace_id"])
        break
' $current)
    if test -z "$workspace"
        echo "Error: no herdr workspace open for $current"
        return 1
    end

    read -l -P "Remove worktree $current? [y/N] " confirm
    string match -qi y $confirm; or return 0

    # Tear down Tilt while the Tiltfile still exists; the worktree-cleanup
    # plugin only sees the post-removal event.
    if type -q tilt; and test -e $current/Tiltfile
        tilt down -f $current/Tiltfile
    end

    # Stop dev servers before Herdr starts deleting the checkout. Otherwise a
    # watcher can recreate files during removal and leave a broken worktree.
    set -l panes (herdr pane list | python3 -c '
import sys, json
workspace, current_pane = sys.argv[1:]
for pane in json.load(sys.stdin).get("result", {}).get("panes", []):
    if pane.get("workspace_id") == workspace and pane.get("pane_id") != current_pane:
        print(pane["pane_id"])
' $workspace "$HERDR_PANE_ID")
    for pane in $panes
        herdr pane send-keys $pane Ctrl+C
    end
    test (count $panes) -eq 0; or sleep 1

    herdr worktree remove --workspace $workspace $argv
end
