; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; managed window history
; =============================================================================

GetManagedCascadeMonitor(hwnd)
{
    global cascade_history

    for monitor_index, history in cascade_history {
        for managed_hwnd in history {
            if managed_hwnd = hwnd
                return monitor_index
        }
    }

    return 0
}

RecordCascadeWindow(monitor_index, hwnd)
{
    global cascade_history

    if !cascade_history.Has(monitor_index)
        cascade_history[monitor_index] := []

    cascade_history[monitor_index].Push(hwnd)

    QueueFocusCornerUpdate()
}

RemoveCascadeWindowFromHistory(hwnd)
{
    global cascade_history

    for monitor_index, history in cascade_history {
        index := history.Length

        while index >= 1 {
            if history[index] = hwnd
                history.RemoveAt(index)

            index -= 1
        }
    }
}

GetLiveCascadeHistory(monitor_index)
{
    global cascade_history

    live_history := []

    if !cascade_history.Has(monitor_index)
        return live_history

    previous_count := cascade_history[monitor_index].Length

    for hwnd in cascade_history[monitor_index] {
        if !WinExist("ahk_id " hwnd)
            continue

        ; A minimized window has no useful cascade geometry. Keep its recorded
        ; membership so restoring it does not silently remove it from history.
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1 {
                live_history.Push(hwnd)
                continue
            }
        }
        catch {
            continue
        }

        if GetMonitorForWindow(hwnd) != monitor_index
            continue

        if !IsWindowInCascadeLayout(hwnd)
            continue

        live_history.Push(hwnd)
    }

    cascade_history[monitor_index] := live_history

    if live_history.Length < previous_count
        QueueCascadeCompaction(monitor_index)

    return live_history
}

IsWindowInCascadeLayout(hwnd)
{
    global cascade_release_tolerance

    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    stacks := BuildCascadeSlotStacks(
        [hwnd],
        cascade_release_tolerance
    )

    return stacks.Length > 0
}


; =============================================================================
; slots, stacks, and exposed layers
; =============================================================================

GetCascadeSlotStacksForMonitor(monitor_index)
{
    global cascade_slot_tolerance

    windows := GetLiveCascadeHistory(monitor_index)

    if windows.Length = 0
        return []

    return BuildCascadeSlotStacks(
        windows,
        cascade_slot_tolerance
    )
}

GetCurrentCascadeLayerWindows(monitor_index)
{
    stacks := GetCascadeSlotStacksForMonitor(monitor_index)

    if stacks.Length = 0
        return []

    z_ranks := GetCascadeWindowZRanks()
    layer_windows := []

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        if ordered_stack.Length
            layer_windows.Push(ordered_stack[1])
    }

    return GetSpatialCascadeOrder(layer_windows)
}

BuildCascadeSlotStacks(windows, tolerance)
{
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    stacks := []
    stacks_by_slot := Map()

    for hwnd in windows {
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue

            monitor_index := GetMonitorForWindow(hwnd)

            if !monitor_index
                continue

            MonitorGetWorkArea(
                monitor_index,
                &work_left,
                &work_top,
                &work_right,
                &work_bottom
            )

            work_width := work_right - work_left
            work_height := work_bottom - work_top

            canonical_width := Floor(
                work_width * window_width_ratio
            )

            canonical_height := Floor(
                work_height * window_height_ratio
            )

            canonical_width := Max(
                minimum_width,
                canonical_width
            )

            canonical_height := Max(
                minimum_height,
                canonical_height
            )

            canonical_width := Min(
                canonical_width,
                work_width - edge_margin * 2
            )

            canonical_height := Min(
                canonical_height,
                work_height - edge_margin * 2
            )

            slots := BuildCascadeSlots(
                work_left,
                work_top,
                work_right,
                work_bottom,
                canonical_width,
                canonical_height
            )

            if !TryGetVisibleFrameRect(
                hwnd,
                &window_x,
                &window_y,
                &window_width,
                &window_height,
                &window_inset_left,
                &window_inset_top,
                &window_inset_right,
                &window_inset_bottom
            ) {
                continue
            }
        }
        catch {
            continue
        }

        best_slot_index := FindNearestCascadeSlot(
            window_x,
            window_y,
            slots,
            tolerance
        )

        ; A manually moved window that is no longer near a canonical slot does
        ; not belong to any stack.
        if !best_slot_index
            continue

        stack_key :=
            monitor_index
            . ":"
            . best_slot_index

        if stacks_by_slot.Has(stack_key) {
            stacks_by_slot[stack_key]["windows"].Push(hwnd)
            continue
        }

        stack_info := Map(
            "slot_index", best_slot_index,
            "windows", [hwnd]
        )

        stacks_by_slot[stack_key] := stack_info
        stacks.Push(stack_info)
    }

    return stacks
}


; =============================================================================
; canonical slot geometry and occupancy
; =============================================================================

