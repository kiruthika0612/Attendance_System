sub view_report
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    my $student_file    = "students_$class.txt";
    my $attendance_file = "attendance_$class.txt";

    my %absent;
    my @students;

    # -------------------------
    # COLOR CODES
    # -------------------------
    my $RED   = "\e[31m";
    my $GREEN = "\e[32m";
    my $RESET = "\e[0m";

    # -------------------------
    # READ STUDENT FILE
    # -------------------------
    open(my $sfh, "<", $student_file)
        or die "Cannot open $student_file: $!";

    while (my $line = <$sfh>)
    {
        chomp($line);
        next if $line eq "";

        my ($roll, $name) = split(' ', $line, 2);

        push @students, [$roll, $name];
        $absent{$roll} = 0;
    }

    close($sfh);

    # -------------------------
    # READ ATTENDANCE FILE
    # -------------------------
    open(my $afh, "<", $attendance_file)
        or die "Cannot open $attendance_file: $!";

    my $total_periods = 0;

    while (my $line = <$afh>)
    {
        chomp($line);
        next if $line eq "";

        my @data = split(' ', $line);
        shift @data;   # remove date

        $total_periods++;

        foreach my $roll (@data)
        {
            if (exists $absent{$roll})
            {
                $absent{$roll}++;
            }
        }
    }

    close($afh);

    # -------------------------
    # HEADER
    # -------------------------
    printf "\n%-10s %-25s %-25s %-15s %-12s %-15s\n",
           "Roll",
           "Name",
           "Total Period of Present",
           "Total Period",
           "Percentage",
           "Status";

    print "----------------------------------------------------------------------------------------------\n";

    # -------------------------
    # DATA ROWS
    # -------------------------
    foreach my $s (@students)
    {
        my ($roll, $name) = @$s;

        my $present = $total_periods - $absent{$roll};

        my $percentage = 0;
        if ($total_periods > 0)
        {
            $percentage = ($present / $total_periods) * 100;
        }

        my $status;

        if ($percentage < 75)
        {
            $status = $RED . "BELOW 75%" . $RESET;
        }
        else
        {
            $status = $GREEN . "OK" . $RESET;
        }

        printf "%-10s %-25s %-25d %-15d %-12.2f %-15s\n",
               $roll,
               $name,
               $present,
               $total_periods,
               $percentage,
               $status;
    }
}

1;