#!/usr/bin/env wish
# ============================================================
# ATTENDANCE MANAGEMENT SYSTEM  -  GUI VERSION
# Toolkit : Tcl/Tk 8.6
# ============================================================
package require Tk
encoding system utf-8
cd [file dirname [info script]]

# ============================================================
# THEME
# ============================================================
array set C {
    bg      "#1e2a3a"
    bg2     "#0f1a2a"
    btn     "#2e4a6a"
    btnact  "#3a6ea5"
    exit    "#6a2e2e"
    exitact "#a53a3a"
    fg      "#ffffff"
    dim     "#aaaaaa"
    blue    "#00d4ff"
    red     "#ff6b6b"
    green   "#6bffb8"
    hdr     "#243650"
}

# ============================================================
# UTILITY: center a toplevel on screen
# ============================================================
proc center_window {w width height} {
    set sw [winfo screenwidth  $w]
    set sh [winfo screenheight $w]
    set x  [expr {($sw - $width)  / 2}]
    set y  [expr {($sh - $height) / 2}]
    wm geometry $w ${width}x${height}+${x}+${y}
}

# ============================================================
# UTILITY: message popup
# ============================================================
proc msg_box {title text {icon info}} {
    tk_messageBox -title $title -message $text -type ok -icon $icon
}

# ============================================================
# ============================================================
# UTILITY: path helpers  -  all class data lives in classes/CLASS/
# ============================================================
proc class_dir {class} { return [file join "classes" $class] }
proc class_sf  {class} { return [file join "classes" $class "students.txt"] }
proc class_af  {class} { return [file join "classes" $class "attendance.txt"] }

# ============================================================
# UTILITY: get list of existing classes (scan classes/ subdirs)
# ============================================================
proc get_classes {} {
    set classes {}
    foreach d [glob -nocomplain -type d [file join "classes" "*"]] {
        set class [file tail $d]
        if {$class ne ""} { lappend classes $class }
    }
    return [lsort $classes]
}

# ============================================================
# UTILITY: parse one student-file line (pipe or plain format)
#   Pipe:  | 1 | ABDUS SALAAM M |
#   Plain: 1 ABDUS SALAAM M
# Returns: {roll name}
# ============================================================
proc parse_student_line {line} {
    set line [string trim $line]
    if {$line eq ""} { return [list "" ""] }

    # Pipe table:  | 1 | NAME |
    if {[string index $line 0] eq "|"} {
        set line [string trim $line "|"]
        set parts [split $line "|"]
        set roll [string trim [lindex $parts 0]]
        set name [string trim [lindex $parts 1]]
        return [list $roll $name]
    }

    # Tab-separated:  1\tNAME
    if {[string first "\t" $line] >= 0} {
        set parts [split $line "\t"]
        set roll [string trim [lindex $parts 0]]
        set name [string trim [lindex $parts 1]]
        return [list $roll $name]
    }

    # Plain space-separated:  1 NAME SURNAME
    set roll [lindex $line 0]
    set name [string trim [lrange $line 1 end]]
    return [list $roll $name]
}

# ============================================================
# UTILITY: load student + attendance data
# Attendance line format:
#   DATE ROLL1 ROLL2 ... OD:ROLL1 ROLL2 ...
# from_date / to_date : "YYYY-MM-DD" or "" for no filter
# Returns dict: students list  absent array-get  od array-get
#               total N  from_date  to_date
# ============================================================
proc load_report_data {class {from_date ""} {to_date ""}} {
    set sf [class_sf $class]
    set af [class_af $class]
    if {![file exists $sf] || ![file exists $af]} {
        error "Class '$class' not found.\nExpected folder: [file nativename [class_dir $class]]"
    }
    array set absent {}
    array set od     {}
    set students {}
    set fh [open $sf r]
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        lassign [parse_student_line $line] roll name
        if {$roll eq ""} continue
        lappend students [list $roll $name]
        set absent($roll) 0
        set od($roll)     0
    }
    close $fh

    set total 0
    set fh [open $af r]
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue

        # first token is the date
        set date_token [lindex [split $line] 0]

        # apply date range filter
        if {$from_date ne "" && $date_token < $from_date} continue
        if {$to_date   ne "" && $date_token > $to_date}   continue

        incr total

        # Split on OD: marker
        set od_part    ""
        set plain_part $line
        set od_idx [string first " OD:" $line]
        if {$od_idx >= 0} {
            set plain_part [string range $line 0 [expr {$od_idx - 1}]]
            set od_part    [string range $line [expr {$od_idx + 4}] end]
        }

        # OD rolls first — so we can exclude from absent
        set od_rolls {}
        foreach r [split $od_part] {
            set r [string trim $r]
            if {$r ne "" && [info exists od($r)]} {
                incr od($r)
                lappend od_rolls $r
            }
        }
        # absent — skip rolls that are in OD list
        foreach r [lrange [split $plain_part] 1 end] {
            set r [string trim $r]
            if {$r ne "" && [info exists absent($r)] && $r ni $od_rolls} {
                incr absent($r)
            }
        }
    }
    close $fh
    return [list students $students \
                 absent   [array get absent] \
                 od       [array get od] \
                 total    $total \
                 from_date $from_date \
                 to_date   $to_date]
}

# ============================================================
# ask_class  -  dropdown dialog to pick an existing class
# Returns class name string or "" if cancelled
# ============================================================
proc ask_class {title} {
    global C
    set classes [get_classes]

    set ns ::_ac[clock milliseconds]
    namespace eval $ns { variable sel ""; variable done 0 }

    set w .__ac[clock milliseconds]
    toplevel $w
    wm title     $w $title
    wm resizable $w 0 0
    wm transient $w .
    $w configure -background $C(bg)
    center_window $w 460 200
    tkwait visibility $w
    grab set $w

    set ${ns}::done 0

    frame $w.f -background $C(bg) -padx 30 -pady 24
    pack  $w.f -fill both -expand 1

    label $w.f.lbl -text "Select Class:" -anchor w \
        -background $C(bg) -foreground $C(fg) -font {Arial 13}
    pack  $w.f.lbl -fill x -pady {0 8}

    # ttk combobox for dropdown
    ttk::style configure TCombobox \
        -fieldbackground $C(bg2) \
        -background      $C(bg2) \
        -foreground      $C(fg)  \
        -arrowcolor      $C(fg)

    ttk::combobox $w.f.cb \
        -textvariable ${ns}::sel \
        -values       $classes \
        -font         {Arial 13} \
        -state        readonly \
        -width        30
    pack $w.f.cb -fill x -ipady 6

    # pre-select first class if any
    if {[llength $classes] > 0} {
        set ${ns}::sel [lindex $classes 0]
    }
    focus $w.f.cb

    frame $w.f.bf -background $C(bg)
    pack  $w.f.bf -pady {16 0}

    button $w.f.bf.ok -text "OK" -width 12 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 1]
    button $w.f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 2]
    pack $w.f.bf.ok $w.f.bf.cn -side left -padx 12 -ipady 8

    bind $w <Return> [list set ${ns}::done 1]
    bind $w <Escape> [list set ${ns}::done 2]

    vwait ${ns}::done
    set result [string trim [set ${ns}::sel]]
    set code   [set ${ns}::done]
    grab release $w
    destroy $w
    namespace delete $ns
    return [expr {$code == 2 ? "" : $result}]
}

# ============================================================
# ask_input  -  plain text input dialog (used for new class name,
#             roll number, etc.)
# Returns trimmed string or "" if cancelled
# ============================================================
proc ask_input {title prompt {default ""}} {
    global C
    set ns ::_ask[clock milliseconds]
    namespace eval $ns { variable val ""; variable done 0 }

    set w .__ask[clock milliseconds]
    toplevel $w
    wm title     $w $title
    wm resizable $w 0 0
    wm transient $w .
    $w configure -background $C(bg)
    center_window $w 520 240
    tkwait visibility $w
    grab set $w

    set ${ns}::val  $default
    set ${ns}::done 0

    frame $w.f -background $C(bg) -padx 30 -pady 24
    pack  $w.f -fill both -expand 1

    label $w.f.lbl -text $prompt -anchor w -wraplength 450 \
        -background $C(bg) -foreground $C(fg) -font {Arial 13}
    pack  $w.f.lbl -fill x -pady {0 10}

    entry $w.f.ent -width 42 -font {Arial 13} \
        -background $C(bg2) -foreground $C(fg) \
        -insertbackground $C(fg) -relief flat -bd 6 \
        -textvariable ${ns}::val
    pack  $w.f.ent -fill x -ipady 6
    focus $w.f.ent

    frame $w.f.bf -background $C(bg)
    pack  $w.f.bf -pady {16 0}

    button $w.f.bf.ok -text "OK" -width 12 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 1]
    button $w.f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 2]
    pack $w.f.bf.ok $w.f.bf.cn -side left -padx 12 -ipady 8

    bind $w.f.ent <Return> [list set ${ns}::done 1]
    bind $w        <Escape> [list set ${ns}::done 2]

    vwait ${ns}::done
    set result [string trim [set ${ns}::val]]
    set code   [set ${ns}::done]
    grab release $w
    destroy $w
    namespace delete $ns
    return [expr {$code == 2 ? "" : $result}]
}