CenterCoordinate(work_start, work_size, window_size)
{
    return work_start + Floor((work_size - window_size) / 2)
}

BuildCascadeSlots(
    work_left,
    work_top,
    work_right,
    work_bottom,
    window_width,
    window_height
)
{
    global cascade_x, cascade_y

    work_width := work_right - work_left
    work_height := work_bottom - work_top

    center_x := CenterCoordinate(
        work_left,
        work_width,
        window_width
    )

    center_y := CenterCoordinate(
        work_top,
        work_height,
        window_height
    )

    ; Slot 1 is the optimally centered position. Fill every position upward
    ; from center before continuing downward from center.
    slots := [[center_x, center_y]]

    ; Slots 2...N: left and upward from center until no more positions fit.
    step := 1

    Loop {
        x := center_x - cascade_x * step
        y := center_y - cascade_y * step

        if !CascadePositionFits(
            x,
            y,
            window_width,
            window_height,
            work_left,
            work_top,
            work_right,
            work_bottom
        ) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    ; Remaining slots: right and downward from center until the work area ends.
    step := 1

    Loop {
        x := center_x + cascade_x * step
        y := center_y + cascade_y * step

        if !CascadePositionFits(
            x,
            y,
            window_width,
            window_height,
            work_left,
            work_top,
            work_right,
            work_bottom
        ) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    return slots
}

CascadePositionFits(
    x,
    y,
    window_width,
    window_height,
    work_left,
    work_top,
    work_right,
    work_bottom
)
{
    global edge_margin

    return (
        x >= work_left + edge_margin
        && y >= work_top + edge_margin
        && x + window_width <= work_right - edge_margin
        && y + window_height <= work_bottom - edge_margin
    )
}

FindNearestCascadeSlot(
    window_x,
    window_y,
    slots,
    tolerance
)
{
    best_slot_index := 0
    best_distance := 0

    Loop slots.Length {
        slot_index := A_Index
        slot := slots[slot_index]

        delta_x := Abs(window_x - slot[1])
        delta_y := Abs(window_y - slot[2])

        if delta_x > tolerance || delta_y > tolerance
            continue

        distance := delta_x + delta_y

        if !best_slot_index
            || distance < best_distance
        {
            best_slot_index := slot_index
            best_distance := distance
        }
    }

    return best_slot_index
}

GetCascadeSlotCounts(
    monitor_index,
    slots,
    tolerance
)
{
    global cascade_history, placement_reservations

    counts := []

    Loop slots.Length
        counts.Push(0)

    if cascade_history.Has(monitor_index) {
        for hwnd in cascade_history[monitor_index] {
            if !WinExist("ahk_id " hwnd)
                continue

            ; A reserved window is counted at its intended slot below instead
            ; of at stale geometry from before its asynchronous move completes.
            if placement_reservations.Has(hwnd)
                continue

            if GetMonitorForWindow(hwnd) != monitor_index
                continue

            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    continue
            }
            catch {
                continue
            }

            if !TryGetVisibleFrameRect(
                hwnd,
                &window_x,
                &window_y,
                &window_width,
                &window_height,
                &window_inset_left,
                &window_inset_top,
                &window_inset_right,
                &window_inset_bottom
            ) {
                continue
            }

            best_slot_index := FindNearestCascadeSlot(
                window_x,
                window_y,
                slots,
                tolerance
            )

            if best_slot_index
                counts[best_slot_index] += 1
        }
    }

    ; Reservations also include windows that have selected a slot but have not
    ; yet been recorded in cascade history.
    for reserved_hwnd, reservation in placement_reservations {
        if reservation["monitor"] != monitor_index
            continue

        if !WinExist("ahk_id " reserved_hwnd)
            continue

        best_slot_index := FindNearestCascadeSlot(
            reservation["x"],
            reservation["y"],
            slots,
            tolerance
        )

        if best_slot_index
            counts[best_slot_index] += 1
    }

    return counts
}

GetNextCascadePosition(
    monitor_index,
    work_left,
    work_top,
    work_right,
    work_bottom,
    window_width,
    window_height
)
{
    global cascade_slot_tolerance

    slots := BuildCascadeSlots(
        work_left,
        work_top,
        work_right,
        work_bottom,
        window_width,
        window_height
    )

    slot_counts := GetCascadeSlotCounts(
        monitor_index,
        slots,
        cascade_slot_tolerance
    )

    selected_slot_index := 1
    selected_count := slot_counts[1]

    ; Smart placement sorts by stack depth first, then canonical slot number.
    ; This fills the shallowest slot and prefers the earliest slot on ties.
    Loop slots.Length {
        slot_index := A_Index
        count := slot_counts[slot_index]

        if count < selected_count {
            selected_slot_index := slot_index
            selected_count := count
        }
    }

    return slots[selected_slot_index]
}


; =============================================================================
; layout compaction
; =============================================================================

QueueCascadeCompaction(monitor_index)
{
    global cascade_compaction_pending

    if !monitor_index
        return

    cascade_compaction_pending[monitor_index] := true

    ; Batch closes/destruction into one final compaction.
    SetTimer FlushCascadeCompactions, -120
}

FlushCascadeCompactions()
{
    global cascade_compaction_pending

    monitors := []

    for monitor_index in cascade_compaction_pending
        monitors.Push(monitor_index)

    cascade_compaction_pending := Map()

    for monitor_index in monitors
        CompactCascadeLayout(monitor_index)
}

CompactCascadeLayout(monitor_index)
{
    global cascade_slot_tolerance
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    ; A fully hidden monitor has nothing visible to compact.
    if monitor_minimized_windows_by_monitor.Has(monitor_index)
        return

    windows := GetLiveCascadeHistory(monitor_index)

    ; Keep a script-hidden layer out of compaction while packing the layers
    ; that remain visible. Restoring the hidden layer compacts everything.
    if layer_minimized_windows_by_monitor.Has(monitor_index) {
        visible_windows := []

        for hwnd in windows {
            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    continue
            }
            catch {
                continue
            }

            visible_windows.Push(hwnd)
        }

        windows := visible_windows
    }

    if windows.Length = 0
        return

    stacks := BuildCascadeSlotStacks(
        windows,
        cascade_slot_tolerance
    )

    if stacks.Length = 0
        return

    MonitorGetWorkArea(
        monitor_index,
        &work_left,
        &work_top,
        &work_right,
        &work_bottom
    )

    work_width := work_right - work_left
    work_height := work_bottom - work_top

    window_width := Max(
        minimum_width,
        Floor(work_width * window_width_ratio)
    )

    window_height := Max(
        minimum_height,
        Floor(work_height * window_height_ratio)
    )

    window_width := Min(
        window_width,
        work_width - edge_margin * 2
    )

    window_height := Min(
        window_height,
        work_height - edge_margin * 2
    )

    slots := BuildCascadeSlots(
        work_left,
        work_top,
        work_right,
        work_bottom,
        window_width,
        window_height
    )

    if slots.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()
    stacks_by_slot := Map()
    maximum_depth := 0

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        stacks_by_slot[stack_info["slot_index"]] := ordered_stack
        maximum_depth := Max(maximum_depth, ordered_stack.Length)
    }

    ; Read the current cascade layer-first and slot-first. Repacking this order
    ; makes every earlier slot/layer dense without changing layer order.
    ordered_windows := []

    Loop maximum_depth {
        layer_index := A_Index

        Loop slots.Length {
            slot_index := A_Index

            if !stacks_by_slot.Has(slot_index)
                continue

            stack_windows := stacks_by_slot[slot_index]

            if layer_index <= stack_windows.Length
                ordered_windows.Push(stack_windows[layer_index])
        }
    }

    target_stacks := []

    Loop slots.Length
        target_stacks.Push([])

    for linear_index, hwnd in ordered_windows {
        target_slot_index := Mod(linear_index - 1, slots.Length) + 1
        target_slot := slots[target_slot_index]

        MoveCascadeWindowToSlot(
            hwnd,
            target_slot[1],
            target_slot[2]
        )

        target_stacks[target_slot_index].Push(hwnd)
    }

    ; Keep each target stack in the same top-to-bottom layer order.
    z_flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    for stack_windows in target_stacks {
        if stack_windows.Length < 2
            continue

        Loop stack_windows.Length - 1 {
            upper_hwnd := stack_windows[A_Index]
            lower_hwnd := stack_windows[A_Index + 1]

            try DllCall(
                "SetWindowPos",
                "ptr", lower_hwnd,
                "ptr", upper_hwnd,
                "int", 0,
                "int", 0,
                "int", 0,
                "int", 0,
                "uint", z_flags,
                "int"
            )
        }
    }

    QueueFocusCornerUpdate()
}


; =============================================================================
; stack Z-order
; =============================================================================

GetCascadeWindowZRanks()
{
    ranks := Map()

    ; WinGetList returns top-level windows in Z-order.
    for rank, hwnd in WinGetList()
        ranks[hwnd] := rank

    return ranks
}

SortCascadeWindowsByZOrder(windows, ranks)
{
    ordered_windows := []

    for hwnd in windows {
        rank := (
            ranks.Has(hwnd)
            ? ranks[hwnd]
            : 2147483647
        )

        insert_index := ordered_windows.Length + 1

        Loop ordered_windows.Length {
            existing_hwnd := ordered_windows[A_Index]

            existing_rank := (
                ranks.Has(existing_hwnd)
                ? ranks[existing_hwnd]
                : 2147483647
            )

            if rank < existing_rank {
                insert_index := A_Index
                break
            }
        }

        ordered_windows.InsertAt(insert_index, hwnd)
    }

    return ordered_windows
}
