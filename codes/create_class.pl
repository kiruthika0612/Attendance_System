sub create_class
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    my $student_file = "students_$class.txt";
    my $attendance_file = "attendance_$class.txt";

    open(my $sfh, ">>", $student_file)
        or die "Cannot create file";

    close($sfh);

    open(my $afh, ">>", $attendance_file)
        or die "Cannot create file";

    close($afh);

    print "\nClass $class created successfully.\n";
}

1;