# ============================================================
# ask_combobox  -  dropdown + editable entry dialog
# values    : list of suggestions shown in dropdown
# Returns selected/typed string or "" if cancelled
# ============================================================
proc ask_combobox {title prompt values {default ""}} {
    global C
    set ns ::_cb[clock milliseconds]
    namespace eval $ns { variable val ""; variable done 0 }

    set w .__cb[clock milliseconds]
    toplevel $w
    wm title     $w $title
    wm resizable $w 0 0
    wm transient $w .
    $w configure -background $C(bg)
    center_window $w 520 220
    tkwait visibility $w
    grab set $w

    set ${ns}::val  $default
    set ${ns}::done 0

    frame $w.f -background $C(bg) -padx 30 -pady 24
    pack  $w.f -fill both -expand 1

    label $w.f.lbl -text $prompt -anchor w -wraplength 450 \
        -background $C(bg) -foreground $C(fg) -font {Arial 13}
    pack  $w.f.lbl -fill x -pady {0 10}

    # editable combobox — user can type or pick from list
    ttk::combobox $w.f.cb \
        -textvariable ${ns}::val \
        -values       $values \
        -font         {Arial 13} \
        -state        normal \
        -width        36
    pack $w.f.cb -fill x -ipady 4
    # pre-select default
    if {$default ne ""} { $w.f.cb set $default }
    focus $w.f.cb

    frame $w.f.bf -background $C(bg)
    pack  $w.f.bf -pady {14 0}

    button $w.f.bf.ok -text "OK" -width 12 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 1]
    button $w.f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 2]
    pack $w.f.bf.ok $w.f.bf.cn -side left -padx 12 -ipady 8

    bind $w.f.cb <Return> [list set ${ns}::done 1]
    bind $w       <Escape> [list set ${ns}::done 2]

    vwait ${ns}::done
    set result [string trim [set ${ns}::val]]
    set code   [set ${ns}::done]
    grab release $w
    destroy $w
    namespace delete $ns
    return [expr {$code == 2 ? "" : $result}]
}

# ============================================================
# ask_daterange  -  pick From and To dates using two calendars
# Returns list {from_date to_date} or {} if cancelled
# ============================================================
proc ask_daterange {title} {
    global C

    set ns ::_dr[clock milliseconds]
    namespace eval $ns {
        variable from_date ""
        variable to_date   ""
        variable done      0
    }

    # default: from = first day of current month, to = today
    set today [clock format [clock seconds] -format "%Y-%m-%d"]
    set yr    [clock format [clock seconds] -format "%Y"]
    set mo    [clock format [clock seconds] -format "%m"]
    set ${ns}::from_date "${yr}-${mo}-01"
    set ${ns}::to_date   $today

    set w .__dr[clock milliseconds]
    toplevel $w
    wm title     $w $title
    wm resizable $w 0 0
    wm transient $w .
    $w configure -background $C(bg)
    center_window $w 900 560
    tkwait visibility $w
    grab set $w

    # --- title ---
    label $w.title -text "Select Date Range" \
        -font {Arial 14 bold} -background $C(bg) -foreground $C(blue)
    pack $w.title -pady {14 6}

    # --- two calendars side by side ---
    frame $w.cals -background $C(bg)
    pack  $w.cals -padx 20 -pady 4

    # FROM calendar
    frame $w.cals.lf -background $C(bg)
    pack  $w.cals.lf -side left -padx 16

    label $w.cals.lf.title -text "FROM Date" \
        -font {Arial 12 bold} -background $C(bg) -foreground $C(green)
    pack  $w.cals.lf.title -pady {0 4}

    frame $w.cals.lf.drow -background $C(bg)
    pack  $w.cals.lf.drow -pady {0 6}
    label $w.cals.lf.drow.lbl -text "Selected:" \
        -font {Arial 11} -background $C(bg) -foreground $C(dim)
    label $w.cals.lf.drow.val -textvariable ${ns}::from_date \
        -font {Arial 12 bold} -background $C(bg) -foreground $C(green)
    pack  $w.cals.lf.drow.lbl $w.cals.lf.drow.val -side left -padx 4

    set from_cy [string trimleft $yr 0]; if {$from_cy eq ""} {set from_cy 2026}
    set from_cm [string trimleft $mo 0]; if {$from_cm eq ""} {set from_cm 1}

    frame $w.cals.lf.cal -background $C(bg2) -padx 2 -pady 2
    pack  $w.cals.lf.cal
    cal_build $w.cals.lf.cal $from_cy $from_cm ${ns}::from_date

    # TO calendar
    frame $w.cals.rf -background $C(bg)
    pack  $w.cals.rf -side left -padx 16

    label $w.cals.rf.title -text "TO Date" \
        -font {Arial 12 bold} -background $C(bg) -foreground $C(blue)
    pack  $w.cals.rf.title -pady {0 4}

    frame $w.cals.rf.drow -background $C(bg)
    pack  $w.cals.rf.drow -pady {0 6}
    label $w.cals.rf.drow.lbl -text "Selected:" \
        -font {Arial 11} -background $C(bg) -foreground $C(dim)
    label $w.cals.rf.drow.val -textvariable ${ns}::to_date \
        -font {Arial 12 bold} -background $C(bg) -foreground $C(blue)
    pack  $w.cals.rf.drow.lbl $w.cals.rf.drow.val -side left -padx 4

    frame $w.cals.rf.cal -background $C(bg2) -padx 2 -pady 2
    pack  $w.cals.rf.cal
    cal_build $w.cals.rf.cal $from_cy $from_cm ${ns}::to_date

    # --- "All dates" checkbox shortcut ---
    set ${ns}::all_dates 0
    checkbutton $w.allchk \
        -text "Show All Dates (no filter)" \
        -font {Arial 12} \
        -variable ${ns}::all_dates \
        -background $C(bg) -foreground $C(fg) \
        -activebackground $C(bg) -activeforeground $C(fg) \
        -selectcolor $C(btn)
    pack $w.allchk -pady {8 4}

    # --- buttons ---
    frame $w.bf -background $C(bg)
    pack  $w.bf -pady {8 14}

    button $w.bf.ok -text "Generate Report" -width 18 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 1]
    button $w.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 2]
    pack $w.bf.ok $w.bf.cn -side left -padx 12 -ipady 8

    bind $w <Escape> [list set ${ns}::done 2]

    vwait ${ns}::done
    set code      [set ${ns}::done]
    set from      [set ${ns}::from_date]
    set to        [set ${ns}::to_date]
    set all_dates [set ${ns}::all_dates]
    grab release $w
    destroy $w
    namespace delete $ns

    if {$code == 2} { return {} }
    # if all_dates checked, return empty strings = no filter
    if {$all_dates} { return [list "" ""] }
    # validate
    if {$from eq "" || $to eq ""} { return [list "" ""] }
    if {$from > $to} {
        # swap silently
        return [list $to $from]
    }
    return [list $from $to]
}

# ============================================================
# make_list_window  -  maximized resizable window with listbox
# Returns window path
# ============================================================
proc make_list_window {title header_text} {
    global C
    set w .lw[clock milliseconds]
    toplevel $w
    wm title     $w $title
    wm resizable $w 1 1
    wm state     $w zoomed
    $w configure -background $C(bg)

    # top title bar
    frame $w.topbar -background $C(bg) -pady 10
    pack  $w.topbar -fill x
    label $w.topbar.t -text $title -font {Arial 16 bold} \
        -background $C(bg) -foreground $C(blue)
    pack  $w.topbar.t -padx 20

    # column header
    label $w.hdr -text $header_text -font {Courier 12 bold} \
        -background $C(hdr) -foreground $C(fg) -anchor w -pady 6
    pack  $w.hdr -fill x -padx 16

    # listbox + scrollbars
    frame $w.lf -background $C(bg)
    pack  $w.lf -fill both -expand 1 -padx 16 -pady {4 0}

    scrollbar $w.lf.sby -orient vertical
    scrollbar $w.lf.sbx -orient horizontal
    listbox $w.lf.lb \
        -font {Courier 12} \
        -background $C(bg2) -foreground $C(fg) \
        -selectbackground $C(btn) \
        -activestyle none \
        -yscrollcommand [list $w.lf.sby set] \
        -xscrollcommand [list $w.lf.sbx set]
    $w.lf.sby configure -command [list $w.lf.lb yview]
    $w.lf.sbx configure -command [list $w.lf.lb xview]

    grid $w.lf.lb  -row 0 -column 0 -sticky nsew
    grid $w.lf.sby -row 0 -column 1 -sticky ns
    grid $w.lf.sbx -row 1 -column 0 -sticky ew
    grid rowconfigure    $w.lf 0 -weight 1
    grid columnconfigure $w.lf 0 -weight 1

    # footer bar  -  close button on right, optional info label on left
    frame $w.footer -background $C(bg)
    pack  $w.footer -fill x

    button $w.footer.close -text "Close" -width 16 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list destroy $w]
    pack $w.footer.close -side right -padx 20 -pady 10 -ipady 8

    return $w
}

