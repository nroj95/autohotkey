; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; desktop monitor selection
; =============================================================================

CaptureDesktopMonitorHint()
{
    global desktop_monitor_hint, desktop_monitor_hint_tick

    MouseGetPos(&mouse_x, &mouse_y, &hover_hwnd)

    if !hover_hwnd
        return

    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hover_hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if !IsDesktopSurfaceWindow(hover_hwnd)
        && !IsDesktopSurfaceWindow(root_hwnd)
        return

    monitor_index := GetMonitorForPoint(mouse_x, mouse_y)

    if !monitor_index
        return

    desktop_monitor_hint := monitor_index
    desktop_monitor_hint_tick := A_TickCount

}


; =============================================================================
; window discovery and placement queue
; =============================================================================

SeedStartupWindows()
{
    global startup_windows, known_windows

    startup_windows := Map()
    known_windows := Map()

    for hwnd in WinGetList() {
        startup_windows[hwnd] := true
        known_windows[hwnd] := true
    }

}

QueueWindowPlacement(hwnd, source_hwnd)
{
    global pending_windows, known_windows, placement_delay_ms

    ; Once any discovery path adopts an HWND, the polling fallback no longer
    ; needs to rediscover the same window.
    known_windows[hwnd] := true


    if pending_windows.Has(hwnd)
        return
    try pid := WinGetPID(hwnd)
    catch
        return
    request := {pid: pid, focus: CaptureNewWindowFocusContext(hwnd)}
    pending_windows[hwnd] := request

    ; Snapshot once here. Readiness retries and settling reuse this monitor
    ; instead of sampling a later mouse position.
    MouseGetPos(&queue_mouse_x, &queue_mouse_y)
    queued_monitor := GetMonitorForPoint(
        queue_mouse_x,
        queue_mouse_y
    )

    DebugLog(
        "Queue placement."
        . " | target=" DebugDescribeWindow(hwnd)
        . " | source=" DebugDescribeWindow(source_hwnd)
        . " | queued-monitor=" queued_monitor
        . " | mouse=(" queue_mouse_x "," queue_mouse_y ")"
    )


    SetTimer(
        PlaceNewWindow.Bind(
            hwnd,
            source_hwnd,
            queued_monitor,
            0,
            false,
            request
        ),
        -placement_delay_ms
    )
}

WatchForMissedWindows()
{
    global known_windows
    global debug_enabled, debug_verbose_enabled
    global pending_windows, handled_windows
    global current_foreground_hwnd, previous_foreground_hwnd
    global placement_enabled

    for hwnd in WinGetList() {
        if known_windows.Has(hwnd)
            continue

        ; Record the HWND immediately. Rejected helper windows should not be
        ; reconsidered every polling cycle.
        known_windows[hwnd] := true

        if debug_enabled && debug_verbose_enabled {
            DebugLog(
                "Poll discovered HWND."
                . " | " DebugDescribeWindow(hwnd)
            )
        }

        if !placement_enabled
            continue

        if pending_windows.Has(hwnd) || handled_windows.Has(hwnd)
            continue

        if !IsPlausibleTopLevelWindow(hwnd) {
            if debug_enabled && debug_verbose_enabled {
                DebugLog(
                    "Poll rejected by top-level prefilter."
                    . " | " DebugDescribeWindow(hwnd)
                )
            }
            continue
        }

        source_hwnd := current_foreground_hwnd

        if source_hwnd = hwnd
            source_hwnd := previous_foreground_hwnd


        QueueWindowPlacement(hwnd, source_hwnd)
    }
    ReconcileCascadeRuntimeState()
}

TryQueueForegroundFallback(hwnd)
{
    global startup_windows
    global pending_windows, handled_windows
    global previous_foreground_hwnd
    global placement_enabled

    if !hwnd
        return

    ; Never adopt a window merely because it was already open when this script
    ; started.
    if startup_windows.Has(hwnd)
        return

    if !placement_enabled
        return

    if pending_windows.Has(hwnd) || handled_windows.Has(hwnd)
        return

    if !IsPlausibleTopLevelWindow(hwnd)
        return

    source_hwnd := previous_foreground_hwnd

    if source_hwnd = hwnd
        source_hwnd := 0


    QueueWindowPlacement(hwnd, source_hwnd)
}


; =============================================================================
; Windows event hooks
; =============================================================================

