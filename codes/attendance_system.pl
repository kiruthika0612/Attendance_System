use strict;
use warnings;

require "./create_class.pl";
require "./add_student.pl";
require "./view_students.pl";
require "./mark_attendance.pl";
require "./view_report.pl";
require "./export_report.pl";
require "./defaulters_list.pl";
require "./search_student.pl";

while (1)
{
    print "\n===== ATTENDANCE MANAGEMENT SYSTEM =====\n";
    print "1. Create Class\n";
    print "2. Add Student\n";
    print "3. View Students\n";
    print "4. Mark Attendance\n";
    print "5. View Report\n";
    print "6. Export CSV Report\n";
    print "7. Defaulter List\n";
    print "8. Search Student\n";
    print "9. Exit\n";

    print "\nEnter choice: ";
    chomp(my $choice = <STDIN>);

    if ($choice == 1)
    {
        create_class();
    }
    elsif ($choice == 2)
    {
        add_student();
    }
    elsif ($choice == 3)
    {
        view_students();
    }
    elsif ($choice == 4)
    {
        mark_attendance();
    }
   elsif ($choice == 5)
{
    view_report();
}
elsif ($choice == 6)
{
    export_report();
}
elsif ($choice == 7)
{
    defaulters_list();
}
elsif ($choice == 8)
{
    search_student();
}
elsif ($choice == 9)
{
    last;
}
    else
    {
        print "\nInvalid choice!\n";
    }
}