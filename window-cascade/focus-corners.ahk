; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; overlay updates
; =============================================================================

QueueFocusCornerUpdate()
{
    global focus_corner_update_pending
    global focus_corner_update_ms

    if focus_corner_update_pending
        return

    focus_corner_update_pending := true

    SetTimer(
        RunQueuedFocusCornerUpdate,
        -focus_corner_update_ms
    )
}

RunQueuedFocusCornerUpdate()
{
    global focus_corner_update_pending

    focus_corner_update_pending := false
    UpdateFocusCornerOverlays()
}

UpdateFocusCornerOverlays()
{
    global focus_corner_overlays, focus_tab_click_generation, cascade_slot_tolerance
    static update_generation := 0

    generation := ++update_generation
    click_generation := focus_tab_click_generation
    active_hwnd := DllCall("GetForegroundWindow", "ptr")

    ; Geometry reads stay interruptible. Never mutate membership while rendering.
    live_windows := GetCascadeWindowsForOverlay()
    live_targets := Map()
    visible_windows := []
    visible_bounds := Map()
    highest_hwnd_by_monitor := Map()
    highest_y_by_monitor := Map()

    for hwnd in live_windows {
        live_targets[hwnd] := true

        if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
            continue

        try {
            if WinGetMinMax("ahk_id " hwnd) != 0
                continue
        }
        catch {
            continue
        }

        if !GetVisibleWindowBounds(
            hwnd,
            &window_x,
            &window_y,
            &window_width,
            &window_height
        ) {
            continue
        }

        monitor_index := GetMonitorForWindow(hwnd)
        if !monitor_index
            continue

        visible_windows.Push(hwnd)
        visible_bounds[hwnd] := [
            window_x,
            window_y,
            window_width,
            window_height,
            monitor_index
        ]

        if !highest_hwnd_by_monitor.Has(monitor_index)
            || window_y < highest_y_by_monitor[monitor_index]
        {
            highest_hwnd_by_monitor[monitor_index] := hwnd
            highest_y_by_monitor[monitor_index] := window_y
        }
    }

    ; Stack keys already include the monitor; equal slot numbers never merge.
    slot_stacks := BuildCascadeSlotStacks(visible_windows, cascade_slot_tolerance)
    z_ranks := GetCascadeWindowZRanks()

    ; Keep the hide/show handoff together, but do not lock the geometry queries.
    previous_critical := A_IsCritical
    Critical "On"
    try {
        ; A newer refresh or tab press may have changed the stack during queries.
        if generation != update_generation
            return
        if active_hwnd != DllCall("GetForegroundWindow", "ptr")
            || click_generation != focus_tab_click_generation
        {
            QueueFocusCornerUpdate()
            return
        }

        selected_targets := Map()
        active_slot_targets := Map()

        for stack_info in slot_stacks {
            ordered_windows := SortCascadeWindowsByZOrder(
                stack_info["windows"],
                z_ranks
            )
            selected_hwnd := SelectFocusCornerSlotTarget(
                ordered_windows,
                active_hwnd
            )
            contains_active := false
            full_height := false

            for hwnd in ordered_windows {
                if hwnd = active_hwnd
                    contains_active := true

                monitor_index := visible_bounds[hwnd][5]
                if highest_hwnd_by_monitor[monitor_index] = hwnd
                    full_height := true
            }

            if contains_active {
                for hwnd in ordered_windows
                    active_slot_targets[hwnd] := true
            }

            ; Full height belongs to the highest slot, not one particular layer.
            if selected_hwnd
                selected_targets[selected_hwnd] := full_height
        }

        stale_targets := []

        ; Hide every old representative before showing any replacement.
        ; Cached per-window GUIs stay reusable without stacking visible pixels.
        for hwnd, overlay in focus_corner_overlays {
            if !live_targets.Has(hwnd)
                stale_targets.Push(hwnd)
            else if !selected_targets.Has(hwnd)
                HideFocusCornerOverlay(hwnd)
        }

        for hwnd in stale_targets
            DestroyFocusCornerOverlay(hwnd)

        for hwnd, full_height in selected_targets {
            if hwnd = active_hwnd || !WinExist("ahk_id " hwnd)
                continue

            bounds := visible_bounds[hwnd]
            try {
                ShowFocusCornerOverlay(
                    hwnd,
                    bounds[1],
                    bounds[2],
                    bounds[3],
                    bounds[4],
                    full_height,
                    active_slot_targets.Has(hwnd)
                )
            }
            catch Error as err {
                ; Closing targets must not interrupt updates for the other slots.
                DebugError("ShowFocusCornerOverlay", err)
            }
        }
    }
    finally {
        Critical(previous_critical)
    }

    ; External applications can still change foreground focus during rendering.
    if active_hwnd != DllCall("GetForegroundWindow", "ptr")
        QueueFocusCornerUpdate()

    DebugFocusCornerAppearance(active_hwnd, active_slot_targets)
}

GetCascadeWindowsForOverlay()
{
    global cascade_history

    windows := []
    seen := Map()

    for monitor_index, history in cascade_history {
        for hwnd in history {
            if seen.Has(hwnd)
                continue

            if !WinExist("ahk_id " hwnd)
                continue

            if GetMonitorForWindow(hwnd) != monitor_index
                continue

            ; Do not remove a window from history just because a visual refresh
            ; catches it during a transient geometry change.
            if !IsWindowInCascadeLayout(hwnd)
                continue

            seen[hwnd] := true
            windows.Push(hwnd)
        }
    }

    return windows
}