StartWindowHooks()
{
    global win_event_callback
    global foreground_hook, window_show_hook, window_destroy_hook
    global window_move_size_hook, window_restore_hook

    EVENT_SYSTEM_FOREGROUND := 0x0003
    EVENT_OBJECT_DESTROY := 0x8001
    EVENT_OBJECT_SHOW := 0x8002
    EVENT_SYSTEM_MOVESIZESTART := 0x000A
    EVENT_SYSTEM_MOVESIZEEND := 0x000B
    EVENT_SYSTEM_MINIMIZESTART := 0x0016
    EVENT_SYSTEM_MINIMIZEEND := 0x0017

    WINEVENT_OUTOFCONTEXT := 0x0000
    WINEVENT_SKIPOWNPROCESS := 0x0002
    flags := WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS

    win_event_callback := CallbackCreate(HandleWinEvent)

    foreground_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_SYSTEM_FOREGROUND,
        "uint", EVENT_SYSTEM_FOREGROUND,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_show_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_OBJECT_SHOW,
        "uint", EVENT_OBJECT_SHOW,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_destroy_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_OBJECT_DESTROY,
        "uint", EVENT_OBJECT_DESTROY,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_move_size_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_SYSTEM_MOVESIZESTART,
        "uint", EVENT_SYSTEM_MOVESIZEEND,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )

    ; MINIMIZEEND announces a restore, not settled geometry. The shared
    ; completion watcher confirms readiness before requesting compaction.
    window_restore_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_SYSTEM_MINIMIZESTART,
        "uint", EVENT_SYSTEM_MINIMIZEEND,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )

    if (
        !foreground_hook
        || !window_show_hook
        || !window_destroy_hook
        || !window_move_size_hook
        || !window_restore_hook
    ) {

        MsgBox(
            "Could not install all Windows event hooks.`n`n"
            . "Window Cascade may not track windows correctly.",
            "Window Cascade",
            "Iconx"
        )
    }
}

StopWindowHooks()
{
    global win_event_callback
    global foreground_hook, window_show_hook, window_destroy_hook
    global window_move_size_hook, window_restore_hook

    SetTimer(WatchForMissedWindows, 0)
    SetTimer(UpdateFocusCornerOverlays, 0)
    SetTimer(RunQueuedFocusCornerUpdate, 0)
    SetTimer(WatchCascadeWindowDrag, 0)
    SetTimer(WatchCascadeWindowRestores, 0)
    SetTimer(FlushCascadeCompactions, 0)
    CancelNewWindowFocus()


    if foreground_hook {
        DllCall("UnhookWinEvent", "ptr", foreground_hook)
        foreground_hook := 0
    }

    if window_show_hook {
        DllCall("UnhookWinEvent", "ptr", window_show_hook)
        window_show_hook := 0
    }

    if window_destroy_hook {
        DllCall("UnhookWinEvent", "ptr", window_destroy_hook)
        window_destroy_hook := 0
    }

    if window_move_size_hook {
        DllCall("UnhookWinEvent", "ptr", window_move_size_hook)
        window_move_size_hook := 0
    }

    if window_restore_hook {
        DllCall("UnhookWinEvent", "ptr", window_restore_hook)
        window_restore_hook := 0
    }

    if win_event_callback {
        CallbackFree(win_event_callback)
        win_event_callback := 0
    }
}

