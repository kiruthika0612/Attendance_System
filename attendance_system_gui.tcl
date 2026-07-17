#!/usr/bin/env wish
# ============================================================
# ATTENDANCE MANAGEMENT SYSTEM  -  GUI VERSION
# Toolkit : Tcl/Tk 8.6
# ============================================================
package require Tk
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
# UTILITY: error/info popup
# ============================================================
proc msg_box {title text {icon info}} {
    tk_messageBox -title $title -message $text -type ok -icon $icon
}

# ============================================================
# ask_input — centered modal dialog, returns string or ""
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
    center_window $w 520 200
    tkwait visibility $w
    grab set $w

    set ${ns}::val  $default
    set ${ns}::done 0

    # --- outer frame fills window ---
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
# load_report_data
# ============================================================
proc load_report_data {class} {
    set sf "students_${class}.txt"
    set af "attendance_${class}.txt"
    if {![file exists $sf] || ![file exists $af]} {
        error "Class '$class' not found.\nExpected: $sf and $af"
    }
    array set absent {}
    set students {}
    set fh [open $sf r]
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        set roll [lindex $line 0]
        set name [lrange $line 1 end]
        lappend students [list $roll $name]
        set absent($roll) 0
    }
    close $fh
    set total 0
    set fh [open $af r]
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        set cols [lrange [split $line] 1 end]
        incr total
        foreach r $cols {
            if {[info exists absent($r)]} { incr absent($r) }
        }
    }
    close $fh
    return [list students $students absent [array get absent] total $total]
}

# ============================================================
# make_list_window — maximized window with listbox + scrollbars
# ============================================================
proc make_list_window {title header_text} {
    global C
    set safe [string map {" " _ - _ ( _ ) _ / _ \\ _} $title]
    set w .[string range $safe 0 20][clock milliseconds]
    toplevel $w
    wm title     $w $title
    wm resizable $w 1 1
    wm state     $w zoomed
    $w configure -background $C(bg)

    # title bar inside window
    frame $w.topbar -background $C(bg) -pady 10
    pack  $w.topbar -fill x

    label $w.topbar.t -text $title -font {Arial 16 bold} \
        -background $C(bg) -foreground $C(blue)
    pack  $w.topbar.t -padx 20

    # column header bar
    label $w.hdr -text $header_text -font {Courier 12 bold} \
        -background $C(hdr) -foreground $C(fg) -anchor w -pady 6
    pack  $w.hdr -fill x -padx 16

    # listbox frame
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

    button $w.close -text "Close" -width 16 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list destroy $w]
    pack $w.close -pady {8 14} -ipady 8

    return $w
}

# ============================================================
# MAIN WINDOW  — maximized, content centered via place
# ============================================================
wm title    . "Attendance Management System"
wm resizable . 1 1
wm state    . zoomed
. configure -background $C(bg)

# center_frame holds everything and is placed at screen center
frame .cf -background $C(bg)
place .cf -relx 0.5 -rely 0.5 -anchor center

label .cf.title -text "ATTENDANCE MANAGEMENT SYSTEM" \
    -font {Arial 22 bold} -background $C(bg) -foreground $C(blue)
pack .cf.title -pady {0 6}

label .cf.sub -text "Select a function below" \
    -font {Arial 13} -background $C(bg) -foreground $C(dim)
pack .cf.sub -pady {0 28}

frame .cf.btns -background $C(bg)
pack .cf.btns -pady 0

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
    set lbl [lindex $def 0]
    set cmd [lindex $def 1]
    set bn  .cf.btns.b${_row}${_col}
    button $bn -text $lbl -width 26 -font {Arial 13 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 -command $cmd
    grid $bn -row $_row -column $_col -padx 14 -pady 8 -ipady 10
    incr _col
    if {$_col == 2} { set _col 0; incr _row }
}

button .cf.exitbtn -text "Exit" -width 56 -font {Arial 13 bold} \
    -background $C(exit) -foreground $C(fg) \
    -activebackground $C(exitact) -activeforeground $C(fg) \
    -relief flat -cursor hand2 -command {destroy .}
pack .cf.exitbtn -pady {26 0} -ipady 10