SelectFocusCornerSlotTarget(ordered_windows, active_hwnd)
{
    ; Inactive slot: exposed window. Active slot: first layer below foreground.
    ; A focused single-window slot has no remaining tab to show.
    for hwnd in ordered_windows {
        if hwnd != active_hwnd
            return hwnd
    }

    return 0
}


; =============================================================================
; overlay placement and lifetime
; =============================================================================

ShowFocusCornerOverlay(
    hwnd,
    window_x,
    window_y,
    window_width,
    window_height,
    full_height := false,
    active_slot := false
)
{
    global focus_corner_overlays
    global focus_corner_size
    global focus_corner_thickness
    global focus_corner_overlap
    global focus_corner_inactive_slot_color, focus_corner_active_slot_color
    global focus_corner_inactive_slot_alpha, focus_corner_active_slot_alpha
    global focus_corner_visible

    marker_color := (
        active_slot
        ? focus_corner_active_slot_color
        : focus_corner_inactive_slot_color
    )
    marker_alpha := (
        active_slot
        ? focus_corner_active_slot_alpha
        : focus_corner_inactive_slot_alpha
    )

    if !focus_corner_overlays.Has(hwnd)
        CreateFocusCornerOverlay(hwnd, marker_color, marker_alpha)

    overlay := focus_corner_overlays[hwnd]
    appearance_changed := (
        overlay.color != marker_color
        || overlay.alpha != marker_alpha
    )

    if overlay.color != marker_color {
        overlay.gui.BackColor := marker_color
        overlay.color := marker_color
    }

    overlay.alpha := marker_alpha

    if (
        overlay.shown
        && overlay.window_x = window_x
        && overlay.window_y = window_y
        && overlay.window_width = window_width
        && overlay.window_height = window_height
        && overlay.full_height = full_height
    ) {
        ; Reapply the selected appearance even when geometry did not change.
        try WinSetTransparent(
            focus_corner_visible ? marker_alpha : 1,
            overlay.gui.Hwnd
        )
        if appearance_changed
            WinRedraw(overlay.gui.Hwnd)

        PlaceFocusCornerAboveTarget(hwnd, overlay)
        return
    }

    thickness := focus_corner_thickness
    overlap := focus_corner_overlap
    outside := thickness - overlap

    marker_x := window_x - outside

    if full_height {
        marker_y := window_y
        marker_height := window_height
    } else {
        marker_y :=
            window_y
            + window_height
            - focus_corner_size

        marker_height := focus_corner_size
    }

    overlay.gui.Show(
        "NA"
        . " x" marker_x
        . " y" marker_y
        . " w" thickness
        . " h" marker_height
    )

    WinSetTransparent(
        focus_corner_visible ? marker_alpha : 1,
        overlay.gui.Hwnd
    )

    ; A reused hidden GUI can have a new BackColor but an old painted surface.
    ; Repaint after showing it; changing alpha alone does not repaint its pixels.
    WinRedraw(overlay.gui.Hwnd)
    PlaceFocusCornerAboveTarget(hwnd, overlay)

    overlay.window_x := window_x
    overlay.window_y := window_y
    overlay.window_width := window_width
    overlay.window_height := window_height
    overlay.full_height := full_height
    overlay.shown := true
}

PlaceFocusCornerAboveTarget(hwnd, overlay)
{
    static SWP_NOSIZE := 0x0001
    static SWP_NOMOVE := 0x0002
    static SWP_NOACTIVATE := 0x0010

    if !WinExist("ahk_id " hwnd)
        return

    flags :=
        SWP_NOSIZE
        | SWP_NOMOVE
        | SWP_NOACTIVATE

    DllCall(
        "SetWindowPos",
        "ptr", overlay.gui.Hwnd,
        "ptr", hwnd,
        "int", 0,
        "int", 0,
        "int", 0,
        "int", 0,
        "uint", flags,
        "int"
    )
}

HideFocusCornerOverlay(hwnd)
{
    global focus_corner_overlays

    if !focus_corner_overlays.Has(hwnd)
        return

    overlay := focus_corner_overlays[hwnd]

    if !overlay.shown
        return

    try overlay.gui.Hide()

    overlay.shown := false
}

CreateFocusCornerOverlay(hwnd, marker_color, marker_alpha)
{
    global focus_corner_overlays
    global focus_corner_targets

    marker_gui := Gui(
        "-Caption"
        . " +ToolWindow"
        . " +E0x08000000",
        "Window Cascade Focus Marker"
    )

    marker_gui.BackColor := marker_color

    focus_corner_targets[marker_gui.Hwnd] := hwnd

    focus_corner_overlays[hwnd] := {
        gui: marker_gui,
        color: marker_color,
        alpha: marker_alpha,
        shown: false,
        window_x: 0,
        window_y: 0,
        window_width: 0,
        window_height: 0,
        full_height: false
    }
}

DestroyFocusCornerOverlay(hwnd)
{
    global focus_corner_overlays
    global focus_corner_targets

    if !focus_corner_overlays.Has(hwnd)
        return

    overlay := focus_corner_overlays[hwnd]
    overlay_hwnd := overlay.gui.Hwnd

    try overlay.gui.Destroy()

    focus_corner_overlays.Delete(hwnd)

    if focus_corner_targets.Has(overlay_hwnd)
        focus_corner_targets.Delete(overlay_hwnd)
}


; =============================================================================
; visibility
; =============================================================================

ToggleFocusCornerVisibility(*)
{
    global focus_corner_visible
    global focus_corner_overlays

    focus_corner_visible := !focus_corner_visible

    for hwnd, overlay in focus_corner_overlays {
        transparency := focus_corner_visible ? overlay.alpha : 1

        try WinSetTransparent(
            transparency,
            overlay.gui.Hwnd
        )
    }

    UpdateTrayMenu()
}
