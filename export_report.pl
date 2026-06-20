sub export_report
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    my $student_file    = "students_$class.txt";
    my $attendance_file = "attendance_$class.txt";

    my $output_file = "report_$class.csv";

    my %absent;
    my @students;

    # READ STUDENTS
    open(my $sfh, "<", $student_file) or die "Cannot open $student_file";

    while (my $line = <$sfh>)
    {
        chomp($line);
        next if $line eq "";

        my ($roll, $name) = split(' ', $line, 2);
        next if $roll !~ /^\d+$/;

        push @students, [$roll, $name];
        $absent{$roll} = 0;
    }

    close($sfh);

    # READ ATTENDANCE
    open(my $afh, "<", $attendance_file) or die "Cannot open $attendance_file";

    my $total = 0;

    while (my $line = <$afh>)
    {
        chomp($line);
        my @data = split(' ', $line);
        shift @data;

        $total++;

        foreach my $r (@data)
        {
            $absent{$r}++ if exists $absent{$r};
        }
    }

    close($afh);

    # WRITE CSV
    open(my $out, ">", $output_file) or die "Cannot create CSV file";

    print $out "Roll,Name,Total Period of Present,Total Period,Percentage,Status\n";
    foreach my $s (@students)
    {
        my ($roll, $name) = @$s;

        my $present = $total - $absent{$roll};
        my $percentage = ($total > 0) ? ($present/$total)*100 : 0;
        my $status = ($percentage < 75) ? "BELOW 75" : "OK";

        print $out "$roll,$name,$present,$total,$percentage,$status\n";
    }

    close($out);

    print "\nCSV Report created: report_$class.csv\n";
}

1;