# ============================================================
# MAIN WINDOW
# ============================================================
wm title    . "Attendance Management System"
wm resizable . 1 1
wm state    . zoomed
. configure -background $C(bg)

frame .cf -background $C(bg)
place .cf -relx 0.5 -rely 0.5 -anchor center

label .cf.title -text "ATTENDANCE MANAGEMENT SYSTEM" \
    -font {Arial 22 bold} -background $C(bg) -foreground $C(blue)
pack .cf.title -pady {0 6}

label .cf.sub -text "Select a function below" \
    -font {Arial 13} -background $C(bg) -foreground $C(dim)
pack .cf.sub -pady {0 28}

frame .cf.btns -background $C(bg)
pack .cf.btns

set btn_defs {
    {"1. Create Class"    do_create_class}
    {"2. Add Student"     do_add_student}
    {"3. View Students"   do_view_students}
    {"4. Mark Attendance" do_mark_attendance}
    {"5. View Report"     do_view_report}
    {"6. Export CSV"      do_export_csv}
    {"7. Defaulter List"  do_defaulters}
    {"8. Search Student"  do_search_student}
}

set _col 0; set _row 0
foreach def $btn_defs {
    set bn .cf.btns.b${_row}${_col}
    button $bn -text [lindex $def 0] -width 26 -font {Arial 13 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 -command [lindex $def 1]
    grid $bn -row $_row -column $_col -padx 14 -pady 8 -ipady 10
    incr _col
    if {$_col == 2} { set _col 0; incr _row }
}

# 9th button — spans both columns so it's always fully visible
button .cf.btns.b_lab -text "9. Create Lab Batch" -width 56 -font {Arial 13 bold} \
    -background $C(btn) -foreground $C(fg) \
    -activebackground $C(btnact) -activeforeground $C(fg) \
    -relief flat -cursor hand2 -command do_create_lab_batches
grid .cf.btns.b_lab -row $_row -column 0 -columnspan 2 -padx 14 -pady 8 -ipady 10 -sticky ew

incr _row
button .cf.btns.b_edit -text "10. Edit Attendance" -width 56 -font {Arial 13 bold} \
    -background $C(btn) -foreground $C(fg) \
    -activebackground $C(btnact) -activeforeground $C(fg) \
    -relief flat -cursor hand2 -command do_edit_attendance
grid .cf.btns.b_edit -row $_row -column 0 -columnspan 2 -padx 14 -pady 8 -ipady 10 -sticky ew

button .cf.exitbtn -text "Exit" -width 56 -font {Arial 13 bold} \
    -background $C(exit) -foreground $C(fg) \
    -activebackground $C(exitact) -activeforeground $C(fg) \
    -relief flat -cursor hand2 -command {destroy .}
pack .cf.exitbtn -pady {26 0} -ipady 10

# ============================================================
# 1. CREATE CLASS  -  ask_input (new name, no existing class needed)
# ============================================================
proc do_create_class {} {
    set class [ask_input "Create Class" "Enter New Class Name:"]
    if {$class eq ""} return

    if {[regexp {[/\\.]} $class]} {
        msg_box "Error" "Class name must not contain  /  \\  or  ." error
        return
    }
    set dir [class_dir $class]
    if {[file exists $dir]} {
        msg_box "Error" "Class '$class' already exists." error
        return
    }
    # create  classes/<name>/  and empty data files inside
    file mkdir $dir
    foreach f [list [class_sf $class] [class_af $class]] {
        close [open $f w]
    }
    msg_box "Success" "Class '$class' created.\nFolder: [file nativename $dir]"
}

# ============================================================
# 2. ADD STUDENT  -  dropdown for class, then single/bulk
# ============================================================
proc do_add_student {} {
    global C
    set class [ask_class "Add Student"]
    if {$class eq ""} return

    set ns ::_opt[clock milliseconds]
    namespace eval $ns { variable choice 0 }

    set w .__opt[clock milliseconds]
    toplevel $w
    wm title $w "Add Student  -  $class"
    wm resizable $w 0 0
    wm transient $w .
    $w configure -background $C(bg)
    center_window $w 440 280
    tkwait visibility $w
    grab set $w

    frame $w.f -background $C(bg) -padx 36 -pady 28
    pack $w.f -fill both -expand 1

    label $w.f.lbl -text "Choose an option:" -font {Arial 14 bold} \
        -background $C(bg) -foreground $C(fg)
    pack $w.f.lbl -pady {0 16}

    foreach {txt val} {"Add Single Student" 1 "Import from File" 2 "Cancel" 99} {
        set bg [expr {$val == 99 ? $C(exit) : $C(btn)}]
        set ab [expr {$val == 99 ? $C(exitact) : $C(btnact)}]
        button $w.f.b$val -text $txt -width 28 -font {Arial 12 bold} \
            -background $bg -foreground $C(fg) \
            -activebackground $ab -activeforeground $C(fg) \
            -relief flat -cursor hand2 \
            -command [list set ${ns}::choice $val]
        pack $w.f.b$val -pady 6 -ipady 8
    }

    vwait ${ns}::choice
    set choice [set ${ns}::choice]
    grab release $w; destroy $w; namespace delete $ns

    if {$choice == 1} {
        set ns2 ::_sadd[clock milliseconds]
        namespace eval $ns2 { variable done 0; variable roll ""; variable name "" }

        set sw .__sadd[clock milliseconds]
        toplevel $sw
        wm title $sw "Add Single Student  -  $class"
        wm resizable $sw 0 0
        wm transient $sw .
        $sw configure -background $C(bg)
        center_window $sw 520 310
        tkwait visibility $sw
        grab set $sw

        frame $sw.f -background $C(bg) -padx 32 -pady 24
        pack $sw.f -fill both -expand 1

        foreach {lbl var} {"Roll Number:" roll "Name:" name} {
            label $sw.f.l_$var -text $lbl -anchor w -font {Arial 13} \
                -background $C(bg) -foreground $C(fg)
            pack  $sw.f.l_$var -fill x -pady {8 2}
            entry $sw.f.e_$var -width 36 -font {Arial 13} \
                -background $C(bg2) -foreground $C(fg) \
                -insertbackground $C(fg) -relief flat -bd 6 \
                -textvariable ${ns2}::$var
            pack  $sw.f.e_$var -fill x -ipady 6
        }

        frame $sw.f.bf -background $C(bg)
        pack $sw.f.bf -pady {18 0}

        button $sw.f.bf.ok -text "Add Student" -width 16 -font {Arial 12 bold} \
            -background $C(btn) -foreground $C(fg) \
            -activebackground $C(btnact) -activeforeground $C(fg) \
            -relief flat -cursor hand2 \
            -command [list apply [list {ns2 class} {
                set roll [string trim [set ${ns2}::roll]]
                set name [string trim [set ${ns2}::name]]
                if {$roll eq "" || $name eq ""} {
                    tk_messageBox -title "Error" \
                        -message "Roll number and Name cannot be empty." \
                        -type ok -icon error
                    return
                }
                set fh [open [class_sf $class] a]
                puts $fh "$roll $name"
                close $fh
                tk_messageBox -title "Success" \
                    -message "Student added:\n  Roll: $roll\n  Name: $name" \
                    -type ok -icon info
                set ${ns2}::done 1
            }] $ns2 $class]

        button $sw.f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
            -background $C(exit) -foreground $C(fg) \
            -activebackground $C(exitact) -activeforeground $C(fg) \
            -relief flat -cursor hand2 \
            -command [list set ${ns2}::done 99]

        pack $sw.f.bf.ok $sw.f.bf.cn -side left -padx 12 -ipady 8
        bind $sw.f.e_name <Return> [list set ${ns2}::done 1]
        focus $sw.f.e_roll

        vwait ${ns2}::done
        grab release $sw; destroy $sw; namespace delete $ns2

    } elseif {$choice == 2} {
        # look for the namelist inside the class subfolder first,
        # then fall back to the main folder
        set input_file [file join [class_dir $class] "namelist.txt"]
        if {![file exists $input_file]} {
            set input_file [file join [class_dir $class] "${class}_list.txt"]
        }
        if {![file exists $input_file]} {
            set expected [file nativename [file join [class_dir $class] "namelist.txt"]]
            msg_box "Error" \
                "Namelist file not found.\n\nPlace your namelist file here:\n  $expected\n\nFile format (one student per line):\n  ROLL  NAME" error
            return
        }
        set in  [open $input_file r]
        set out [open [class_sf $class] w]
        fcopy $in $out
        close $in; close $out
        msg_box "Success" "Students imported successfully from:\n[file nativename $input_file]"
    }
}

# ============================================================
# 3. VIEW STUDENTS  -  dropdown
# ============================================================
proc do_view_students {} {
    global C
    set class [ask_class "View Students"]
    if {$class eq ""} return

    set sf [class_sf $class]
    if {![file exists $sf]} { msg_box "Error" "Class '$class' not found." error; return }
    set fh [open $sf r]
    set lines [split [read $fh] \n]
    close $fh

    set hdr [format "  %-16s  %-40s" "Roll No" "Name"]
    set w [make_list_window "Student List  -  $class" $hdr]

    set count 0
    foreach line $lines {
        set line [string trim $line]
        if {$line eq ""} continue
        lassign [parse_student_line $line] roll name
        if {$roll eq ""} continue
        $w.lf.lb insert end [format "  %-16s  %s" $roll $name]
        incr count
    }
    if {$count == 0} { $w.lf.lb insert end "  (No students found)" }

    label $w.footer.cnt -text "Total: $count student(s)" -font {Arial 12} \
        -background $C(bg) -foreground $C(dim)
    pack $w.footer.cnt -side left -padx 20 -pady 10
}

# ============================================================
# 4. MARK ATTENDANCE  -  dropdown for class
# ============================================================
# CALENDAR WIDGET  -  renders inline in a parent frame
# cal_build  : draws the month grid into $parent
# cal_select : called when user clicks a day; updates $datevar
# ============================================================
proc cal_build {parent year month datevar} {
    global C

    # destroy previous grid if any
    foreach child [winfo children $parent] { destroy $child }

    set months {January February March April May June
                July August September October November December}
    set days   {Sun Mon Tue Wed Thu Fri Sat}

    # --- nav row ---
    frame $parent.nav -background $C(bg2)
    pack  $parent.nav -fill x

    button $parent.nav.prev -text "<" -font {Arial 12 bold} -width 3 \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list cal_prev $parent $year $month $datevar]
    label  $parent.nav.lbl \
        -text "[lindex $months [expr {$month-1}]]  $year" \
        -font {Arial 13 bold} -width 22 -anchor center \
        -background $C(bg2) -foreground $C(blue)
    button $parent.nav.next -text ">" -font {Arial 12 bold} -width 3 \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list cal_next $parent $year $month $datevar]
    pack $parent.nav.prev -side left  -padx 4 -pady 4 -ipady 2
    pack $parent.nav.lbl  -side left  -padx 4
    pack $parent.nav.next -side left  -padx 4 -pady 4 -ipady 2

    # --- day-of-week headers ---
    frame $parent.hdrs -background $C(bg2)
    pack  $parent.hdrs -fill x
    foreach d $days {
        label $parent.hdrs.d$d -text $d -width 4 -anchor center \
            -font {Arial 10 bold} \
            -background $C(bg2) -foreground $C(dim)
        pack $parent.hdrs.d$d -side left -padx 2 -pady 2
    }

    # --- day grid ---
    frame $parent.grid -background $C(bg2)
    pack  $parent.grid -fill both -expand 1

    # calculate first weekday of month (0=Sun)
    set first [clock format [clock scan "$year-$month-01"] -format %w]
    # days in month
    set next_month [expr {$month == 12 ? 1 : $month + 1}]
    set next_year  [expr {$month == 12 ? $year + 1 : $year}]
    set last_day [expr {int([string trimleft \
        [clock format \
            [expr {[clock scan "${next_year}-${next_month}-01"] - 86400}] \
            -format %d] \
        0])}]
    if {$last_day == 0} { set last_day 1 }

    # today for highlighting
    set today [clock format [clock seconds] -format "%Y-%m-%d"]

    set col $first
    set row 0
    for {set d 1} {$d <= $last_day} {incr d} {
        set ds [format "%04d-%02d-%02d" $year $month $d]

        # determine background: selected > today > default
        set curval [uplevel #0 [list set $datevar]]
        if {$ds eq $curval} {
            set bg $C(green)
            set fg $C(bg)
            set fw bold
        } elseif {$ds eq $today} {
            set bg $C(btnact)
            set fg $C(fg)
            set fw bold
        } else {
            set bg $C(bg2)
            set fg $C(fg)
            set fw normal
        }

        button $parent.grid.d${d} \
            -text [format "%2d" $d] \
            -font "Arial 11 $fw" -width 3 \
            -background $bg -foreground $fg \
            -activebackground $C(blue) -activeforeground $C(bg) \
            -relief flat -cursor hand2 \
            -command [list cal_select $parent $ds $datevar]
        grid $parent.grid.d${d} -row $row -column $col -padx 2 -pady 2 -ipady 3

        incr col
        if {$col == 7} { set col 0; incr row }
    }
}

