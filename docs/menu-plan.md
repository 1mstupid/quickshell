# Menu: plan

Status: approved, open questions resolved. Code starts on this branch after the review.

## Summary

The bar morphs into a row of six icon tabs: Todo, Habits, Pomodoro, Wi-Fi,
Bluetooth, VPN. A drop-down notch below the bar holds the active tab's panel.

- Opens from a click on the clock, or `qs ipc call menu toggle`.
- Always on the origin screen.
- While open, the bar's contents (workspaces, clock, recorder, media) hide.
- Closes on Escape, on a click outside, or on a second click on the clock.
- Tabs and the drop-down are one notch, so the menu reads as the bar growing.
- Icons only, no labels.

## Storage

All files live in `~/.local/xdg/config/`.

- `todo-YYYY-MM-DD.txt`: one file per due date. Created on first use.
- `habits.json`: today's habits and their history (see below).
- `pomodoro`: existing state file. Kept, because it lets a running timer survive
  a bar restart. The panel only reads and writes it through the `Pomodoro`
  singleton.

## Todo

Line format:

    - [ ] Send the weekly update | due 2026-10-26 | p1

- `[ ]` / `[x]` is the tick state.
- `due` is required. It's written from the file's date by default.
- `p1`–`p3` is an optional priority. Items without one sort after items with one.

Items are stored in the file for their due date. Adding a task with a later due
date writes it into that day's file. A new file starts with a `# YYYY-MM-DD`
header, which is the template.

The panel lists items in groups, scrollable:

1. Overdue
2. Today
3. Tomorrow
4. This week
5. This month
6. Later

Within a group, items sort by priority, then by file order. Operations: add,
tick, delete. Deleting removes the line from its file.

## Habits

`habits.json`:

    {
      "day": "2026-10-24",
      "habits": [
        {"id": "0", "name": "Read", "status": "completed"}
      ],
      "history": {
        "2026-10-23": ["0"]
      }
    }

`day` is added so the shell knows which date `status` refers to. That lets it
close out a day even if the shell wasn't running at midnight.

- At midnight, each habit's `status` resets to `pending`, and the previous day's
  completed ids are written to `history`.
- The panel shows a card per habit: name, a 5-week grid from `history`, a check
  button that toggles today, and a streak count.
- Streak: consecutive days ending today, or ending yesterday if today is still
  pending.
- Writes go through `FileView` with `atomicWrites`, like the launcher's recents.

## Pomodoro panel

- Start, pause, resume and stop, through the `Pomodoro` singleton.
- Duration in minutes, editable in the panel, saved through the same state file.

## Network

Split into three tabs, each polling only while its tab is open:

- Wi-Fi: scan list, connect, password prompt, radio toggle.
- Bluetooth: power toggle, paired devices, pair new. Hidden if there's no adapter.
- VPN: saved profiles (including WireGuard) and external tunnels.

## Files

- `services/menu/MenuState.qml` (new): open state, active tab, owns `PillState`.
- `services/menu/Todo.qml`, `services/menu/Habits.qml`: storage and logic. The
  `services/menu/` folder has its own `qmldir`.
- `widgets/menu/Menu.qml` (new): drop-down notch and tab panels.
- `widgets/bar/Bar.qml`: morph into the tab row, and hide contents while open.
- `widgets/network/Network.qml`: split into the Wi-Fi, Bluetooth and VPN panels.
- `shell.qml`: import the menu.

## Decisions

- Overdue items go in their own group, at the top.
- Priority is `p1`–`p3`.
- The template is the `# YYYY-MM-DD` header and nothing else.
