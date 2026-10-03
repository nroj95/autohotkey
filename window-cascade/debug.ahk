; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; debug logging
; =============================================================================

InitializeDebugLogging()
{
    global debug_enabled

    if !debug_enabled
        return

    reset_message := DllCall(
        "RegisterWindowMessage",
        "str", "WindowDebug.ResetLogs",
        "uint"
    )

    if reset_message {
        OnMessage(
            reset_message,
            HandleDebugResetLogsMessage
        )
    }

    OnError(LogUnhandledError)

    DebugLogSession("started")
}

HandleDebugResetLogsMessage(*)
{
    ResetDebugLog()
}

ResetDebugLog()
{
    global debug_enabled, debug_log_path

    if !debug_enabled
        return

    try {
        if FileExist(debug_log_path)
            FileDelete(debug_log_path)
    }
    catch Error as err {
        DebugLog(
            "Debug log reset failed."
            . " | message=" err.Message
        )
        return
    }

    DebugLogSession("reset")
}

DebugLogSession(reason)
{
    process_id := DllCall(
        "GetCurrentProcessId",
        "uint"
    )

    DebugLog(
        "Debug session " reason "."
        . " | pid=" process_id
        . " | ahk=" A_AhkVersion
        . ' | script="' A_ScriptFullPath '"'
    )
}

DebugLog(message)
{
    global debug_enabled, debug_log_path

    if !debug_enabled
        return

    timestamp := FormatTime(
        ,
        "yyyy-MM-dd HH:mm:ss"
    )

    try FileAppend(
        timestamp
        . " | tick=" A_TickCount
        . " | " message
        . "`n",
        debug_log_path,
        "UTF-8-RAW"
    )
}


; =============================================================================
; error reporting and window diagnostics
; =============================================================================

DebugError(context, err)
{
    DebugLog(
        "ERROR in " context
        . " | message=" err.Message
        . " | what=" err.What
        . " | file=" err.File
        . " | line=" err.Line
    )

    if err.Stack != ""
        DebugLog(
            "STACK | "
            . StrReplace(
                StrReplace(err.Stack, "`r", ""),
                "`n",
                " | "
            )
        )
}

LogUnhandledError(err, mode)
{
    DebugError(
        "Unhandled error, mode=" mode,
        err
    )

    return 0
}

DebugDescribeWindow(hwnd)
{
    global debug_enabled, debug_verbose_enabled
    if !debug_enabled || !debug_verbose_enabled
        return "hwnd=" hwnd

    if !hwnd
        return "hwnd=0"

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return "hwnd=" hwnd " [invalid]"

    title := ""
    class_name := ""
    process_name := ""
    min_max := "?"
    x := "?"
    y := "?"
    width := "?"
    height := "?"

    try title := WinGetTitle("ahk_id " hwnd)
    try class_name := WinGetClass("ahk_id " hwnd)
    try process_name := WinGetProcessName("ahk_id " hwnd)
    try min_max := WinGetMinMax("ahk_id " hwnd)

    try {
        WinGetPos(
            &window_x,
            &window_y,
            &window_width,
            &window_height,
            "ahk_id " hwnd
        )

        x := window_x
        y := window_y
        width := window_width
        height := window_height
    }

    title := StrReplace(
        StrReplace(title, "`r", " "),
        "`n",
        " "
    )

    visible := DllCall(
        "IsWindowVisible",
        "ptr", hwnd,
        "int"
    )

    iconic := DllCall(
        "IsIconic",
        "ptr", hwnd,
        "int"
    )

    cloaked := false
    try cloaked := IsWindowCloaked(hwnd)

    return (
        "hwnd=" hwnd
        . ' exe="' process_name '"'
        . ' class="' class_name '"'
        . ' title="' title '"'
        . " minmax=" min_max
        . " visible=" visible
        . " iconic=" iconic
        . " cloaked=" cloaked
        . " rect=(" x "," y
        . " " width "x" height ")"
    )
}