# ============================================================
# 1. CREATE CLASS
# ============================================================
proc do_create_class {} {
    set class [ask_input "Create Class" "Enter Class Name:"]
    if {$class eq ""} return
    foreach f [list "students_${class}.txt" "attendance_${class}.txt"] {
        if {![file exists $f]} { close [open $f w] }
    }
    msg_box "Success" "Class '$class' created successfully."
}

# ============================================================
# 2. ADD STUDENT
# ============================================================
proc do_add_student {} {
    global C
    set class [ask_input "Add Student" "Enter Class Name:"]
    if {$class eq ""} return

    if {![file exists "students_${class}.txt"]} {
        msg_box "Error" "Class '$class' not found. Create it first." error
        return
    }

    # option chooser — centered, large
    set ns ::_opt[clock milliseconds]
    namespace eval $ns { variable choice 0 }

    set w .__opt[clock milliseconds]
    toplevel $w
    wm title     $w "Add Student — $class"
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
    grab release $w
    destroy $w
    namespace delete $ns

    if {$choice == 1} {
        set ns2 ::_sadd[clock milliseconds]
        namespace eval $ns2 { variable done 0; variable roll ""; variable name "" }

        set sw .__sadd[clock milliseconds]
        toplevel $sw
        wm title     $sw "Add Single Student — $class"
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
                set fh [open "students_${class}.txt" a]
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
        grab release $sw
        destroy $sw
        namespace delete $ns2

    } elseif {$choice == 2} {
        set input_file "${class}_list.txt"
        if {![file exists $input_file]} {
            msg_box "Error" \
                "Import file '$input_file' not found.\nCreate it with lines:  ROLL NAME" error
            return
        }
        set in  [open $input_file r]
        set out [open "students_${class}.txt" w]
        fcopy $in $out
        close $in; close $out
        msg_box "Success" "Bulk import from '$input_file' successful."
    }
}

# ============================================================
# 3. VIEW STUDENTS
# ============================================================
proc do_view_students {} {
    global C
    set class [ask_input "View Students" "Enter Class Name:"]
    if {$class eq ""} return

    set sf "students_${class}.txt"
    if {![file exists $sf]} { msg_box "Error" "Class '$class' not found." error; return }

    set fh [open $sf r]
    set lines [split [read $fh] \n]
    close $fh

    set hdr [format "  %-16s  %-40s" "Roll No" "Name"]
    set w [make_list_window "Student List — $class" $hdr]

    set count 0
    foreach line $lines {
        set line [string trim $line]
        if {$line eq ""} continue
        set roll [lindex $line 0]
        set name [lrange $line 1 end]
        $w.lf.lb insert end [format "  %-16s  %s" $roll $name]
        incr count
    }
    if {$count == 0} { $w.lf.lb insert end "  (No students found)" }

    label $w.cnt -text "Total: $count student(s)" -font {Arial 12} \
        -background $C(bg) -foreground $C(dim)
    pack $w.cnt -before $w.close -pady {0 4}
}

