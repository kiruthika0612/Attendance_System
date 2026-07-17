#!/usr/bin/perl
use strict;
use warnings;
use Win32::GUI ();

# ============================================================
# ATTENDANCE MANAGEMENT SYSTEM  -  GUI VERSION
# Toolkit : Win32::GUI (native Windows controls)
# Logic   : identical to the original CLI modules
# Data    : students_CLASS.txt  /  attendance_CLASS.txt
# ============================================================

# ---- fonts ----
my $FNT_TITLE = Win32::GUI::Font->new(-name=>"Arial",-size=>13,-bold=>1);
my $FNT_BTN   = Win32::GUI::Font->new(-name=>"Arial",-size=>10,-bold=>1);
my $FNT_NORM  = Win32::GUI::Font->new(-name=>"Arial",-size=>10);
my $FNT_MONO  = Win32::GUI::Font->new(-name=>"Courier New",-size=>9);

# ==============================================================
# BUSINESS LOGIC HELPERS  (same as original .pl modules)
# ==============================================================

sub _load_report_data {
    my ($class) = @_;
    my $sf = "students_$class.txt";
    my $af = "attendance_$class.txt";
    return (undef, "Class '$class' not found (missing $sf).") unless -e $sf && -e $af;

    my (%absent, @students);
    open my $sfh, "<", $sf or return (undef, "Cannot open $sf");
    while (<$sfh>) {
        chomp; next if /^\s*$/;
        my ($roll, $name) = split ' ', $_, 2;
        push @students, [$roll, $name];
        $absent{$roll} = 0;
    }
    close $sfh;

    open my $afh, "<", $af or return (undef, "Cannot open $af");
    my $total = 0;
    while (<$afh>) {
        chomp; next if /^\s*$/;
        my @cols = split ' ', $_;
        shift @cols;
        $total++;
        $absent{$_}++ for grep { exists $absent{$_} } @cols;
    }
    close $afh;

    return ({ students=>\@students, absent=>\%absent, total=>$total }, undef);
}

