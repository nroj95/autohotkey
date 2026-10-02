; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; side-layout cycle
; =============================================================================

CycleWindowSnap(side)
{
    global last_minimized_hwnd
    global borderless_windows

    ; Special states start a fresh side cycle even if restoring them happens
    ; to put the window on coordinates that match an existing layout.
    fresh_cycle_entry := !!last_minimized_hwnd

    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        if borderless_windows.Has(hwnd)
            fresh_cycle_entry := true
        else if WinGetMinMax(window) = 1
            fresh_cycle_entry := true

        PrepareWindowForPlacement(hwnd)

        GetWindowMonitorWorkArea(
            hwnd,
            &left,
            &top,
            &right,
            &bottom
        )

        work_width := right - left
        work_height := bottom - top

        half_width := Floor(work_width / 2)
        third_width := Floor(work_width / 3)
        two_thirds_width := Floor(work_width * 2 / 3)

        center_third_x :=
            left + Floor((work_width - third_width) / 2)

        center_third := [
            center_third_x,
            top,
            third_width,
            work_height
        ]

        left_layouts := [
            [left, top, half_width, work_height],
            [left, top, third_width, work_height],
            center_third,
            [left, top, two_thirds_width, work_height]
        ]

        right_layouts := [
            [right - half_width, top, half_width, work_height],
            [right - third_width, top, third_width, work_height],
            center_third,
            [
                right - two_thirds_width,
                top,
                two_thirds_width,
                work_height
            ]
        ]

        if side = "left" {
            layouts := left_layouts
            opposite_layouts := right_layouts
        } else {
            layouts := right_layouts
            opposite_layouts := left_layouts
        }

        if !fresh_cycle_entry {
            ; If the window already belongs to this arrow's cycle, advance one
            ; step. The center third acts as the junction before the two-thirds
            ; layout on either side.
            matched_index := FindMatchingLayoutIndex(
                window,
                layouts
            )

            if matched_index {
                next_index := (
                    matched_index = layouts.Length
                    ? 1
                    : matched_index + 1
                )

                target := layouts[next_index]
            } else {
                ; Pressing the opposite arrow walks backward through the side
                ; the window currently occupies instead of jumping across.
                opposite_index := FindMatchingLayoutIndex(
                    window,
                    opposite_layouts
                )

                if opposite_index {
                    previous_index := (
                        opposite_index = 1
                        ? opposite_layouts.Length
                        : opposite_index - 1
                    )

                    target := opposite_layouts[previous_index]
                } else {
                    fresh_cycle_entry := true
                }
            }
        }

        if fresh_cycle_entry {
            ; Every fresh side-cycle entry starts at two-thirds.
            target := layouts[4]
        }

        WinMove(
            target[1],
            target[2],
            target[3],
            target[4],
            window
        )
    }
}

FindMatchingLayoutIndex(window, layouts, tolerance := 8)
{
    WinGetPos(
        &x,
        &y,
        &width,
        &height,
        window
    )

    for layout_index, layout in layouts {
        if Abs(x - layout[1]) > tolerance
            continue

        if Abs(y - layout[2]) > tolerance
            continue

        if Abs(width - layout[3]) > tolerance
            continue

        if Abs(height - layout[4]) > tolerance
            continue

        return layout_index
    }

    return 0
}

; =============================================================================
; quarter placement
; =============================================================================

PlaceWindowQuarter(position)
{
    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        PrepareWindowForPlacement(hwnd)

        third_layout := GetQuarterLayout(
            hwnd,
            position,
            "third"
        )

        half_layout := GetQuarterLayout(
            hwnd,
            position,
            "half"
        )

        ; Arbitrary positions enter at the smaller third-width tile.
        ; Repeating the same shortcut toggles between third and half width.
        if WindowMatchesLayout(window, third_layout)
            target := half_layout
        else
            target := third_layout

        WinMove(
            target[1],
            target[2],
            target[3],
            target[4],
            window
        )
    }
}

ToggleCenterQuarter()
{
    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        PrepareWindowForPlacement(hwnd)

        top_layout := GetQuarterLayout(hwnd, "top-center", "third")
        bottom_layout := GetQuarterLayout(hwnd, "bottom-center", "third")

        if WindowMatchesLayout(window, top_layout)
            target := bottom_layout
        else
            target := top_layout

        WinMove(
            target[1],
            target[2],
            target[3],
            target[4],
            window
        )
    }
}

GetQuarterLayout(hwnd, position, width_mode := "half")
{
    GetWindowMonitorWorkArea(
        hwnd,
        &left,
        &top,
        &right,
        &bottom
    )

    work_width := right - left
    work_height := bottom - top

    tile_width := (
        width_mode = "third"
        ? Floor(work_width / 3)
        : Floor(work_width / 2)
    )

    half_height := Floor(work_height / 2)

    switch position {
        case "top-left", "bottom-left":
            target_x := left
        case "top-center", "bottom-center":
            target_x := left + Floor((work_width - tile_width) / 2)
        case "top-right", "bottom-right":
            target_x := right - tile_width
        default:
            throw Error("Unknown quarter position: " position)
    }

    is_top := InStr(position, "top-") = 1
    target_y := is_top ? top : top + half_height

    ; The bottom tile receives any leftover pixel from an odd work-area height.
    tile_height := is_top ? half_height : bottom - target_y

    return [target_x, target_y, tile_width, tile_height]
}

WindowMatchesLayout(window, layout, tolerance := 8)
{
    return FindMatchingLayoutIndex(window, [layout], tolerance) = 1
}

; =============================================================================
; prepare a window for placement
; =============================================================================

PrepareWindowForPlacement(hwnd)
{
    global borderless_windows

    window := "ahk_id " hwnd

    if borderless_windows.Has(hwnd) {
        RestoreBorderlessWindow(hwnd, false, true)
        return
    }

    if WinGetMinMax(window) != 0
        WinRestore(window)
}