# ============================================================
# 4. MARK ATTENDANCE
# ============================================================
proc do_mark_attendance {} {
    global C
    set class [ask_input "Mark Attendance" "Enter Class Name:"]
    if {$class eq ""} return

    if {![file exists "attendance_${class}.txt"]} {
        msg_box "Error" "Class '$class' not found." error; return
    }

    set ns ::_ma[clock milliseconds]
    namespace eval $ns { variable done 0; variable date ""; variable abs "" }

    set w .__ma[clock milliseconds]
    toplevel $w
    wm title     $w "Mark Attendance — $class"
    wm resizable $w 0 0
    wm transient $w .
    $w configure -background $C(bg)
    center_window $w 560 320
    tkwait visibility $w
    grab set $w

    frame $w.f -background $C(bg) -padx 32 -pady 24
    pack $w.f -fill both -expand 1

    label $w.f.ld -text "Date (YYYY-MM-DD):" -anchor w -font {Arial 13} \
        -background $C(bg) -foreground $C(fg)
    pack $w.f.ld -fill x -pady {0 4}
    entry $w.f.ed -width 38 -font {Arial 13} \
        -background $C(bg2) -foreground $C(fg) \
        -insertbackground $C(fg) -relief flat -bd 6 \
        -textvariable ${ns}::date
    pack $w.f.ed -fill x -ipady 6 -pady {0 16}

    label $w.f.la \
        -text "Absent Roll Numbers (space-separated, leave blank if none):" \
        -anchor w -font {Arial 13} -wraplength 480 \
        -background $C(bg) -foreground $C(fg)
    pack $w.f.la -fill x -pady {0 4}
    entry $w.f.ea -width 38 -font {Arial 13} \
        -background $C(bg2) -foreground $C(fg) \
        -insertbackground $C(fg) -relief flat -bd 6 \
        -textvariable ${ns}::abs
    pack $w.f.ea -fill x -ipady 6 -pady {0 20}

    frame $w.f.bf -background $C(bg)
    pack $w.f.bf

    button $w.f.bf.ok -text "Mark Attendance" -width 20 -font {Arial 12 bold} \
        -background $C(btn) -foreground $C(fg) \
        -activebackground $C(btnact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list apply [list {ns class} {
            set date [string trim [set ${ns}::date]]
            set abs  [string trim [set ${ns}::abs]]
            if {$date eq ""} {
                tk_messageBox -title "Error" -message "Date cannot be empty." -type ok -icon error
                return
            }
            if {![regexp {^\d{4}-\d{2}-\d{2}$} $date]} {
                tk_messageBox -title "Error" \
                    -message "Date must be YYYY-MM-DD format.\nExample: 2025-07-16" \
                    -type ok -icon error
                return
            }
            set fh [open "attendance_${class}.txt" a]
            puts $fh "$date $abs"
            close $fh
            tk_messageBox -title "Success" \
                -message "Attendance marked for $date." -type ok -icon info
            set ${ns}::done 1
        }] $ns $class]

    button $w.f.bf.cn -text "Cancel" -width 12 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 \
        -command [list set ${ns}::done 99]

    pack $w.f.bf.ok $w.f.bf.cn -side left -padx 12 -ipady 8
    bind $w.f.ea <Return> [list set ${ns}::done 1]
    focus $w.f.ed

    vwait ${ns}::done
    grab release $w
    destroy $w
    namespace delete $ns
}

