sub mark_attendance
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    my $attendance_file = "attendance_$class.txt";

    print "Enter Date (YYYY-MM-DD): ";
    chomp(my $date = <STDIN>);

    print "Enter absent roll numbers separated by space: ";
    chomp(my $absent = <STDIN>);

    open(my $fh, ">>", $attendance_file)
        or die "Cannot open $attendance_file: $!";

    print $fh "$date $absent\n";

    close($fh);

    print "\nAttendance marked successfully.\n";
}

1;