proc cal_prev {parent year month datevar} {
    if {$month == 1} { cal_build $parent [expr {$year-1}] 12 $datevar
    } else           { cal_build $parent $year [expr {$month-1}] $datevar }
}
proc cal_next {parent year month datevar} {
    if {$month == 12} { cal_build $parent [expr {$year+1}] 1 $datevar
    } else            { cal_build $parent $year [expr {$month+1}] $datevar }
}
proc cal_select {parent date datevar} {
    global C

    # reset ALL day buttons to default colour first
    foreach child [winfo children $parent.grid] {
        $child configure -background $C(bg2) -foreground $C(fg)
    }
    # extract day number — strip leading zeros to avoid octal interpretation
    set day_part [lindex [split $date -] 2]
    set d [expr {int([string trimleft $day_part 0])}]
    if {$d == 0} { set d 1 }
    # highlight the chosen day
    catch { $parent.grid.d${d} configure -background $C(green) -foreground $C(bg) }
    # write result into the caller's variable
    uplevel #0 [list set $datevar $date]

    # if this date already has a record, load it into the absent/OD fields
    # the namespace is embedded in the datevar name: ::_ma<ts>::seldate
    set ns [namespace qualifiers $datevar]
    if {$ns eq ""} return
    # find the class from the namespace variable
    if {![info exists ${ns}::class]} return
    set class [set ${ns}::class]
    set af [class_af $class]
    if {![file exists $af]} return

    set fh [open $af r]
    set found_absent ""
    set found_od     ""
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        set tok [lindex [split $line] 0]
        if {$tok eq $date} {
            set od_part ""
            set plain   $line
            set oi [string first " OD:" $line]
            if {$oi >= 0} {
                set plain   [string range $line 0 [expr {$oi-1}]]
                set od_part [string trim [string range $line [expr {$oi+4}] end]]
            }
            set found_absent [string trim [join [lrange [split $plain] 1 end]]]
            set found_od     $od_part
            break
        }
    }
    close $fh

    # populate the entry fields
    set ${ns}::abs $found_absent
    set ${ns}::od  $found_od

    # update status label to show existing record was loaded
    if {$found_absent ne "" || $found_od ne ""} {
        set ${ns}::status "Existing record loaded for $date  (editing)"
    } else {
        set ${ns}::status ""
    }
}