# ============================================================
# 5. VIEW REPORT
# ============================================================
proc do_view_report {} {
    global C
    set class [ask_input "View Report" "Enter Class Name:"]
    if {$class eq ""} return

    if {[catch {set data [load_report_data $class]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students $d(students)
    array set absent $d(absent)
    set total $d(total)

    set hdr [format "  %-12s %-24s %-10s %-8s %-12s %-12s" \
        "Roll" "Name" "Present" "Total" "Percent" "Status"]
    set w [make_list_window "Attendance Report — $class  (Total Periods: $total)" $hdr]

    foreach s $students {
        set roll    [lindex $s 0]
        set name    [lindex $s 1]
        set present [expr {$total - $absent($roll)}]
        set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
        set status  [expr {$pct < 75 ? "BELOW 75%" : "OK"}]
        $w.lf.lb insert end \
            [format "  %-12s %-24s %-10d %-8d %-12.2f %-12s" \
                $roll $name $present $total $pct $status]
        $w.lf.lb itemconfigure end \
            -foreground [expr {$pct < 75 ? $C(red) : $C(green)}]
    }
    if {[llength $students] == 0} {
        $w.lf.lb insert end "  (No students found)"
    }
}

# ============================================================
# 6. EXPORT CSV
# ============================================================
proc do_export_csv {} {
    set class [ask_input "Export CSV Report" "Enter Class Name:"]
    if {$class eq ""} return

    if {[catch {set data [load_report_data $class]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students $d(students)
    array set absent $d(absent)
    set total $d(total)

    set outfile "report_${class}.csv"
    set fh [open $outfile w]
    puts $fh "Roll,Name,Total Period of Present,Total Period,Percentage,Status"
    foreach s $students {
        set roll [lindex $s 0]
        set name [lindex $s 1]
        if {$roll eq ""} continue
        set present [expr {$total - $absent($roll)}]
        set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
        set status  [expr {$pct < 75 ? "BELOW 75" : "OK"}]
        puts $fh [format "%s,%s,%d,%d,%.2f,%s" $roll $name $present $total $pct $status]
    }
    close $fh
    msg_box "Success" "CSV report saved:\n[file nativename [file join [pwd] $outfile]]"
}

# ============================================================
# 7. DEFAULTER LIST
# ============================================================
proc do_defaulters {} {
    global C
    set class [ask_input "Defaulter List" "Enter Class Name:"]
    if {$class eq ""} return

    if {[catch {set data [load_report_data $class]} err]} {
        msg_box "Error" $err error; return
    }
    array set d $data
    set students $d(students)
    array set absent $d(absent)
    set total $d(total)

    set hdr [format "  %-12s %-28s %-12s" "Roll" "Name" "Attendance %"]
    set w [make_list_window "Defaulter List (<75%) — $class  (Total Periods: $total)" $hdr]
    $w.topbar.t configure -foreground $C(red)

    set count 0
    foreach s $students {
        set roll [lindex $s 0]
        set name [lindex $s 1]
        if {$roll eq ""} continue
        set present [expr {$total - $absent($roll)}]
        set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
        if {$pct < 75} {
            $w.lf.lb insert end [format "  %-12s %-28s %.2f%%" $roll $name $pct]
            $w.lf.lb itemconfigure end -foreground $C(red)
            incr count
        }
    }
    if {$count == 0} {
        $w.lf.lb insert end "  No defaulters — all students are above 75%."
        $w.lf.lb itemconfigure end -foreground $C(green)
    }

    label $w.cnt -text "Total Defaulters: $count student(s)" -font {Arial 12} \
        -background $C(bg) -foreground $C(dim)
    pack $w.cnt -before $w.close -pady {0 4}
}

# ============================================================
# 8. SEARCH STUDENT
# ============================================================
proc do_search_student {} {
    global C
    set class [ask_input "Search Student" "Enter Class Name:"]
    if {$class eq ""} return

    set roll [ask_input "Search Student" "Enter Roll Number:"]
    if {$roll eq ""} return

    set sf "students_${class}.txt"
    set af "attendance_${class}.txt"
    if {![file exists $sf] || ![file exists $af]} {
        msg_box "Error" "Class '$class' not found." error; return
    }

    array set absent {}
    set found_name ""
    set fh [open $sf r]
    foreach line [split [read $fh] \n] {
        set line [string trim $line]
        if {$line eq ""} continue
        set r [lindex $line 0]
        set n [lrange $line 1 end]
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
        set cols [lrange [split $line] 1 end]
        incr total
        foreach r $cols {
            if {[info exists absent($r)]} { incr absent($r) }
        }
    }
    close $fh

    set present [expr {$total - $absent($roll)}]
    set pct     [expr {$total > 0 ? ($present * 100.0 / $total) : 0.0}]
    set status  [expr {$pct < 75 ? "BELOW 75%  (Defaulter)" : "OK"}]
    set pct_str [format "%.2f%%" $pct]
    set sc      [expr {$pct < 75 ? $C(red) : $C(green)}]

    set w .__sr[clock milliseconds]
    toplevel $w
    wm title     $w "Student Report — $roll"
    wm resizable $w 1 1
    wm state     $w zoomed
    $w configure -background $C(bg)

    # center a card frame on the maximized window
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
        [list "Present"       $present    $C(fg)] \
        [list "Total Periods" $total      $C(fg)] \
        [list "Percentage"    $pct_str    $C(fg)] \
        [list "Status"        $status     $sc   ] \
    ] {
        set key [lindex $pair 0]
        set val [lindex $pair 1]
        set col [lindex $pair 2]

        frame $w.card.r$rownum -background $C(bg2)
        pack  $w.card.r$rownum -fill x -pady 4

        label $w.card.r$rownum.k -text "$key :" -font {Arial 13 bold} \
            -width 18 -anchor w -background $C(bg2) -foreground $C(dim)
        label $w.card.r$rownum.v -text $val -font {Arial 14} \
            -anchor w -background $C(bg2) -foreground $col
        pack $w.card.r$rownum.k $w.card.r$rownum.v -side left -padx 4
        incr rownum
    }

    button $w.card.close -text "Close" -width 18 -font {Arial 12 bold} \
        -background $C(exit) -foreground $C(fg) \
        -activebackground $C(exitact) -activeforeground $C(fg) \
        -relief flat -cursor hand2 -command [list destroy $w]
    pack $w.card.close -pady {22 0} -ipady 10
}
