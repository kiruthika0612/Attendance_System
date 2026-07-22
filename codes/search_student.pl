sub search_student
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    print "Enter Roll Number: ";
    chomp(my $search = <STDIN>);

    my $student_file    = "students_$class.txt";
    my $attendance_file = "attendance_$class.txt";

    my %absent;
    my $name = "";

    open(my $sfh, "<", $student_file) or die "Cannot open file";

    while (my $line = <$sfh>)
    {
        chomp($line);
        my ($roll, $n) = split(' ', $line, 2);

        if ($roll eq $search)
        {
            $name = $n;
        }

        $absent{$roll} = 0;
    }

    close($sfh);

    open(my $afh, "<", $attendance_file) or die "Cannot open file";

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

    if ($name eq "")
    {
        print "\nStudent not found!\n";
        return;
    }

    my $present = $total - $absent{$search};
    my $percentage = ($total > 0) ? ($present/$total)*100 : 0;

    print "\n===== STUDENT REPORT =====\n";
    print "Roll No   : $search\n";
    print "Name      : $name\n";
    print "Present   : $present\n";
    print "Total     : $total\n";
    printf "Percent   : %.2f%%\n", $percentage;
}

1;