# ============================================================
# 4. MARK ATTENDANCE  -  calendar picker, no manual date typing
# ============================================================
proc do_mark_attendance {} {
    global C
    set class [ask_class "Mark Attendance"]
    if {$class eq ""} return

    set ns ::_ma[clock milliseconds]
    namespace eval $ns {
        variable done 0; variable seldate ""; variable abs ""
        variable od ""; variable status ""; variable class ""
    }
    set ${ns}::class $class

    # shared save proc — overwrites existing date record or appends new one
    proc _save_attendance {class date abs od} {
        set af [class_af $class]
        set new_line $date
        if {$abs ne ""} { append new_line " $abs" }
        if {$od  ne ""} { append new_line " OD:$od" }

        # read existing lines
        set lines {}
        if {[file exists $af]} {
            set fh [open $af r]
            foreach line [split [read $fh] \n] {
                set line [string trim $line]
                if {$line eq ""} continue
                lappend lines $line
            }
            close $fh
        }

        # replace or append
        set found 0
        set out {}
        foreach line $lines {
            if {[lindex [split $line] 0] eq $date} {
                lappend out $new_line
                set found 1
            } else {
                lappend out $line
            }
        }
        if {!$found} { lappend out $new_line }

        set fh [open $af w]
        foreach line $out { puts $fh $line }
        close $fh
        return $found
    }

    set w .__ma[clock milliseconds]
    toplevel $w
    wm title     $w "Mark Attendance  -  $class"
    wm resizable $w 1 1
    $w configure -background $C(bg)
    center_window $w 620 820

    # --- content frame centered in the window ---
    frame $w.outer -background $C(bg)
    pack  $w.outer -fill both -expand 1

    frame $w.outer.f -background $C(bg) -padx 30 -pady 20
    pack  $w.outer.f -anchor center

    set f $w.outer.f

    # --- selected date display ---
    frame $f.drow -background $C(bg)
    pack  $f.drow -fill x -pady {0 6}
    label $f.drow.lbl -text "Selected Date:" -font {Arial 12 bold} \
        -background $C(bg) -foreground $C(fg)
    label $f.drow.val -textvariable ${ns}::seldate -font {Arial 13 bold} \
        -background $C(bg) -foreground $C(blue)
    pack $f.drow.lbl $f.drow.val -side left -padx 4

    # --- calendar ---
    set cy [clock format [clock seconds] -format %Y]
    set cm [clock format [clock seconds] -format %m]
    set cm [string trimleft $cm 0]
    if {$cm eq ""} {set cm 1}

    frame $f.cal -background $C(bg2) -padx 4 -pady 4
    pack  $f.cal -fill x -pady {0 14}
    cal_build $f.cal $cy $cm ${ns}::seldate

    # --- absent rolls ---
    label $f.la \
        -text "Absent Roll Numbers (space-separated, blank if none):" \
        -anchor w -font {Arial 12} -wraplength 460 \
        -background $C(bg) -foreground $C(fg)
    pack $f.la -fill x -pady {0 4}
    entry $f.ea -width 40 -font {Arial 13} \
        -background $C(bg2) -foreground $C(fg) \
        -insertbackground $C(fg) -relief flat -bd 6 \
        -textvariable ${ns}::abs
    pack $f.ea -fill x -ipady 8 -pady {0 12}

    # --- OD rolls ---
    label $f.lo \
        -text "OD Roll Numbers (space-separated, blank if none):" \
        -anchor w -font {Arial 12} -wraplength 460 \
        -background $C(bg) -foreground $C(blue)
    pack $f.lo -fill x -pady {0 4}
    entry $f.eo -width 40 -font {Arial 13} \
        -background $C(bg2) -foreground $C(fg) \
        -insertbackground $C(fg) -relief flat -bd 6 \
        -textvariable ${ns}::od
    pack $f.eo -fill x -ipady 8 -pady {0 18}

    # --- status bar (shows last save, no popup needed) ---
    label $f.status -textvariable ${ns}::status \
        -font {Arial 11 bold} -background $C(bg) -foreground $C(green) \
        -anchor center -wraplength 560
    pack $f.status -fill x -pady {0 4}

    # --- edit existing record for selected date ---
    button $f.editbtn \
        -text "View / Edit Selected Date Record" \
        -width 38 -font {Arial 11 bold} \
        -background $C(hdr) -foreground $C(blue) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list apply [list {ns class win} {
            set date [string trim [set ${ns}::seldate]]
            if {$date eq ""} {
                tk_messageBox -title "No Date" \
                    -message "Please select a date first." -type ok -icon info
                return
            }
            set af [class_af $class]
            set found_absent ""
            set found_od     ""
            set exists 0
            if {[file exists $af]} {
                set fh [open $af r]
                foreach line [split [read $fh] \n] {
                    set line [string trim $line]
                    if {$line eq ""} continue
                    if {[lindex [split $line] 0] eq $date} {
                        set exists 1
                        set oi [string first " OD:" $line]
                        set plain $line
                        set od_part ""
                        if {$oi >= 0} {
                            set plain   [string range $line 0 [expr {$oi-1}]]
                            set od_part [string trim \
                                [string range $line [expr {$oi+4}] end]]
                        }
                        set found_absent [string trim \
                            [join [lrange [split $plain] 1 end]]]
                        set found_od $od_part
                        break
                    }
                }
                close $fh
            }
            if {!$exists} {
                tk_messageBox -title "No Record" \
                    -message "No record found for $date.\nUse Mark & Continue or Mark & Close to add one." \
                    -type ok -icon info
                return
            }

            global C
            set ns2 ::_qe[clock milliseconds]
            namespace eval $ns2 {
                variable absent ""; variable od ""; variable done 0
            }
            set ${ns2}::absent $found_absent
            set ${ns2}::od     $found_od

            set ew .__qe[clock milliseconds]
            toplevel $ew
            wm title     $ew "Edit Record  -  $date"
            wm resizable $ew 0 0
            wm transient $ew $win
            $ew configure -background $C(bg)
            set sw [winfo screenwidth  $ew]
            set sh [winfo screenheight $ew]
            wm geometry $ew 560x300+[expr {($sw-560)/2}]+[expr {($sh-300)/2}]
            tkwait visibility $ew
            grab set $ew

            frame $ew.f -background $C(bg) -padx 28 -pady 20
            pack  $ew.f -fill both -expand 1

            label $ew.f.dt -text "Editing: $date" \
                -font {Arial 14 bold} \
                -background $C(bg) -foreground $C(blue)
            pack  $ew.f.dt -pady {0 14}

            foreach {lbl var fc} [list \
                "Absent Roll Numbers:" absent $C(fg) \
                "OD Roll Numbers:"     od     $C(blue) \
            ] {
                label $ew.f.l_$var -text $lbl -anchor w \
                    -font {Arial 12} \
                    -background $C(bg) -foreground $fc
                pack  $ew.f.l_$var -fill x -pady {6 2}
                entry $ew.f.e_$var -width 46 -font {Arial 12} \
                    -background $C(bg2) -foreground $C(fg) \
                    -insertbackground $C(fg) -relief flat -bd 4 \
                    -textvariable ${ns2}::$var
                pack  $ew.f.e_$var -fill x -ipady 6
            }
            focus $ew.f.e_absent

            frame $ew.f.bf -background $C(bg)
            pack  $ew.f.bf -pady {14 0}

            button $ew.f.bf.ok -text "Save Changes" -width 16 \
                -font {Arial 12 bold} \
                -background $C(btn) -foreground $C(fg) \
                -activebackground $C(btnact) -activeforeground $C(fg) \
                -relief flat -cursor hand2 \
                -command [list set ${ns2}::done 1]
            button $ew.f.bf.cn -text "Cancel" -width 12 \
                -font {Arial 12 bold} \
                -background $C(exit) -foreground $C(fg) \
                -activebackground $C(exitact) -activeforeground $C(fg) \
                -relief flat -cursor hand2 \
                -command [list set ${ns2}::done 2]
            pack $ew.f.bf.ok $ew.f.bf.cn -side left -padx 10 -ipady 6

            bind $ew <Return> [list set ${ns2}::done 1]
            bind $ew <Escape> [list set ${ns2}::done 2]

            vwait ${ns2}::done
            set new_abs [string trim [set ${ns2}::absent]]
            set new_od  [string trim [set ${ns2}::od]]
            set code    [set ${ns2}::done]
            grab release $ew; destroy $ew; namespace delete $ns2

            if {$code == 2} return

            _save_attendance $class $date $new_abs $new_od
            set ${ns}::abs    $new_abs
            set ${ns}::od     $new_od
            set ${ns}::status "Updated: $date"
        }] $ns $class $w]
    pack $f.editbtn -pady {0 10} -ipady 4

    # --- buttons ---
    frame $f.bf -background $C(bg)
    pack  $f.bf

    button $f.bf.ok -text "Mark & Continue" -width 18 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list apply [list {ns class f} {
            set date [string trim [set ${ns}::seldate]]
            set abs  [string trim [set ${ns}::abs]]
            set od   [string trim [set ${ns}::od]]
            if {$date eq ""} {
                tk_messageBox -title "Error" \
                    -message "Please select a date from the calendar." \
                    -type ok -icon error
                return
            }
            set was_edit [_save_attendance $class $date $abs $od]
            # clear entries
            set ${ns}::abs ""
            set ${ns}::od  ""
            # advance to next day
            set next [clock format \
                [expr {[clock scan $date -format "%Y-%m-%d"] + 86400}] \
                -format "%Y-%m-%d"]
            set ${ns}::seldate $next
            # rebuild calendar for next day's month
            set ny [lindex [split $next -] 0]
            set nm [string trimleft [lindex [split $next -] 1] 0]
            if {$nm eq ""} {set nm 1}
            cal_build $f.cal $ny $nm ${ns}::seldate
            # show silent status — no popup
            set act [expr {$was_edit ? "Updated" : "Saved"}]
            set ${ns}::status "$act: $date  ->  Next: $next"
        }] $ns $class $f]

    button $f.bf.done -text "Mark & Close" -width 16 -font {Arial 12 bold} \
        -background $C(btnact) -foreground $C(fg) \
        -activebackground $C(btn) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list apply [list {ns class} {
            set date [string trim [set ${ns}::seldate]]
            set abs  [string trim [set ${ns}::abs]]
            set od   [string trim [set ${ns}::od]]
            if {$date eq ""} {
                tk_messageBox -title "Error" \
                    -message "Please select a date from the calendar." \
                    -type ok -icon error
                return
            }
            set line $date
            if {$abs ne ""} { append line " $abs" }
            if {$od  ne ""} { append line " OD:$od" }
            set fh [open [class_af $class] a]
            puts $fh $line
            close $fh
            tk_messageBox -title "Success" \
                -message "Attendance saved for $date." \
                -type ok -icon info
            set ${ns}::done 1
        }] $ns $class]

    button $f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 99]

    pack $f.bf.ok $f.bf.done $f.bf.cn -side left -padx 8 -ipady 8
    focus $f.ea

    vwait ${ns}::done
    destroy $w; namespace delete $ns
}

