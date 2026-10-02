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