; =============================================================================
; focus-tab appearance diagnostics
; =============================================================================

DebugFocusCornerAppearance(active_hwnd, active_slot_targets)
{
    global debug_enabled, debug_verbose_enabled, focus_corner_overlays, focus_corner_visible
    static previous_snapshot := ""

    if !debug_enabled || !debug_verbose_enabled
        return

    snapshot := (
        "active=" active_hwnd
        . " | foreground_now=" DllCall("GetForegroundWindow", "ptr")
        . " | active_slot_windows=" active_slot_targets.Count
        . " | tabs_visible=" focus_corner_visible
        . " | click_owned=" HasFocusTabClick()
    )

    for target_hwnd, overlay in focus_corner_overlays {
        try {
            marker_hwnd := overlay.gui.Hwnd
            native_visible := DllCall("IsWindowVisible", "ptr", marker_hwnd, "int")

            if !overlay.shown && !native_visible
                continue

            ; Read native state, not just the cached intended opacity. Pure HWNDs
            ; also let diagnostics inspect a GUI during a hide/show transition.
            native_alpha := WinGetTransparent(marker_hwnd)
            native_topmost := !!(WinGetExStyle(marker_hwnd) & 0x8)
            WinGetPos(&x, &y, &width, &height, marker_hwnd)
            preceding_hwnd := DllCall("GetWindow", "ptr", marker_hwnd, "uint", 3, "ptr") ; GW_HWNDPREV

            role := active_slot_targets.Has(target_hwnd) ? "active-slot" : "inactive-slot"

            snapshot .= (
                " | tab={target=" target_hwnd
                . ",hwnd=" marker_hwnd
                . ",role=" role
                . ",color=" overlay.gui.BackColor
                . ",base_alpha=" overlay.alpha
                . ",native_alpha=" (native_alpha == "" ? "unknown" : native_alpha)
                . ",shown=" overlay.shown
                . ",visible=" native_visible
                . ",topmost=" native_topmost
                . ",above=" preceding_hwnd
                . ",rect=" x "," y "," width "," height "}"
            )
        }
        catch {
            ; A target or its GUI may disappear during a diagnostic read.
            continue
        }
    }

    ; The fallback timer may read often, but unchanged state must not flood logs.
    if snapshot = previous_snapshot
        return

    previous_snapshot := snapshot
    DebugLog("Focus-tab appearance. | " snapshot)
}


DebugDescribeForegroundState()
{
    global debug_enabled

    if !debug_enabled
        return ""

    ; Foreground, thread activation and keyboard focus are different handles.
    ; Capture them only for launch-recovery diagnostics, never on every repaint.
    info := Buffer(24 + 6 * A_PtrSize, 0)
    NumPut("uint", info.Size, info)

    foreground := DllCall("GetForegroundWindow", "ptr")
    result := (
        "foreground=" foreground
        . " | foreground-pid=" DebugGetWindowProcessId(foreground)
    )

    if DllCall("GetGUIThreadInfo", "uint", 0, "ptr", info, "int") {
        thread_active := NumGet(info, 8, "ptr")
        keyboard_focus := NumGet(info, 8 + A_PtrSize, "ptr")
        keyboard_focus_root := (
            keyboard_focus
            ? DllCall("GetAncestor", "ptr", keyboard_focus, "uint", 2, "ptr") ; GA_ROOT
            : 0
        )

        result .= (
            " | thread-active=" thread_active
            . " | keyboard-focus=" keyboard_focus
            . " | keyboard-focus-root=" keyboard_focus_root
            . " | keyboard-focus-pid=" DebugGetWindowProcessId(keyboard_focus)
            . " | focus-root-is-foreground=" (keyboard_focus_root = foreground)
        )
    }

    return result
}


DebugGetWindowProcessId(hwnd)
{
    if !hwnd
        return 0

    pid := 0
    DllCall(
        "GetWindowThreadProcessId",
        "ptr", hwnd,
        "uint*", &pid,
        "uint"
    )
    return pid
}