HandleWinEvent(
    hook_handle,
    event,
    hwnd,
    object_id,
    child_id,
    event_thread,
    event_time
)
{
    global current_foreground_hwnd, previous_foreground_hwnd
    global pending_windows, handled_windows
    global startup_windows
    global placement_enabled
    global desktop_monitor_hint, desktop_monitor_hint_tick
    global debug_enabled, debug_verbose_enabled

    try {
        EVENT_SYSTEM_FOREGROUND := 0x0003
        EVENT_OBJECT_DESTROY := 0x8001
        EVENT_OBJECT_SHOW := 0x8002
        EVENT_SYSTEM_MOVESIZESTART := 0x000A
        EVENT_SYSTEM_MOVESIZEEND := 0x000B
        EVENT_SYSTEM_MINIMIZESTART := 0x0016
        EVENT_SYSTEM_MINIMIZEEND := 0x0017
        OBJID_WINDOW := 0
        CHILDID_SELF := 0

        if event = EVENT_SYSTEM_FOREGROUND {
            ObserveNewWindowForeground(hwnd)
            if hwnd && hwnd != current_foreground_hwnd {
                CancelPendingAdoptionUndo()

                previous_foreground_hwnd := current_foreground_hwnd
                current_foreground_hwnd := hwnd

                DebugLog(
                    "Foreground changed."
                    . " | current=" DebugDescribeWindow(hwnd)
                    . " | previous="
                    . DebugDescribeWindow(previous_foreground_hwnd)
                )

                if IsDesktopSurfaceWindow(hwnd) {
                    MouseGetPos(&mouse_x, &mouse_y)
                    monitor_index := GetMonitorForPoint(mouse_x, mouse_y)

                    if monitor_index {
                        desktop_monitor_hint := monitor_index
                        desktop_monitor_hint_tick := A_TickCount

                    }
                }
            }

            QueueFocusCornerUpdate()
            TryQueueForegroundFallback(hwnd)
            return
        }

        if object_id != OBJID_WINDOW || child_id != CHILDID_SELF || !hwnd
            return


        if event = EVENT_OBJECT_DESTROY {
            was_managed := !!GetManagedCascadeMonitor(hwnd)

            ; Filter logging, not cleanup. The first event clears tracking, so
            ; repeated/unrelated destroys are quiet unless verbose logging is on.
            if (
                debug_enabled
                && (debug_verbose_enabled || was_managed
                    || pending_windows.Has(hwnd) || handled_windows.Has(hwnd))
            ) {
                DebugLog(
                    "Destroy event."
                    . " | " DebugDescribeWindow(hwnd)
                )
            }

            ForgetWindow(hwnd)

            if was_managed
                QueueFocusCornerUpdate()

            return
        }


        if event = EVENT_SYSTEM_MINIMIZESTART {
            if GetManagedCascadeMonitor(hwnd) {
                ObserveCascadeMinimizedWindow(hwnd)
                CancelPlacementStabilization(hwnd)
            }
            RemoveWindowFromCascadeRestore(hwnd)
            return
        }

        if event = EVENT_SYSTEM_MINIMIZEEND {
            CancelPlacementStabilization(hwnd)
            TrackCascadeWindowRestores([hwnd])
            return
        }

        if event = EVENT_SYSTEM_MOVESIZESTART {
            BeginCascadeWindowDrag(hwnd, event_time)
            return
        }

        if event = EVENT_SYSTEM_MOVESIZEEND {
            EndCascadeWindowDrag(hwnd)
            return
        }


        if event != EVENT_OBJECT_SHOW
            return

        if GetManagedCascadeMonitor(hwnd)
            QueueFocusCornerUpdate()

        if debug_enabled && debug_verbose_enabled {
            DebugLog(
                "Show event."
                . " | pending=" pending_windows.Has(hwnd)
                . " | handled=" handled_windows.Has(hwnd)
                . " | " DebugDescribeWindow(hwnd)
            )
        }

        ; EVENT_OBJECT_SHOW also fires when some existing minimized windows are
        ; restored. Only windows absent from the startup snapshot are new.
        if startup_windows.Has(hwnd) {
            if debug_enabled && debug_verbose_enabled {
                DebugLog(
                    "Show event skipped: window existed at script startup."
                    . " | " DebugDescribeWindow(hwnd)
                )
            }
            return
        }

        ; Cheap filtering here prevents Explorer controls, ribbon pieces,
        ; tooltips, and other child/helper windows from ever reaching the timer.
        if !IsPlausibleTopLevelWindow(hwnd)
            return


        if !placement_enabled {
            return
        }

        if pending_windows.Has(hwnd) {
            return
        }

        if handled_windows.Has(hwnd) {
            return
        }

        source_hwnd := current_foreground_hwnd

        ; If focus already moved to the new window, use the prior foreground window.
        if source_hwnd = hwnd
            source_hwnd := previous_foreground_hwnd

        DebugLog(
            "Show event accepted."
            . " | target=" DebugDescribeWindow(hwnd)
            . " | source=" DebugDescribeWindow(source_hwnd)
        )

        QueueWindowPlacement(hwnd, source_hwnd)
    }
    catch Error as err {
        DebugError("HandleWinEvent", err)
    }
}


; =============================================================================
; destroyed window cleanup
; =============================================================================

ForgetWindow(hwnd)
{
    global pending_windows, handled_windows, placement_reservations
    global placement_stabilization_generations
    global pending_adoption_undo
    global cascade_history
    global startup_windows, known_windows
    global current_foreground_hwnd, previous_foreground_hwnd

    ; Do not wait for the next visual sweep: a destroyed target must never leave
    ; its script-owned focus GUI behind.
    DestroyFocusCornerOverlay(hwnd)

    affected_monitor := GetManagedCascadeMonitor(hwnd)

    if IsCascadeWindowBeingDragged(hwnd)
        StopCascadeWindowDrag()

    if IsPendingAdoptionUndoFor(hwnd)
        pending_adoption_undo := 0

    if placement_stabilization_generations.Has(hwnd)
        placement_stabilization_generations.Delete(hwnd)

    if startup_windows.Has(hwnd)
        startup_windows.Delete(hwnd)

    if known_windows.Has(hwnd)
        known_windows.Delete(hwnd)

    if pending_windows.Has(hwnd) {
        pending_windows.Delete(hwnd)
    }

    if handled_windows.Has(hwnd) {
        handled_windows.Delete(hwnd)
    }

    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    if current_foreground_hwnd = hwnd
        current_foreground_hwnd := 0

    if previous_foreground_hwnd = hwnd
        previous_foreground_hwnd := 0

    RemoveWindowFromMinimizeState(hwnd)
    NormalizeAllCascadesMinimizedState()

    RemoveCascadeWindowFromHistory(hwnd)
    ForgetCascadeMinimizedObservation(hwnd)

    RemoveWindowFromCascadeCloseBatch(hwnd)

    if affected_monitor
        QueueCascadeCompaction(affected_monitor)
}