# ==============================================================
# SIMPLE INPUT DIALOG  (returns entered string or undef)
# ==============================================================
sub _ask {
    my ($owner, $title, $prompt) = @_;

    my $W = Win32::GUI::DialogBox->new(
        -owner   => $owner,
        -title   => $title,
        -width   => 370, -height => 145,
        -resizable => 0,
    );
    $W->AddLabel(-text=>$prompt, -font=>$FNT_NORM,
                 -left=>12,-top=>14,-width=>340,-height=>20);
    my $tf = $W->AddTextfield(-font=>$FNT_NORM,
                 -left=>12,-top=>40,-width=>336,-height=>24,-name=>"tf");
    $W->AddButton(-text=>"OK",    -font=>$FNT_BTN,
                 -left=>75, -top=>76,-width=>90,-height=>28,-name=>"ok");
    $W->AddButton(-text=>"Cancel",-font=>$FNT_BTN,
                 -left=>195,-top=>76,-width=>90,-height=>28,-name=>"cancel");

    my $result;
    $W->ok_Click(sub     { $result = $tf->Text; $result=~s/^\s+|\s+$//g; $W->EndDialog(1); 1 });
    $W->cancel_Click(sub { $W->EndDialog(0); 1 });
    $W->tf_KeyDown(sub   {
        if ($_[0] == 0x0D) { $result = $tf->Text; $result=~s/^\s+|\s+$//g; $W->EndDialog(1); }
        return 1;
    });

    my $ret = $W->DialogBox();
    return ($ret == 1) ? $result : undef;
}

# ==============================================================
# MAIN WINDOW
# ==============================================================
my $MW = Win32::GUI::Window->new(
    -title      => "Attendance Management System",
    -left       => 350, -top => 150,
    -width      => 520, -height => 440,
    -resizable  => 0,
    -maximizebox=> 0,
);

$MW->AddLabel(
    -text  => "ATTENDANCE MANAGEMENT SYSTEM",
    -font  => $FNT_TITLE,
    -left  => 60, -top => 22,
    -width => 400, -height => 28,
);
$MW->AddLabel(
    -text  => "Select a function from the buttons below:",
    -font  => $FNT_NORM,
    -left  => 100, -top => 56,
    -width => 310, -height => 18,
);

# ---- layout buttons 2 per row ----
my @BTN_DEFS = (
    ["1. Create Class",      "btn_cc"],
    ["2. Add Student",       "btn_as"],
    ["3. View Students",     "btn_vs"],
    ["4. Mark Attendance",   "btn_ma"],
    ["5. View Report",       "btn_vr"],
    ["6. Export CSV",        "btn_ex"],
    ["7. Defaulter List",    "btn_dl"],
    ["8. Search Student",    "btn_ss"],
);

my ($col, $row_y) = (0, 90);
for my $def (@BTN_DEFS) {
    $MW->AddButton(
        -text   => $def->[0],
        -name   => $def->[1],
        -font   => $FNT_BTN,
        -left   => ($col == 0) ? 60 : 280,
        -top    => $row_y,
        -width  => 175,
        -height => 34,
    );
    $col++;
    if ($col == 2) { $col = 0; $row_y += 46; }
}

$MW->AddButton(
    -text   => "Exit",
    -name   => "btn_exit",
    -font   => $FNT_BTN,
    -left   => 160, -top  => $row_y + 12,
    -width  => 175, -height => 34,
);

# ==============================================================
# BUTTON HANDLERS
# ==============================================================

$MW->btn_cc_Click(sub { _do_create_class(); 1 });
$MW->btn_as_Click(sub { _do_add_student();  1 });
$MW->btn_vs_Click(sub { _do_view_students();  1 });
$MW->btn_ma_Click(sub { _do_mark_attendance(); 1 });
$MW->btn_vr_Click(sub { _do_view_report();    1 });
$MW->btn_ex_Click(sub { _do_export_csv();     1 });
$MW->btn_dl_Click(sub { _do_defaulters();     1 });
$MW->btn_ss_Click(sub { _do_search_student(); 1 });
$MW->btn_exit_Click(sub { $MW->Hide(); -1 });
$MW->Hook(WM_DESTROY => sub { Win32::GUI::DoEvents(); -1 });

# ==============================================================
# 1. CREATE CLASS
# ==============================================================
sub _do_create_class {
    my $class = _ask($MW, "Create Class", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    for my $f ("students_$class.txt", "attendance_$class.txt") {
        unless (-e $f) {
            open(my $fh,">>", $f) or do {
                Win32::GUI::MessageBox($MW,"Cannot create $f","Error",0); return;
            };
            close $fh;
        }
    }
    Win32::GUI::MessageBox($MW, "Class '$class' created successfully.", "Success", 0);
}

# ==============================================================
# 2. ADD STUDENT
# ==============================================================
sub _do_add_student {
    my $class = _ask($MW, "Add Student", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    my $sf = "students_$class.txt";
    unless (-e $sf) {
        Win32::GUI::MessageBox($MW,"Class '$class' not found.","Error",0); return;
    }

    # Option dialog
    my $OD = Win32::GUI::DialogBox->new(
        -owner  => $MW, -title => "Add Student - $class",
        -width  => 320, -height => 160, -resizable => 0,
    );
    $OD->AddLabel(-text=>"Choose option:",-font=>$FNT_BTN,
        -left=>20,-top=>16,-width=>260,-height=>20);
    $OD->AddButton(-text=>"Add Single Student",-font=>$FNT_BTN,
        -left=>40,-top=>46,-width=>200,-height=>30,-name=>"single");
    $OD->AddButton(-text=>"Import from File",-font=>$FNT_BTN,
        -left=>40,-top=>86,-width=>200,-height=>30,-name=>"bulk");

    my $choice = 0;
    $OD->single_Click(sub { $choice=1; $OD->EndDialog(1); 1 });
    $OD->bulk_Click(sub   { $choice=2; $OD->EndDialog(1); 1 });
    $OD->DialogBox();

    if ($choice == 1) {
        # Single student sub-dialog
        my $AD = Win32::GUI::DialogBox->new(
            -owner => $MW, -title => "Add Single Student",
            -width => 370, -height => 200, -resizable => 0,
        );
        $AD->AddLabel(-text=>"Roll Number:",-font=>$FNT_NORM,
            -left=>12,-top=>16,-width=>200,-height=>18);
        my $tf_roll = $AD->AddTextfield(-font=>$FNT_NORM,
            -left=>12,-top=>38,-width=>336,-height=>24,-name=>"tf_roll");
        $AD->AddLabel(-text=>"Name:",-font=>$FNT_NORM,
            -left=>12,-top=>72,-width=>200,-height=>18);
        my $tf_name = $AD->AddTextfield(-font=>$FNT_NORM,
            -left=>12,-top=>94,-width=>336,-height=>24,-name=>"tf_name");
        $AD->AddButton(-text=>"Add",-font=>$FNT_BTN,
            -left=>70,-top=>132,-width=>90,-height=>28,-name=>"add");
        $AD->AddButton(-text=>"Cancel",-font=>$FNT_BTN,
            -left=>200,-top=>132,-width=>90,-height=>28,-name=>"cancel");

        $AD->add_Click(sub {
            my $roll = $tf_roll->Text; $roll =~ s/^\s+|\s+$//g;
            my $name = $tf_name->Text; $name =~ s/^\s+|\s+$//g;
            if ($roll eq "" || $name eq "") {
                Win32::GUI::MessageBox($AD,"Roll and Name cannot be empty.","Error",0);
                return 1;
            }
            open(my $fh,">>","students_$class.txt") or do {
                Win32::GUI::MessageBox($AD,"Cannot open file.","Error",0); return 1;
            };
            print $fh "$roll $name\n";
            close $fh;
            Win32::GUI::MessageBox($AD,"Student added successfully.","Success",0);
            $AD->EndDialog(1);
            1;
        });
        $AD->cancel_Click(sub { $AD->EndDialog(0); 1 });
        $AD->DialogBox();

    } elsif ($choice == 2) {
        my $input_file = "${class}_list.txt";
        unless (-e $input_file) {
            Win32::GUI::MessageBox($MW,
                "Import file '$input_file' not found.\n\nCreate a file named '$input_file' with lines:\n  ROLL NAME",
                "Error", 0);
            return;
        }
        open my $in,  "<", $input_file  or do { Win32::GUI::MessageBox($MW,"Cannot read $input_file","Error",0); return; };
        open my $out, ">", $sf          or do { close $in; Win32::GUI::MessageBox($MW,"Cannot write $sf","Error",0); return; };
        print $out $_ while <$in>;
        close $in; close $out;
        Win32::GUI::MessageBox($MW,"Bulk import from '$input_file' successful.","Success",0);
    }
}

# ==============================================================
# 3. VIEW STUDENTS
# ==============================================================
sub _do_view_students {
    my $class = _ask($MW, "View Students", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    my $sf = "students_$class.txt";
    unless (-e $sf) { Win32::GUI::MessageBox($MW,"Class '$class' not found.","Error",0); return; }

    open my $fh, "<", $sf or do { Win32::GUI::MessageBox($MW,"Cannot open file.","Error",0); return; };
    my @lines = <$fh>; close $fh;

    my $W = Win32::GUI::DialogBox->new(
        -owner  => $MW, -title => "Student List - $class",
        -width  => 480, -height => 420, -resizable => 0,
    );
    $W->AddLabel(-text=>"Student List — $class", -font=>$FNT_TITLE,
        -left=>14,-top=>12,-width=>440,-height=>24);
    $W->AddLabel(-text=>"  Roll No          Name", -font=>$FNT_MONO,
        -left=>14,-top=>42,-width=>440,-height=>18);

    my $lb = $W->AddListbox(
        -font        => $FNT_MONO,
        -left        => 14, -top   => 62,
        -width       => 436, -height => 286,
        -name        => "lb",
        -vscroll     => 1,
    );

    my $count = 0;
    for my $line (@lines) {
        chomp $line; next if $line =~ /^\s*$/;
        my ($roll,$name) = split ' ',$line,2;
        $lb->AddString(sprintf("  %-14s  %s", $roll, $name));
        $count++;
    }
    $lb->AddString("  (No students found)") if $count == 0;

    $W->AddLabel(-text=>"Total: $count student(s)", -font=>$FNT_NORM,
        -left=>14,-top=>354,-width=>220,-height=>18);
    $W->AddButton(-text=>"Close",-font=>$FNT_BTN,
        -left=>330,-top=>350,-width=>100,-height=>28,-name=>"close");
    $W->close_Click(sub { $W->EndDialog(0); 1 });
    $W->DialogBox();
}

# ==============================================================
# 4. MARK ATTENDANCE
# ==============================================================
sub _do_mark_attendance {
    my $class = _ask($MW, "Mark Attendance", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    my $af = "attendance_$class.txt";
    unless (-e $af) { Win32::GUI::MessageBox($MW,"Class '$class' not found.","Error",0); return; }

    my $W = Win32::GUI::DialogBox->new(
        -owner => $MW, -title => "Mark Attendance - $class",
        -width => 400, -height => 210, -resizable => 0,
    );
    $W->AddLabel(-text=>"Date (YYYY-MM-DD):", -font=>$FNT_NORM,
        -left=>12,-top=>16,-width=>360,-height=>18);
    my $tf_date = $W->AddTextfield(-font=>$FNT_NORM,
        -left=>12,-top=>38,-width=>360,-height=>24,-name=>"tf_date");
    $W->AddLabel(-text=>"Absent Roll Numbers (space-separated):", -font=>$FNT_NORM,
        -left=>12,-top=>72,-width=>360,-height=>18);
    my $tf_abs = $W->AddTextfield(-font=>$FNT_NORM,
        -left=>12,-top=>94,-width=>360,-height=>24,-name=>"tf_abs");
    $W->AddButton(-text=>"Mark Attendance",-font=>$FNT_BTN,
        -left=>50,-top=>134,-width=>140,-height=>28,-name=>"ok");
    $W->AddButton(-text=>"Cancel",-font=>$FNT_BTN,
        -left=>210,-top=>134,-width=>100,-height=>28,-name=>"cancel");

    $W->ok_Click(sub {
        my $date = $tf_date->Text; $date =~ s/^\s+|\s+$//g;
        my $abs  = $tf_abs->Text;  $abs  =~ s/^\s+|\s+$//g;
        if ($date eq "") { Win32::GUI::MessageBox($W,"Date cannot be empty.","Error",0); return 1; }
        unless ($date =~ /^\d{4}-\d{2}-\d{2}$/) {
            Win32::GUI::MessageBox($W,"Date must be YYYY-MM-DD.","Error",0); return 1;
        }
        open my $fh, ">>", "attendance_$class.txt" or do {
            Win32::GUI::MessageBox($W,"Cannot open attendance file.","Error",0); return 1;
        };
        print $fh "$date $abs\n";
        close $fh;
        Win32::GUI::MessageBox($W,"Attendance marked for $date.","Success",0);
        $W->EndDialog(1);
        1;
    });
    $W->cancel_Click(sub { $W->EndDialog(0); 1 });
    $W->DialogBox();
}

# ==============================================================
# 5. VIEW REPORT
# ==============================================================
sub _do_view_report {
    my $class = _ask($MW, "View Report", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    my ($data, $err) = _load_report_data($class);
    if ($err) { Win32::GUI::MessageBox($MW,$err,"Error",0); return; }

    my @students = @{$data->{students}};
    my %absent   = %{$data->{absent}};
    my $total    = $data->{total};

    my $W = Win32::GUI::DialogBox->new(
        -owner => $MW, -title => "Attendance Report - $class",
        -width => 680, -height => 460, -resizable => 0,
    );
    $W->AddLabel(-text=>"Attendance Report — $class  (Total Periods: $total)",
        -font=>$FNT_TITLE,-left=>14,-top=>12,-width=>640,-height=>24);

    # Column headers
    $W->AddLabel(-text=>sprintf("  %-10s %-22s %-9s %-8s %-10s %-12s",
        "Roll","Name","Present","Total","Percent","Status"),
        -font=>$FNT_MONO,-left=>14,-top=>42,-width=>640,-height=>18);

    my $lb = $W->AddListbox(
        -font    => $FNT_MONO,
        -left    => 14, -top => 62,
        -width   => 644, -height => 318,
        -name    => "lb",
        -vscroll => 1,
    );

    foreach my $s (@students) {
        my ($roll,$name) = @$s;
        my $present  = $total - $absent{$roll};
        my $pct      = $total > 0 ? ($present/$total)*100 : 0;
        my $status   = $pct < 75 ? "BELOW 75%" : "OK";
        $lb->AddString(sprintf("  %-10s %-22s %-9d %-8d %-10.2f %-12s",
            $roll, $name, $present, $total, $pct, $status));
    }
    $lb->AddString("  (No students found)") unless @students;

    $W->AddButton(-text=>"Close",-font=>$FNT_BTN,
        -left=>280,-top=>388,-width=>100,-height=>28,-name=>"close");
    $W->close_Click(sub { $W->EndDialog(0); 1 });
    $W->DialogBox();
}

# ==============================================================
# 6. EXPORT CSV REPORT
# ==============================================================
sub _do_export_csv {
    my $class = _ask($MW, "Export CSV Report", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    my ($data, $err) = _load_report_data($class);
    if ($err) { Win32::GUI::MessageBox($MW,$err,"Error",0); return; }

    my @students = @{$data->{students}};
    my %absent   = %{$data->{absent}};
    my $total    = $data->{total};
    my $outfile  = "report_$class.csv";

    open my $fh, ">", $outfile or do {
        Win32::GUI::MessageBox($MW,"Cannot create CSV file.","Error",0); return;
    };
    print $fh "Roll,Name,Total Period of Present,Total Period,Percentage,Status\n";
    foreach my $s (@students) {
        my ($roll,$name) = @$s;
        next unless $roll =~ /\S/;
        my $present = $total - $absent{$roll};
        my $pct     = $total > 0 ? ($present/$total)*100 : 0;
        my $status  = $pct < 75 ? "BELOW 75" : "OK";
        print $fh "$roll,$name,$present,$total,$pct,$status\n";
    }
    close $fh;
    Win32::GUI::MessageBox($MW,"CSV report saved as:\n$outfile","Success",0);
}

# ==============================================================
# 7. DEFAULTER LIST
# ==============================================================
sub _do_defaulters {
    my $class = _ask($MW, "Defaulter List", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    my ($data, $err) = _load_report_data($class);
    if ($err) { Win32::GUI::MessageBox($MW,$err,"Error",0); return; }

    my @students = @{$data->{students}};
    my %absent   = %{$data->{absent}};
    my $total    = $data->{total};

    my $W = Win32::GUI::DialogBox->new(
        -owner => $MW, -title => "Defaulter List (<75%) - $class",
        -width => 500, -height => 420, -resizable => 0,
    );
    $W->AddLabel(-text=>"Defaulter List (<75%) — $class  (Total Periods: $total)",
        -font=>$FNT_TITLE,-left=>14,-top=>12,-width=>464,-height=>24);
    $W->AddLabel(-text=>sprintf("  %-10s %-24s %-10s","Roll","Name","Percent"),
        -font=>$FNT_MONO,-left=>14,-top=>42,-width=>460,-height=>18);

    my $lb = $W->AddListbox(
        -font    => $FNT_MONO,
        -left    => 14, -top => 62,
        -width   => 464, -height => 288,
        -name    => "lb",
        -vscroll => 1,
    );

    my $count = 0;
    foreach my $s (@students) {
        my ($roll,$name) = @$s;
        next if $roll !~ /\S/;
        my $present = $total - $absent{$roll};
        my $pct     = $total > 0 ? ($present/$total)*100 : 0;
        if ($pct < 75) {
            $lb->AddString(sprintf("  %-10s %-24s %.2f%%", $roll, $name, $pct));
            $count++;
        }
    }
    $lb->AddString("  No defaulters found.") if $count == 0;

    $W->AddLabel(-text=>"Defaulters: $count student(s)",-font=>$FNT_NORM,
        -left=>14,-top=>358,-width=>220,-height=>18);
    $W->AddButton(-text=>"Close",-font=>$FNT_BTN,
        -left=>360,-top=>354,-width=>100,-height=>28,-name=>"close");
    $W->close_Click(sub { $W->EndDialog(0); 1 });
    $W->DialogBox();
}

# ==============================================================
# 8. SEARCH STUDENT
# ==============================================================
sub _do_search_student {
    my $class = _ask($MW, "Search Student", "Enter Class Name:");
    return unless defined $class && $class =~ /\S/;

    my $roll = _ask($MW, "Search Student", "Enter Roll Number:");
    return unless defined $roll && $roll =~ /\S/;

    my $sf = "students_$class.txt";
    my $af = "attendance_$class.txt";
    unless (-e $sf && -e $af) {
        Win32::GUI::MessageBox($MW,"Class '$class' not found.","Error",0); return;
    }

    my (%absent, $name);
    open my $sfh, "<", $sf or do { Win32::GUI::MessageBox($MW,"Cannot open student file.","Error",0); return; };
    while (<$sfh>) {
        chomp;
        my ($r,$n) = split ' ',$_,2;
        $name = $n if defined $r && $r eq $roll;
        $absent{$r} = 0 if defined $r;
    }
    close $sfh;

    unless (defined $name) {
        Win32::GUI::MessageBox($MW,"Student roll '$roll' not found in class '$class'.","Not Found",0); return;
    }

    open my $afh, "<", $af or do { Win32::GUI::MessageBox($MW,"Cannot open attendance file.","Error",0); return; };
    my $total = 0;
    while (<$afh>) {
        chomp; next if /^\s*$/;
        my @cols = split ' ',$_;
        shift @cols;
        $total++;
        $absent{$_}++ for grep { exists $absent{$_} } @cols;
    }
    close $afh;

    my $present = $total - ($absent{$roll} // 0);
    my $pct     = $total > 0 ? ($present/$total)*100 : 0;
    my $status  = $pct < 75 ? "BELOW 75%  (Defaulter)" : "OK";

    my $W = Win32::GUI::DialogBox->new(
        -owner => $MW, -title => "Student Report - $roll",
        -width => 380, -height => 300, -resizable => 0,
    );
    $W->AddLabel(-text=>"Student Report", -font=>$FNT_TITLE,
        -left=>14,-top=>14,-width=>340,-height=>26);

    my @rows = (
        ["Roll Number",   $roll],
        ["Name",          $name],
        ["Class",         $class],
        ["Present",       $present],
        ["Total Periods", $total],
        ["Percentage",    sprintf("%.2f%%", $pct)],
        ["Status",        $status],
    );
    my $y = 50;
    for my $r (@rows) {
        $W->AddLabel(-text=>"$r->[0] :", -font=>$FNT_BTN,
            -left=>20,-top=>$y,-width=>130,-height=>20);
        $W->AddLabel(-text=>$r->[1], -font=>$FNT_NORM,
            -left=>160,-top=>$y,-width=>200,-height=>20);
        $y += 24;
    }

    $W->AddButton(-text=>"Close",-font=>$FNT_BTN,
        -left=>135,-top=>$y+8,-width=>100,-height=>28,-name=>"close");
    $W->close_Click(sub { $W->EndDialog(0); 1 });
    $W->DialogBox();
}

# ==============================================================
# START
# ==============================================================
$MW->Show();
Win32::GUI::Dialog();
