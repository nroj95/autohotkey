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
    global focus_corner_overlays

    RefreshFocusCornerAccent()

    active_hwnd := DllCall(
        "GetForegroundWindow",
        "ptr"
    )

    ; The marker timer must never mutate cascade membership. A window can be
    ; temporarily between geometries while Explorer or placement settles.
    live_windows := GetCascadeWindowsForOverlay()
    live_targets := Map()
    visible_bounds := Map()

    highest_hwnd_by_monitor := Map()
    highest_y_by_monitor := Map()

    ; Cache geometry and identify the highest cascade window on each monitor.
    for hwnd in live_windows {
        live_targets[hwnd] := true

        if !DllCall(
            "IsWindowVisible",
            "ptr", hwnd,
            "int"
        ) {
            continue
        }

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

    for hwnd in live_windows {
        if (
            hwnd = active_hwnd
            || !visible_bounds.Has(hwnd)
        ) {
            HideFocusCornerOverlay(hwnd)
            continue
        }

        bounds := visible_bounds[hwnd]
        monitor_index := bounds[5]

        is_highest_on_monitor := (
            highest_hwnd_by_monitor.Has(monitor_index)
            && highest_hwnd_by_monitor[monitor_index] = hwnd
        )

        ShowFocusCornerOverlay(
            hwnd,
            bounds[1],
            bounds[2],
            bounds[3],
            bounds[4],
            is_highest_on_monitor
        )
    }

    stale_targets := []

    for hwnd, overlay in focus_corner_overlays {
        if !live_targets.Has(hwnd)
            stale_targets.Push(hwnd)
    }

    for hwnd in stale_targets
        DestroyFocusCornerOverlay(hwnd)
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


; =============================================================================
; overlay placement and lifetime
; =============================================================================

ShowFocusCornerOverlay(
    hwnd,
    window_x,
    window_y,
    window_width,
    window_height,
    full_height := false
)
{
    global focus_corner_overlays
    global focus_corner_size
    global focus_corner_thickness
    global focus_corner_overlap
    global focus_corner_visible, focus_corner_visible_alpha

    if !focus_corner_overlays.Has(hwnd)
        CreateFocusCornerOverlay(hwnd)

    overlay := focus_corner_overlays[hwnd]

    if (
        overlay.shown
        && overlay.window_x = window_x
        && overlay.window_y = window_y
        && overlay.window_width = window_width
        && overlay.window_height = window_height
        && overlay.full_height = full_height
    ) {
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
        focus_corner_visible ? focus_corner_visible_alpha : 1,
        "ahk_id " overlay.gui.Hwnd
    )

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

CreateFocusCornerOverlay(hwnd)
{
    global focus_corner_overlays
    global focus_corner_targets
    global focus_corner_accent_color

    marker_gui := Gui(
        "-Caption"
        . " +ToolWindow"
        . " +E0x08000000",
        "Window Cascade Focus Marker"
    )

    marker_gui.BackColor := focus_corner_accent_color

    focus_corner_targets[marker_gui.Hwnd] := hwnd

    focus_corner_overlays[hwnd] := {
        gui: marker_gui,
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
; clicks, visibility, and accent color
; =============================================================================

HandleFocusCornerClick(
    w_param,
    l_param,
    message,
    overlay_hwnd
)
{
    global focus_corner_targets

    if !focus_corner_targets.Has(overlay_hwnd)
        return

    target_hwnd := focus_corner_targets[overlay_hwnd]

    if !WinExist("ahk_id " target_hwnd) {
        DestroyFocusCornerOverlay(target_hwnd)
        return 0
    }

    HideFocusCornerOverlay(target_hwnd)

    try WinActivate("ahk_id " target_hwnd)

    return 0
}

ToggleFocusCornerVisibility(*)
{
    global focus_corner_visible, focus_corner_visible_alpha
    global focus_corner_overlays

    focus_corner_visible := !focus_corner_visible
    transparency := focus_corner_visible ? focus_corner_visible_alpha : 1

    for hwnd, overlay in focus_corner_overlays {
        try WinSetTransparent(
            transparency,
            "ahk_id " overlay.gui.Hwnd
        )
    }

    UpdateTrayMenu()
}

RefreshFocusCornerAccent()
{
    global focus_corner_overlays
    global focus_corner_accent_color
    global focus_corner_accent_check_tick
    global focus_corner_accent_check_ms

    if (
        focus_corner_accent_color != ""
        && A_TickCount - focus_corner_accent_check_tick
            < focus_corner_accent_check_ms
    ) {
        return
    }

    focus_corner_accent_check_tick := A_TickCount
    new_color := GetWindowsAccentHexColor()

    if new_color = focus_corner_accent_color
        return

    focus_corner_accent_color := new_color
    targets := []

    for hwnd, overlay in focus_corner_overlays
        targets.Push(hwnd)

    for hwnd in targets
        DestroyFocusCornerOverlay(hwnd)
}

GetWindowsAccentHexColor()
{
    colorization_color := 0
    opaque_blend := 0

    result := DllCall(
        "dwmapi\DwmGetColorizationColor",
        "uint*", &colorization_color,
        "int*", &opaque_blend,
        "int"
    )

    if result != 0
        return "0078D4"

    red := (colorization_color >> 16) & 0xFF
    green := (colorization_color >> 8) & 0xFF
    blue := colorization_color & 0xFF

    return Format(
        "{:02X}{:02X}{:02X}",
        red,
        green,
        blue
    )
}
