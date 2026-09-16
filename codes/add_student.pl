sub add_student
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    my $student_file = "students_$class.txt";

    print "\nChoose option:\n";
    print "1. Add Single Student\n";
    print "2. Import from File\n";
    print "Enter choice: ";

    chomp(my $opt = <STDIN>);

    # -------------------------
    # SINGLE STUDENT
    # -------------------------
    if ($opt == 1)
    {
        print "Enter Roll Number: ";
        chomp(my $roll = <STDIN>);

        print "Enter Name: ";
        chomp(my $name = <STDIN>);

        open(my $fh, ">>", $student_file)
            or die "Cannot open file";

        print $fh "$roll $name\n";
        close($fh);

        print "\nStudent added successfully.\n";
    }

    # -------------------------
    # BULK IMPORT
    # -------------------------
    elsif ($opt == 2)
    {
        my $input_file = "${class}_list.txt";

        open(my $in, "<", $input_file)
            or die "Cannot open $input_file";

        open(my $out, ">", $student_file)
            or die "Cannot create $student_file";

        while (my $line = <$in>)
        {
            print $out $line;
        }

        close($in);
        close($out);

        print "\nBulk import successful.\n";
    }

    else
    {
        print "\nInvalid option!\n";
    }
}

1;