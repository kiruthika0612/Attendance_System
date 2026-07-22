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
# Returns dict: students list  absent array-get  od array-get  total N
# ============================================================
proc load_report_data {class} {
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
        incr total

        # Split on OD: marker
        # Format: DATE A1 A2 ... OD:O1 O2 ...
        set od_part    ""
        set plain_part $line
        set od_idx [string first " OD:" $line]
        if {$od_idx >= 0} {
            set plain_part [string range $line 0 [expr {$od_idx - 1}]]
            set od_part    [string range $line [expr {$od_idx + 4}] end]
        }

        # First token of plain_part is the date — skip it
        set absent_rolls [lrange [split $plain_part] 1 end]
        # OD rolls — collect them first so we can exclude from absent
        set od_rolls {}
        foreach r [split $od_part] {
            set r [string trim $r]
            if {$r ne "" && [info exists od($r)]} {
                incr od($r)
                lappend od_rolls $r
            }
        }
        # Only count as absent if NOT in OD list for this day
        foreach r $absent_rolls {
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
                 total    $total]
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
    set last_day   [clock format \
        [expr {[clock scan "${next_year}-${next_month}-01"] - 86400}] \
        -format %d]

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
    # extract day number  -  strip leading zero to get plain integer
    set day_part [lindex [split $date -] 2]
    set d [expr {int($day_part)}]
    # highlight the chosen day
    catch { $parent.grid.d${d} configure -background $C(green) -foreground $C(bg) }
    # write result into the caller's variable
    uplevel #0 [list set $datevar $date]
}

# ============================================================
# 4. MARK ATTENDANCE  -  calendar picker, no manual date typing
# ============================================================
proc do_mark_attendance {} {
    global C
    set class [ask_class "Mark Attendance"]
    if {$class eq ""} return

    set ns ::_ma[clock milliseconds]
    namespace eval $ns { variable done 0; variable seldate ""; variable abs ""; variable od "" }

    # pre-select today
    set ${ns}::seldate [clock format [clock seconds] -format "%Y-%m-%d"]

    set w .__ma[clock milliseconds]
    toplevel $w
    wm title     $w "Mark Attendance  -  $class"
    wm resizable $w 1 1
    $w configure -background $C(bg)
    center_window $w 560 720

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

    # --- buttons ---
    frame $f.bf -background $C(bg)
    pack  $f.bf

    button $f.bf.ok -text "Mark Attendance" -width 20 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
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
            # Build line: DATE ABSENT_ROLLS OD:OD_ROLLS
            set line $date
            if {$abs ne ""} { append line " $abs" }
            if {$od  ne ""} { append line " OD:$od" }
            set fh [open [class_af $class] a]
            puts $fh $line
            close $fh
            tk_messageBox -title "Success" \
                -message "Attendance marked for $date." \
                -type ok -icon info
            set ${ns}::done 1
        }] $ns $class]

    button $f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 99]

    pack $f.bf.ok $f.bf.cn -side left -padx 12 -ipady 8
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

    if {[catch {set data [load_report_data $class]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students $d(students)
    array set absent $d(absent)
    array set od     $d(od)
    set total $d(total)

    set hdr [format "  %-10s %-22s %-8s %-8s %-7s %-6s %-10s %-10s" \
        "Roll" "Name" "Present" "Absent" "OD" "Total" "Percent" "Status"]
    set w [make_list_window "Attendance Report  -  $class  (Total Periods: $total)" $hdr]

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
        $w.lf.lb insert end "  (No students found)"
    }
}

# ============================================================
# 6. EXPORT CSV  -  dropdown
# ============================================================
proc do_export_csv {} {
    set class [ask_class "Export CSV Report"]
    if {$class eq ""} return

    if {[catch {set data [load_report_data $class]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students $d(students)
    array set absent $d(absent)
    array set od     $d(od)
    set total $d(total)

    set outfile [file join [class_dir $class] "report_${class}.csv"]
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

    if {[catch {set data [load_report_data $class]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students $d(students)
    array set absent $d(absent)
    array set od     $d(od)
    set total $d(total)

    set hdr [format "  %-10s %-22s %-8s %-7s %-10s" \
        "Roll" "Name" "Absent" "OD" "Attend %"]
    set w [make_list_window "Defaulter List (<75%)  -  $class  (Total Periods: $total)" $hdr]
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