# ============================================================
# 5. VIEW REPORT  -  dropdown
# ============================================================
proc do_view_report {} {
    global C
    set class [ask_class "View Report"]
    if {$class eq ""} return

    set dr [ask_daterange "View Report  -  $class"]
    if {$dr eq {}} return
    lassign $dr from_date to_date

    if {[catch {set data [load_report_data $class $from_date $to_date]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students  $d(students)
    array set absent $d(absent)
    array set od     $d(od)
    set total     $d(total)

    # build range label for title
    set range_lbl [expr {
        $from_date eq "" ? "All Dates" :
        "$from_date  to  $to_date"
    }]

    set hdr [format "  %-10s %-22s %-8s %-8s %-7s %-6s %-10s %-10s" \
        "Roll" "Name" "Present" "Absent" "OD" "Total" "Percent" "Status"]
    set w [make_list_window \
        "Attendance Report  -  $class  |  $range_lbl  (Periods: $total)" $hdr]

    foreach s $students {
        set roll    [lindex $s 0]
        set name    [lindex $s 1]
        set abs_cnt $absent($roll)
        set od_cnt  $od($roll)
        set present [expr {$total - $abs_cnt}]
        set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
        set status  [expr {$pct < 75 ? "BELOW 75%" : "OK"}]
        $w.lf.lb insert end \
            [format "  %-10s %-22s %-8d %-8d %-7d %-6d %-10.2f %-10s" \
                $roll $name $present $abs_cnt $od_cnt $total $pct $status]
        $w.lf.lb itemconfigure end \
            -foreground [expr {$pct < 75 ? $C(red) : $C(green)}]
    }
    if {[llength $students] == 0} {
        $w.lf.lb insert end "  (No students found for this date range)"
    }
}

# ============================================================
# 6. EXPORT CSV  -  dropdown
# ============================================================
proc do_export_csv {} {
    set class [ask_class "Export CSV Report"]
    if {$class eq ""} return

    set dr [ask_daterange "Export CSV  -  $class"]
    if {$dr eq {}} return
    lassign $dr from_date to_date

    if {[catch {set data [load_report_data $class $from_date $to_date]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students  $d(students)
    array set absent $d(absent)
    array set od     $d(od)
    set total     $d(total)

    set range_lbl [expr {$from_date eq "" ? "all" : "${from_date}_to_${to_date}"}]
    set outfile [file join [class_dir $class] "report_${class}_${range_lbl}.csv"]
    set fh [open $outfile w]
    puts $fh "Roll,Name,Present,Absent,OD,Total Periods,Percentage,Status"
    foreach s $students {
        set roll    [lindex $s 0]
        set name    [lindex $s 1]
        if {$roll eq ""} continue
        set abs_cnt $absent($roll)
        set od_cnt  $od($roll)
        set present [expr {$total - $abs_cnt}]
        set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
        set status  [expr {$pct < 75 ? "BELOW 75" : "OK"}]
        puts $fh [format "%s,%s,%d,%d,%d,%d,%.2f,%s" \
            $roll $name $present $abs_cnt $od_cnt $total $pct $status]
    }
    close $fh
    msg_box "Success" "CSV report saved:\n[file nativename [file join [pwd] $outfile]]"
}

# ============================================================
# 7. DEFAULTER LIST  -  dropdown
# ============================================================
proc do_defaulters {} {
    global C
    set class [ask_class "Defaulter List"]
    if {$class eq ""} return

    set dr [ask_daterange "Defaulter List  -  $class"]
    if {$dr eq {}} return
    lassign $dr from_date to_date

    if {[catch {set data [load_report_data $class $from_date $to_date]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students  $d(students)
    array set absent $d(absent)
    array set od     $d(od)
    set total     $d(total)

    set range_lbl [expr {$from_date eq "" ? "All Dates" : "$from_date  to  $to_date"}]

    set hdr [format "  %-10s %-22s %-8s %-7s %-10s" \
        "Roll" "Name" "Absent" "OD" "Attend %"]
    set w [make_list_window \
        "Defaulter List (<75%)  -  $class  |  $range_lbl  (Periods: $total)" $hdr]
    $w.topbar.t configure -foreground $C(red)

    set count 0
    foreach s $students {
        set roll    [lindex $s 0]
        set name    [lindex $s 1]
        if {$roll eq ""} continue
        set abs_cnt $absent($roll)
        set od_cnt  $od($roll)
        set present [expr {$total - $abs_cnt}]
        set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
        if {$pct < 75} {
            $w.lf.lb insert end \
                [format "  %-10s %-22s %-8d %-7d %.2f%%" \
                    $roll $name $abs_cnt $od_cnt $pct]
            $w.lf.lb itemconfigure end -foreground $C(red)
            incr count
        }
    }
    if {$count == 0} {
        $w.lf.lb insert end "  No defaulters  -  all students above 75%."
        $w.lf.lb itemconfigure end -foreground $C(green)
    }

    label $w.footer.cnt -text "Total Defaulters: $count student(s)" -font {Arial 12} \
        -background $C(bg) -foreground $C(dim)
    pack $w.footer.cnt -side left -padx 20 -pady 10
}

# ============================================================
# 8. SEARCH STUDENT  -  dropdown for class, then roll number input
# ============================================================
proc do_search_student {} {
    global C
    set class [ask_class "Search Student"]
    if {$class eq ""} return

    set roll [ask_input "Search Student" "Enter Roll Number:"]
    if {$roll eq ""} return

    set sf [class_sf $class]
    set af [class_af $class]
    if {![file exists $sf] || ![file exists $af]} {
        msg_box "Error" "Class '$class' not found." error; return
    }

    array set absent {}
    set found_name ""
    set fh [open $sf r]
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        lassign [parse_student_line $line] r n
        if {$r eq $roll} { set found_name $n }
        set absent($r) 0
    }
    close $fh

    if {$found_name eq ""} {
        msg_box "Not Found" "Roll '$roll' not found in class '$class'." error
        return
    }

    set total 0
    set fh [open $af r]
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        incr total
        set od_idx [string first " OD:" $line]
        set plain_part $line
        set od_part    ""
        if {$od_idx >= 0} {
            set plain_part [string range $line 0 [expr {$od_idx - 1}]]
            set od_part    [string range $line [expr {$od_idx + 4}] end]
        }
        foreach r [lrange [split $plain_part] 1 end] {
            set r [string trim $r]
            if {$r ne "" && [info exists absent($r)]} { incr absent($r) }
        }
        foreach r [split $od_part] {
            set r [string trim $r]
            if {$r ne "" && [info exists absent($r)]} { incr absent(od_$r) 0; incr od_count }
        }
    }
    close $fh

    # recalculate per-student OD from scratch using load_report_data
    if {[catch {set rdata [load_report_data $class]} rerr]} {
        set rdata {}
    }
    set od_cnt 0
    if {$rdata ne {}} {
        array set rd $rdata
        array set od_arr $rd(od)
        if {[info exists od_arr($roll)]} { set od_cnt $od_arr($roll) }
        set total $rd(total)
        if {[info exists absent($roll)]} { set abs_cnt $absent($roll) } else { set abs_cnt 0 }
        array set absent_arr $rd(absent)
        if {[info exists absent_arr($roll)]} { set abs_cnt $absent_arr($roll) }
    } else {
        set abs_cnt $absent($roll)
    }

    set present [expr {$total - $abs_cnt}]
    set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
    set status  [expr {$pct < 75 ? "BELOW 75%  (Defaulter)" : "OK"}]
    set pct_str [format "%.2f%%" $pct]
    set sc      [expr {$pct < 75 ? $C(red) : $C(green)}]

    set w .__sr[clock milliseconds]
    toplevel $w
    wm title     $w "Student Report  -  $roll"
    wm resizable $w 1 1
    wm state     $w zoomed
    $w configure -background $C(bg)

    frame $w.card -background $C(bg2) -padx 40 -pady 30
    place $w.card -relx 0.5 -rely 0.5 -anchor center

    label $w.card.title -text "STUDENT REPORT" -font {Arial 20 bold} \
        -background $C(bg2) -foreground $C(blue)
    pack $w.card.title -pady {0 20}

    set rownum 0
    foreach pair [list \
        [list "Roll Number"   $roll       $C(fg)] \
        [list "Name"          $found_name $C(fg)] \
        [list "Class"         $class      $C(fg)] \
        [list "Total Periods" $total      $C(fg)] \
        [list "Present"       $present    $C(fg)] \
        [list "Absent"        $abs_cnt    $C(red)] \
        [list "OD"            $od_cnt     $C(blue)] \
        [list "Percentage"    $pct_str    $C(fg)] \
        [list "Status"        $status     $sc   ] \
    ] {
        frame $w.card.r$rownum -background $C(bg2)
        pack  $w.card.r$rownum -fill x -pady 4
        label $w.card.r$rownum.k -text "[lindex $pair 0] :" \
            -font {Arial 13 bold} -width 18 -anchor w \
            -background $C(bg2) -foreground $C(dim)
        label $w.card.r$rownum.v -text [lindex $pair 1] \
            -font {Arial 14} -anchor w \
            -background $C(bg2) -foreground [lindex $pair 2]
        pack $w.card.r$rownum.k $w.card.r$rownum.v -side left -padx 4
        incr rownum
    }

    button $w.card.close -text "Close" -width 18 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 -command [list destroy $w]
    pack $w.card.close -pady {22 0} -ipady 10
}

# ============================================================
# 9. CREATE LAB BATCHES
# Splits a class student list into 2 batches (A and B),
# each stored as a new class folder:  CLASSNAME-LAB-A
#                                     CLASSNAME-LAB-B
# The main class folder is untouched (theory attendance).
# Both batch folders share the same lab subject name prefix.
# ============================================================
proc do_create_lab_batches {} {
    global C

    # Step 1: pick source class
    set class [ask_class "Create Lab Batches"]
    if {$class eq ""} return

    set sf [class_sf $class]
    if {![file exists $sf]} {
        msg_box "Error" "Class '$class' not found." error; return
    }

    # Step 2: ask lab subject — plain text entry, user types their own name
    set subject [ask_input "Lab Name" \
        "Enter the Lab Name:\n(e.g.  Microprocessor Lab  or  Networks Lab)" ""]
    if {$subject eq ""} return
    # sanitise — replace spaces and slashes with underscore
    set subject [string map {" " "_" "/" "_" "\\" "_"} $subject]

    # Step 3: read all students
    set fh [open $sf r]
    set alllines {}
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        lassign [parse_student_line $line] roll name
        if {$roll eq ""} continue
        lappend alllines [list $roll $name]
    }
    close $fh

    set total [llength $alllines]
    if {$total == 0} {
        msg_box "Error" "No students found in class '$class'." error; return
    }

    # Step 4: dedicated batch-split dialog
    set half [expr {int(ceil($total / 2.0))}]

    set ns4 ::_bs[clock milliseconds]
    namespace eval $ns4 { variable val ""; variable done 0 }
    set ${ns4}::val $half

    set bw .__bs[clock milliseconds]
    toplevel $bw
    wm title     $bw "Batch Split"
    wm resizable $bw 0 0
    wm transient $bw .
    $bw configure -background $C(bg)
    center_window $bw 480 300
    tkwait visibility $bw
    grab set $bw

    frame $bw.f -background $C(bg) -padx 30 -pady 24
    pack  $bw.f -fill both -expand 1

    label $bw.f.l1 -text "Total students: $total" \
        -font {Arial 13 bold} -background $C(bg) -foreground $C(blue)
    pack  $bw.f.l1 -pady {0 14}

    label $bw.f.l2 \
        -text "How many students in Batch A?\n(Batch B gets the rest)" \
        -font {Arial 12} -background $C(bg) -foreground $C(fg) \
        -justify center
    pack  $bw.f.l2 -pady {0 10}

    entry $bw.f.ent -width 20 -font {Arial 14} -justify center \
        -background $C(bg2) -foreground $C(fg) \
        -insertbackground $C(fg) -relief flat -bd 6 \
        -textvariable ${ns4}::val
    pack  $bw.f.ent -ipady 8 -pady {0 16}
    focus $bw.f.ent
    $bw.f.ent selection range 0 end

    frame $bw.f.bf -background $C(bg)
    pack  $bw.f.bf

    button $bw.f.bf.ok -text "OK" -width 12 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns4}::done 1]
    button $bw.f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns4}::done 2]
    pack $bw.f.bf.ok $bw.f.bf.cn -side left -padx 12 -ipady 8

    bind $bw.f.ent <Return> [list set ${ns4}::done 1]
    bind $bw        <Escape> [list set ${ns4}::done 2]

    vwait ${ns4}::done
    set split_val [string trim [set ${ns4}::val]]
    set done4     [set ${ns4}::done]
    grab release $bw
    destroy $bw
    namespace delete $ns4

    if {$done4 == 2} return
    if {![string is integer -strict $split_val] || \
        $split_val < 1 || $split_val >= $total} {
        msg_box "Error" \
            "Split must be a whole number between 1 and [expr {$total-1}]." error
        return
    }

    set batch_a [lrange $alllines 0 [expr {$split_val - 1}]]
    set batch_b [lrange $alllines $split_val end]

    # Step 5: create batch folders
    set name_a "${subject}_${class}-LAB-A"
    set name_b "${subject}_${class}-LAB-B"

    foreach {bname blist} [list $name_a $batch_a $name_b $batch_b] {
        set dir [class_dir $bname]
        if {[file exists $dir]} {
            set ans [tk_messageBox -title "Overwrite?" \
                -message "Batch '$bname' already exists.\nOverwrite student list?" \
                -type yesno -icon question]
            if {$ans ne "yes"} continue
        } else {
            file mkdir $dir
        }
        # write students.txt
        set fh [open [class_sf $bname] w]
        foreach s $blist {
            puts $fh "[lindex $s 0]\t[lindex $s 1]"
        }
        close $fh
        # create empty attendance.txt if not exists
        set af [class_af $bname]
        if {![file exists $af]} { close [open $af w] }
    }

    # Step 6: show result summary
    set w .lbr[clock milliseconds]
    toplevel $w
    wm title     $w "Lab Batches Created  -  $class"
    wm resizable $w 1 1
    wm state     $w zoomed
    $w configure -background $C(bg)

    # top title
    frame $w.topbar -background $C(bg) -pady 10
    pack  $w.topbar -fill x
    label $w.topbar.t -text "Lab Batches Created Successfully" \
        -font {Arial 16 bold} -background $C(bg) -foreground $C(green)
    pack  $w.topbar.t -padx 20

    # info summary block
    frame $w.info -background $C(bg2) -padx 20 -pady 14
    pack  $w.info -fill x -padx 20 -pady 10

    set rownum 0
    foreach row [list \
        [list "Source Class"  $class] \
        [list "Lab Subject"   $subject] \
        [list "Batch A"       "$name_a  ([llength $batch_a] students)"] \
        [list "Batch B"       "$name_b  ([llength $batch_b] students)"] \
        [list "Next Step"     "Use  4. Mark Attendance  and select a batch"] \
    ] {
        set rf $w.info.row$rownum
        frame $rf -background $C(bg2)
        pack  $rf -fill x -pady 3
        label $rf.k -text "[lindex $row 0] :" \
            -font {Arial 12 bold} -width 16 -anchor w \
            -background $C(bg2) -foreground $C(dim)
        label $rf.v -text [lindex $row 1] \
            -font {Arial 12} -anchor w \
            -background $C(bg2) -foreground $C(fg)
        pack $rf.k $rf.v -side left -padx 4
        incr rownum
    }

    # two listboxes side by side
    frame $w.lists -background $C(bg)
    pack  $w.lists -fill both -expand 1 -padx 20 -pady 8

    set col_idx 0
    set bnames [list $name_a $name_b]
    set blists [list $batch_a $batch_b]
    set bcols  [list $C(blue) $C(green)]
    for {set i 0} {$i < 2} {incr i} {
        set bname [lindex $bnames $i]
        set blist [lindex $blists $i]
        set bcol  [lindex $bcols  $i]
        set lf $w.lists.col$i
        frame $lf -background $C(bg)
        pack  $lf -side left -fill both -expand 1 -padx 8

        label $lf.t -text "$bname  ([llength $blist] students)" \
            -font {Arial 12 bold} -background $C(bg) -foreground $bcol
        pack  $lf.t -pady {0 6}

        frame $lf.lbf -background $C(bg)
        pack  $lf.lbf -fill both -expand 1

        scrollbar $lf.lbf.sb  -orient vertical
        listbox   $lf.lbf.box -font {Courier 12} \
            -background $C(bg2) -foreground $C(fg) \
            -selectbackground $C(btn) -activestyle none \
            -yscrollcommand [list $lf.lbf.sb set]
        $lf.lbf.sb configure -command [list $lf.lbf.box yview]
        pack $lf.lbf.box -side left -fill both -expand 1
        pack $lf.lbf.sb  -side right -fill y

        foreach s $blist {
            $lf.lbf.box insert end [format "  %-8s  %s" [lindex $s 0] [lindex $s 1]]
        }
    }

    button $w.close -text "Close" -width 16 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 -command [list destroy $w]
    pack $w.close -pady {8 14} -ipady 6
}

# ============================================================
# 10. EDIT ATTENDANCE
# Shows all attendance records for a class in a table.
# Click any row to edit that day's absent/OD rolls.
# ============================================================
proc do_edit_attendance {} {
    global C
    set class [ask_class "Edit Attendance"]
    if {$class eq ""} return

    set af [class_af $class]
    if {![file exists $af]} {
        msg_box "Error" "No attendance file for '$class'." error; return
    }

    # unique namespace to hold entries for this edit session
    set ns ::_eat[clock milliseconds]
    namespace eval $ns { variable entries {} }

    # ---- read all lines ----
    set fh [open $af r]
    set raw_lines [split [read $fh] \n]
    close $fh

    set elist {}
    foreach line $raw_lines {
        set line [string trim $line]
        if {$line eq ""} continue
        set od_part ""
        set plain   $line
        set oi [string first " OD:" $line]
        if {$oi >= 0} {
            set plain   [string range $line 0 [expr {$oi-1}]]
            set od_part [string trim [string range $line [expr {$oi+4}] end]]
        }
        set tokens [split $plain]
        set date   [lindex $tokens 0]
        set absent [string trim [join [lrange $tokens 1 end]]]
        lappend elist [list $date $absent $od_part]
    }
    # sort by date
    set ${ns}::entries [lsort -index 0 $elist]

    # ---- build window ----
    set w .ea[clock milliseconds]
    toplevel $w
    wm title     $w "Edit Attendance  -  $class"
    wm resizable $w 1 1
    wm state     $w zoomed
    $w configure -background $C(bg)

    # destroy namespace when window closes
    bind $w <Destroy> [list namespace delete $ns]

    frame $w.topbar -background $C(bg) -pady 10
    pack  $w.topbar -fill x
    label $w.topbar.t \
        -text "Edit Attendance  -  $class  (double-click a row to edit)" \
        -font {Arial 15 bold} -background $C(bg) -foreground $C(blue)
    pack  $w.topbar.t -padx 20

    label $w.hdr \
        -text [format "  %-14s  %-36s  %-20s" "Date" "Absent Rolls" "OD Rolls"] \
        -font {Courier 12 bold} -background $C(hdr) -foreground $C(fg) \
        -anchor w -pady 6
    pack $w.hdr -fill x -padx 16

    frame $w.lf -background $C(bg)
    pack  $w.lf -fill both -expand 1 -padx 16 -pady {4 0}

    scrollbar $w.lf.sby -orient vertical
    listbox $w.lf.lb \
        -font {Courier 12} \
        -background $C(bg2) -foreground $C(fg) \
        -selectbackground $C(btnact) \
        -activestyle none \
        -yscrollcommand [list $w.lf.sby set]
    $w.lf.sby configure -command [list $w.lf.lb yview]
    pack $w.lf.lb  -side left -fill both -expand 1
    pack $w.lf.sby -side right -fill y

    # populate list
    ea_refresh $w $ns

    frame $w.footer -background $C(bg)
    pack  $w.footer -fill x

    label $w.footer.hint \
        -text "Double-click or Enter to edit  |  Delete to remove row" \
        -font {Arial 11} -background $C(bg) -foreground $C(dim)
    pack  $w.footer.hint -side left -padx 20 -pady 10

    button $w.footer.del -text "Delete Row" -width 14 -font {Arial 11 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list do_edit_delete $w $af $ns $class]
    pack  $w.footer.del -side right -padx 8 -pady 8 -ipady 4

    button $w.footer.close -text "Close" -width 14 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list destroy $w]
    pack  $w.footer.close -side right -padx 8 -pady 8 -ipady 4

    bind $w.lf.lb <Double-Button-1> [list do_edit_row $w $af $ns $class]
    bind $w.lf.lb <Return>          [list do_edit_row $w $af $ns $class]
}

# ---- refresh listbox from namespace entries ----
proc ea_refresh {w ns} {
    set lb $w.lf.lb
    $lb delete 0 end
    foreach e [set ${ns}::entries] {
        set date   [lindex $e 0]
        set absent [lindex $e 1]
        set od     [lindex $e 2]
        $lb insert end [format "  %-14s  %-36s  %-20s" $date $absent $od]
    }
}

# ---- write namespace entries back to file ----
proc ea_save {af ns} {
    set fh [open $af w]
    foreach e [set ${ns}::entries] {
        set date   [lindex $e 0]
        set absent [lindex $e 1]
        set od     [lindex $e 2]
        set line   $date
        if {$absent ne ""} { append line " $absent" }
        if {$od     ne ""} { append line " OD:$od"  }
        puts $fh $line
    }
    close $fh
}

# ---- edit a single row ----
proc do_edit_row {w af ns class} {
    global C

    set lb  $w.lf.lb
    set idx [$lb curselection]
    if {$idx eq ""} {
        tk_messageBox -title "Select Row" \
            -message "Please click a row first." -type ok -icon info
        return
    }
    set idx [lindex $idx 0]
    set e   [lindex [set ${ns}::entries] $idx]

    set date   [lindex $e 0]
    set absent [lindex $e 1]
    set od     [lindex $e 2]

    set ns2 ::_er[clock milliseconds]
    namespace eval $ns2 { variable absent ""; variable od ""; variable done 0 }
    set ${ns2}::absent $absent
    set ${ns2}::od     $od

    set ew .__er[clock milliseconds]
    toplevel $ew
    wm title     $ew "Edit  -  $date"
    wm resizable $ew 0 0
    wm transient $ew $w
    $ew configure -background $C(bg)
    center_window $ew 560 300
    tkwait visibility $ew
    grab set $ew

    frame $ew.f -background $C(bg) -padx 28 -pady 20
    pack  $ew.f -fill both -expand 1

    label $ew.f.dtitle -text "Date: $date" \
        -font {Arial 14 bold} -background $C(bg) -foreground $C(blue)
    pack  $ew.f.dtitle -pady {0 14}

    foreach {lbl var fg_col} [list \
        "Absent Roll Numbers:" absent $C(fg) \
        "OD Roll Numbers:"     od     $C(blue) \
    ] {
        label $ew.f.l_$var -text $lbl -anchor w \
            -font {Arial 12} -background $C(bg) -foreground $fg_col
        pack  $ew.f.l_$var -fill x -pady {8 2}
        entry $ew.f.e_$var -width 46 -font {Arial 12} \
            -background $C(bg2) -foreground $C(fg) \
            -insertbackground $C(fg) -relief flat -bd 4 \
            -textvariable ${ns2}::$var
        pack  $ew.f.e_$var -fill x -ipady 6
    }
    focus $ew.f.e_absent

    frame $ew.f.bf -background $C(bg)
    pack  $ew.f.bf -pady {16 0}

    button $ew.f.bf.ok -text "Save Changes" -width 16 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns2}::done 1]
    button $ew.f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns2}::done 2]
    pack $ew.f.bf.ok $ew.f.bf.cn -side left -padx 10 -ipady 6

    bind $ew <Return> [list set ${ns2}::done 1]
    bind $ew <Escape> [list set ${ns2}::done 2]

    vwait ${ns2}::done
    set new_absent [string trim [set ${ns2}::absent]]
    set new_od     [string trim [set ${ns2}::od]]
    set code       [set ${ns2}::done]
    grab release $ew; destroy $ew; namespace delete $ns2

    if {$code == 2} return

    # update namespace entries
    lset ${ns}::entries $idx [list $date $new_absent $new_od]
    ea_save $af $ns
    ea_refresh $w $ns
}

# ---- delete a row ----
proc do_edit_delete {w af ns class} {
    set lb  $w.lf.lb
    set idx [$lb curselection]
    if {$idx eq ""} {
        tk_messageBox -title "Select Row" \
            -message "Please click a row to delete." -type ok -icon info
        return
    }
    set idx  [lindex $idx 0]
    set date [lindex [lindex [set ${ns}::entries] $idx] 0]

    set ans [tk_messageBox -title "Confirm Delete" \
        -message "Delete attendance record for:\n  $date ?" \
        -type yesno -icon warning -default no]
    if {$ans ne "yes"} return

    set ${ns}::entries [lreplace [set ${ns}::entries] $idx $idx]
    ea_save $af $ns
    ea_refresh $w $ns
}
