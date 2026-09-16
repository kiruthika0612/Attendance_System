sub view_students
{
    print "\nEnter Class Name: ";
    chomp(my $class = <STDIN>);

    my $student_file = "students_$class.txt";

    open(my $fh, "<", $student_file)
        or die "Class not found";

    print "\n===== STUDENT LIST =====\n";

    while(my $line = <$fh>)
    {
        print $line;
    }

    close($fh);
}

1;