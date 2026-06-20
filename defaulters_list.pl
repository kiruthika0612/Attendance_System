sub defaulters_list
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    my $student_file    = "students_$class.txt";
    my $attendance_file = "attendance_$class.txt";

    my %absent;
    my @students;

    open(my $sfh, "<", $student_file) or die "Cannot open file";

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

    print "\n===== DEFAULTER LIST (<75%) =====\n";

    foreach my $s (@students)
    {
        my ($roll, $name) = @$s;

        my $present = $total - $absent{$roll};
        my $percentage = ($total > 0) ? ($present/$total)*100 : 0;

        if ($percentage < 75)
        {
            printf "%-10s %-25s %.2f%%\n", $roll, $name, $percentage;
        }
    }
}

1;