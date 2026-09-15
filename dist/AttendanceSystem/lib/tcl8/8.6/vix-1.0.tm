package require Tcl 8.6
package require twapi_com

namespace eval vix {
    variable package "vix"
    variable version 1.0
    variable _ruffdoc
    lappend _ruffdoc Introduction "
        This document describes V$version of the $package package.
        The package provides an interface to the VIX library for
        manipulating VMware virtual machines. The package uses
        the VIX COM interface and therefore only runs on Windows
        although the virtual machines themselves may run any
        operating system.
    " Prerequisites {
            The package has the following prerequisites:
        
        - Tcl 8.6
        - The 'twapi_com' package available from http://twapi.sf.net
        - The VMware VIX library. This is installed as part of
          the VMware Workstation product and is also available as a
          separate free download from VMware.
    } {Download and Installation} {
        The package is available from the 'Files' area of the SourceForge
        project at http://sourceforge.net/p/tcl-vix.

        It is distributed as a Tcl module 'vix-VERSION.tm'. Place this
        file anywhere in a directory included in the list of module directories
        searched by Tcl. Alternatively, install it with the command
            tclsh vix-VERSION.tm install ?TARGETDIR?
        If 'TARGETDIR' is not specified, it will install to a suitable
        directory in the module path.

    } Usage {
        Load the module
            package require vix

        All commands are placed within the 'vix' namespace.
        The package must be initialized before any other calls are made:
            vix::initialize
        
        This allocates internal resources required for further use of the
        package. Conversely, resources should be released when the package
        is not required:
            vix::finalize

        Note that all objects created using the Host and VM classes
        must be destroyed before calling finalize.

        These calls may be made multiple times in an application as long
        any other VIX calls are made after an initialize call without
        an intermediate finalize call.

        To manipulate a virtual machine, first connect to 
        the VMware host that contains it.
            vix::Host create host
        The above call will connect to a VMware Workstation host on the 
        local system. For connecting to other VMware products and
        remote systems, see the documentation for the Host class.

        Once connected to a host, we can obtain an object corresponding to
        a virtual machine:
            set vm [host open "c:/Virtual Machines/vm1-win8pro/vm1-win8pro.vmx"]
        The specified path may be a file path to the virtual machine's
        VMS file as in the case of VMware Workstation or a storage path
        as in the case of the ESX/ESXi products.

        You can open multiple virtual machines from a single Host object.
        All such VM objects must be destroyed before destroying
        the owning Host object.

        The above call returns a VM object which may then be used
        to manipulate the associated virtual machine using any of
        the methods of the VM class. For example,
            $vm power_on
        will power on the virtual machine. The supported methods
        include commands to manipulate system state, copy files to and
        from the virtual machine, start programs and so on.

        There are some additional important points to be noted about using
        these methods. See the documentation of the
        VM.wait_for_tools and VM.login for details.
        
        When no longer needed, the objects should be destroyed.
           $vm destroy
           host destroy
        Note that this does *not* change the state of the VMware host
        or the virtual machines themselves.
    }

    proc initialize {} {
        # Initializes the vix package
        #
        # This command initializes internal resources used for interfacing
        # to VMware hosts. It must be called before using any other commands
        # from the package.

        variable Vix
        
        if {![info exists Vix]} {
            set Vix [twapi::comobj VixCom.VixLib]
        }
        return
    }

    proc finalize {} {
        # Finalizes the vix package
        #
        # This command must be called after finishing with the use
        # of the vix package to release internal resources. Before
        # calling this command, all vix objects should have been destroyed.
        #
        # Once this command returns, the initialize command must be called
        # before the application makes use of the package again.
        variable Vix
        if {[info exists Vix]} {
            $Vix destroy
            unset Vix
        }
    }

    proc vix {} {
        variable Vix
        return $Vix
    }

    proc check_error {err} {
        variable Vix
        if {$err && [$Vix ErrorIndicatesFailure $err]} {
            set msg [$Vix GetErrorText $err [twapi::vt_empty]]
            return -level 1 -code error -errorcode [list VIX $err $msg] $msg
        }
    }

    proc check_path {path} {
        # Path must be absolute path. However, we allow volume-relative
        # since since guest may actually be *ix where volume-relative
        # really is absolute
        if {[file pathtype $path] eq "relative"} {
            return -level 1 -code error -errorcode [list VIX FILE NOTABSOLUTE] "File path $path is a relative file path."
        }
    }

    proc wait_for_result {job {propname VIX_PROPERTY_JOB_RESULT_HANDLE}} {
        twapi::trap {
            set results [twapi::vt_null]; # Must be init'ed
            set err [$job Wait [twapi::safearray i4 [list [$propname]]] results]
            check_error $err

            # $results is a safearray the first element of which
            # will contain the awaited result
            return [lindex [twapi::variant_value $results 0 0 0] 0]
        } finally {
            $job -destroy
        }
    }

    proc wait_for_results {job args} {
        twapi::trap {
            set values {}
            foreach propname $args {
                set results [twapi::vt_null]; # Must be init'ed
                set err [$job Wait [twapi::safearray i4 [$propname]] results]
                check_error $err
                # $results is a safearray the first element of which
                # will contain the awaited result
                lappend values [lindex [twapi::variant_value $results 0 0 0] 0]
            }
        } finally {
            $job -destroy
        }
        return $values
    }

    proc wait_for_completion {job {preserve 0}} {
        twapi::trap {
            set err [$job WaitWithoutResults]
            check_error $err
        } finally {
            if {! $preserve} {
                $job -destroy
            }
        }
        return
    }

    proc wait_for_properties {job args} {
        # args is list of property symbols
        # Returns nested list if more than one arg

        set props [lmap arg $args { $arg }]
        set values {}
        twapi::trap {
            wait_for_completion $job 1
            set count [$job GetNumProperties [lindex $props 0]]
            set proparr [twapi::safearray i4 $props]
            for {set i 0} {$i < $count} {incr i} {
                set results [twapi::vt_null]
                set err [$job GetNthProperties $i $proparr results]
                check_error $err
                if {[llength $props] == 1} {
                    lappend values [lindex [twapi::variant_value $results 0 0 0] 0]
                } else {
                    lappend values [twapi::variant_value $results 0 0 0]
                }
            }
        } finally {
            $job -destroy
        }

        return $values
    }

    proc pick {cond {a 1} {b 0}} {
        return [expr {$cond ? $a : $b}]
    }
}

oo::class create vix::_VixHandle {
    variable Ifc;            # Raw interface - retrieved when needed
    constructor {args} {
        next {*}$args

    }

    destructor {
        if {[info exists Ifc]} {
            twapi::IUnknown_Release $Ifc
        }
        next
        return
    }

    method _ifc {} {
        if {! [info exists Ifc]} {
            set ifc [[my wrappee] -interface 0]
            # Note we do NOT call IUnknown_Release on $ifc as
            # we did not incr ref count
            
            # {70AED194-6CFA-4BA3-8E63-D32A3573A171} -> IVixHandle IID
            set Ifc [::twapi::IUnknown_QueryInterface $ifc {{70AED194-6CFA-4BA3-8E63-D32A3573A171}}]
        }
        return $Ifc
    }

    method _type {} {
        set type [twapi::vixhandle_type [my _ifc]]
        set types {
            0 none   2 host   3 vm   5 network   6 job   7 snapshot
            9 property_list   11 metadata_container
        }
        if {[dict exist $types $type]} {
            return [dict get $types $type]
        } else {
            return $type
        }
    }

    method _properties {args} {
        set props {}
        set propids {}
        foreach prop $args {
            lappend propids [$prop]
        }
        lassign [twapi::vixhandle_properties [my _ifc] $propids] err results
        check_error $err
        return [twapi::variant_value $results 0 0 0]
    }

    method _get_property {propname} {
        return [lindex [my _properties $propname] 0]
    }
}

oo::class create vix::Host {
    variable Opts Host VMs NameCounter
    mixin vix::_VixHandle
    constructor args {
        # Class representing a host system running VMware software
        #
        # -hosttype HOSTTYPE - specifies the type of VMware host software.
        #   HOSTTYPE must be one of 'workstation' for VMware Workstation
        #   (default), 'workstation_server' for VMware Workstation in shared
        #   mode, 'server' for VMware Server 1.0, 'player' for VMware Player
        #   and 'vi_server' for VMware Server 2.0, vCenter and ESX/ESXi.
        # -hostname HOSTNAME - specifies the name of the host system. Defaults
        #   to the local system. Cannot be specified if HOSTTYPE is 
        #   'workstation' or 'player'. Must be specified in other cases.
        # -connect BOOLEAN - if true (default), automatically connects
        #   to the host. If false, caller must separately call the connect
        #   method.
        # -port PORTNUMBER - specifies the port number to connect to on the
        #   host. Ignored if -hostname is not specified.
        # -username USER - name of the account to use to connect to the host
        #   system. Ignored if -hostname is not specified.
        # -password PASSWORD - the password associated with the account.
        #   Ignored if -hostname is not specified.
        # The specified host is not contacted until the connect method
        # is invoked.

        namespace path [linsert [namespace path] end [namespace qualifiers [self class]]]
        array set Opts [twapi::parseargs args {
            {hosttype.arg workstation {workstation workstation_shared server vi_server player}}
            hostname.arg
            {port.int 0}
            username.arg
            password.arg
            {connect.bool 1}
            {sslverify.bool 1}
        } -maxleftover 0]

        if {[info exists Opts(hostname)]} {
            if {$Opts(hosttype) in {workstation player}} {
                twapi::badargs! "Option -hostname cannot be specified if -hosttype is 'workstation' or 'player'"
            }
            foreach opt {port username password} {
                if {![info exists Opts($opt)]} {
                    twapi::badargs! "If -hostname is specified,  -port, -username and -password must also be specified."
                }
            }
        } else {
            if {$Opts(hosttype) ni {workstation player}} {
                twapi::badargs! "Option -hostname must be specified if -hosttype is not 'workstation' or 'player'"
            }
            set Opts(hostname) [twapi::vt_empty]
            set Opts(username) [twapi::vt_empty]
            set Opts(password) [twapi::vt_empty]
        }

        set Opts(VIX_SERVICE_PROVIDER) [VIX_SERVICEPROVIDER_VMWARE_[string toupper $Opts(hosttype)]]

        if {$Opts(sslverify)} {
            set Opts(options) [VIX_HOSTOPTION_VERIFY_SSL_CERT]
        } else {
            set Opts(options) 0
        }

        if {$Opts(connect)} {
            my connect
        }
    }

    destructor {
        # Disconnects from the VMware host
        #
        # After destroying a Host object, the application should not
        # attempt to access related VM objects.

        my disconnect 1
        if {[info exists Host]} {
            $Host Disconnect
            $Host -destroy
        }
    }

    method wrappee {} {
        # Returns the underlying twapi::Automation COM object
        #
        # The method is used to retrieve the wrapped COM object
        # either for debugging purposes or to invoke VIX methods
        # that are not directly supported by this class.
        # IMPORTANT: The returned object must NOT be directly destroyed
        # by the caller and must not be accessed beyond the lifetime
        # of the wrapper object.
        #
        # The command will raise an error if there is no associated
        # wrapped COM object.
        return $Host
    }

    method connect {} {
        # Establishes a connection to the host system represented by this
        # object.
        #
        # This method must be called before any virtual machines
        # can be opened on the host system. The method may be called
        # multiple times with calls being no-ops if the connection is
        # already established.

        if {[info exists Host]} {
            return
        }
        set Host [wait_for_result    \
                      [[vix] Connect \
                           [VIX_API_VERSION] \
                           $Opts(VIX_SERVICE_PROVIDER) \
                           $Opts(hostname) $Opts(port) \
                           $Opts(username) $Opts(password) \
                           $Opts(options) 0 0]]
        return
    }

    method disconnect {{force 0}} {
        # Disconnects the object from the associated VMware host.
        #
        # force - if 0, an error is raised if any associated
        #   VM objects exist. If 1, the associated VM objects
        #   are forcibly destroyed before disconnecting.
        #
        # The application should normally ensure that all VM objects 
        # associated with this host have been closed before calling disconnect.
        #
        # The connect method may be called to reestablish the connection.

        if {![info exists Host]} {
            return
        }

        if {[array size VMs]} {
            if {! $force} {
                error "Cannot disconnect until all guest system objects are closed."
            }
            foreach guest [array names VMs] {
                catch {$guest destroy}
            }
        }

        $Host Disconnect
        $Host -destroy
        unset Host
    }

    method open {vm_path} {
        # Returns a VM object representing a virtual machine
        # on this VMware host
        #
        # vm_path - absolute path to the VMX file for the virtual machine
        #  on the VMware host. The path must be in the syntax expected
        #  by the VMware host operating system.
        #
        # The methods of the returned VM object may be used to interact with
        # the corresponding virtual machine.
        #
        # For VMware server and ESX/ESXi hosts, the virtual machine
        # must have been registered.

        set guest [VM create guest#[incr NameCounter] [wait_for_result [$Host OpenVM $vm_path 0]]]
        set VMs($guest) $vm_path
        trace add command $guest {rename delete} [list [self] trace_VM]
        return $guest
    }

    method register {vm_path} {
        # Registers a virtual machine with a VMware host
        #
        # vm_path - absolute path to the VMX file for the virtual machine
        #  on the VMware host. The path must be in the syntax expected
        #  by the VMware host operating system.
        #
        # For VMware Server and ESX/ESXi hosts, a virtual machine must be 
        # registered before it can be accessed with the open call.
        # For other VMware host types, this call is ignored.
        # Registration is a one-time operation and may also be done
        # through the VMware command line or user interface.

        wait_for_completion [$Host RegisterVM $vm_path 0]
    }

    method unregister {vm_path} {
        # Unregisters a virtual machine with a VMware host.
        #
        # vm_path - absolute path to the VMX file for the virtual machine
        #  on the VMware host. The path must be in the syntax expected
        #  by the VMware host operating system.
        #
        # For VMware Server and ESX/ESXi hosts, a virtual machine must be 
        # registered before it can be accessed with the open call. This
        # method removes a registered VM from the host inventory.

        wait_for_completion [$Host UnregisterVM $vm_path 0]
    }

    method running_vms {} {
        # Returns a list of virtual machines that are running on the host
        #
        # Each element of the returned list contains the path from
        # which the virtual machine was created.
        return [wait_for_properties [$Host FindItems [VIX_FIND_RUNNING_VMS] 0 -1 0] VIX_PROPERTY_FOUND_ITEM_LOCATION]
    }

    method registered_vms {} {
        # Returns a list of virtual machines that are registered on the host
        #
        # Each element of the returned list contains the path of the
        # registered virtual machine. This command is only relevant for
        # ESX/ESXi and VMware Server hosts.

        return [wait_for_properties [$Host FindItems [VIX_FIND_RUNNING_VMS] 0 -1 0] VIX_PROPERTY_FOUND_ITEM_LOCATION]
    }

    method type {} {
        # Returns the type of the VMware host software
        #
        # The returned value is one of the values accepted for the
        # '-hosttype' option to the connect method.
        return [twapi::dict* {
            2 server 3 workstation 4 player 10 vi_server 11 workstation_shared
        } [my _get_property VIX_PROPERTY_HOST_HOSTTYPE]]
    }

    method version {} {
        # Returns a string containing the version of the VMware host software
        return [my _get_property VIX_PROPERTY_HOST_SOFTWARE_VERSION]
    }

    method trace_VM {oldname newname op} {
        # Internal command to track virtual machines. Do not call directly.

        if {$oldname eq $newname || ![info exists VMs($oldname)]} {
            return
        }
        if {$op eq "rename"} {
            set VMs($newname) $VMs($oldname)
        }
        unset VMs($oldname)
    }
}

oo::class create vix::VM {
    variable Guest Snapshots
    mixin vix::_VixHandle

    constructor {comobj} {
        # Represents a virtual machine on a VMware host.
        #
        # comobj - Wrapped VIX Automation object
        #
        # Objects of this class should not be created directly.
        # They are returned by the open method of an Host object.
        #
        # The methods of this class allow invoking of various operations
        # on the associated virtual machine.
        #
        # The associated VM may or may not be running.
        
        namespace path [linsert [namespace path] end [namespace qualifiers [self class]]]
        set Guest $comobj
    }

    destructor {
        if {[array size Snapshots]} {
            foreach snapshot [array names Snapshots] {
                catch {$snapshot destroy}
            }
        }

        $Guest -destroy
    }

    method wrappee {} {
        # Returns the underlying twapi::Automation COM object
        #
        # The method is used to retrieve the wrapped COM object
        # either for debugging purposes or to invoke VIX methods
        # that are not directly supported by this class.
        # IMPORTANT: The returned object must NOT be directly destroyed
        # by the caller and must not be accessed beyond the lifetime
        # of the wrapper object.
        #
        # The command will raise an error if there is no associated
        # wrapped COM object.
        return $Guest
    }

    method power_on {args} {
        # Powers on the associated virtual machine.
        #
        # -hide BOOLEAN - If false (default), the user interface
        #   is displayed on Workstation and Player VMware hosts.
        #   If true, the user interface is not shown.
        #
        # The associated virtual machine is powered on or resumed
        # from a suspended state. Note that after powering on
        # commands that require the use of VMware Tools on the
        # virtual machine should not be used until the latter is
        # up and running. The command wait_for_tools can be used
        # for this purpose.
        twapi::parseargs args {
            {hide.bool 0}
        } -setvars -maxleftover 0
        wait_for_completion [$Guest PowerOn \
                                 [pick $hide [VIX_VMPOWEROP_NORMAL] \
                                      [VIX_VMPOWEROP_LAUNCH_GUI]] \
                                 0 0]
    }
    method shutdown {} {
        # Shuts down the associated virtual machine.
        #
        # The virtual machine, which must be in a running state,
        # is shut down cleanly using the running
        # operating system. This is in contrast to the power_off method.
        #
        # The command requires VMware Tools to be running on the virtual 
        # machine.
        wait_for_completion [$Guest PowerOff [VIX_VMPOWEROP_FROM_GUEST] 0]
    }

    method reboot {} {
        # Reboots the associated virtual machine.
        #
        # The virtual machine, which must be in a running state,
        # is shut down cleanly using the running
        # operating system and restarted.
        # This is in contrast to the reset method.
        #
        # The command requires VMware Tools to be running on the virtual 
        # machine.
        wait_for_completion [$Guest Reset [VIX_VMPOWEROP_FROM_GUEST] 0]
    }

    method power_off {} {
        # Powers off the associated virtual machine.
        #
        # The virtual machine, which must have been powered on, is turned
        # off with the equivalent of a hardware switch. Unlike
        # the shutdown method, the virtual machine's operating system 
        # is not involved and VMware Tools need not be running on it.
        wait_for_completion [$Guest PowerOff [VIX_VMPOWEROP_NORMAL] 0]
    }

    method reset {} {
        # Resets the associated virtual machine.
        #
        # The virtual machine, which must have been powered on, is turned
        # off and on with the equivalent of a hardware reset. Unlike
        # the reboot method, the virtual machine's operating system 
        # is not involved and VMware Tools need not be running on it.
        wait_for_completion [$Guest Reset [VIX_VMPOWEROP_NORMAL] 0]
    }

    method suspend {} {
        # Suspends the associated virtual machine.
        #
        # The virtual machine, which must have been powered on, is suspended.
        # It can be resumed by calling the power_on method.
        wait_for_completion [$Guest Suspend 0 0]
    }
    
    method wait_for_tools {{timeout 10}} {
        # Waits for VMware Tools to be running in the virtual machine.
        # 
        # timeout - specifies a timeout in seconds to wait. If the tools
        #   are not running within this time, the command completes with
        #   an error. A 0 or negative value indicates an indefinite wait.
        #   Default value is 10 seconds.
        #
        # Several VM methods require VMware Tools to be running.
        # An application can call this method to wait for this. Generally
        # this is only required after powering on or resuming a virtual
        # machine.
        
        wait_for_completion [$Guest WaitForToolsInGuest $timeout 0]
    }

    method login {username password args} {
        # Establishes a login context on the associated virtual machine.
        #
        # username - the login account name
        # password - the password for the account
        # -interactive BOOLEAN - Indicates whether the login session
        #  requires an interactive context. See more below.
        #
        # Several VM operations, for example the ones for files,
        # require a login context on the virtual machine. This method
        # establishes such a context. The virtual machine operating
        # system will enforce access permissions based on this context.
        #
        # The method may be called multiple times to change the login
        # context. To invalidate the context, use the logout method.
        #
        # By default, the login context does not have an interactive
        # desktop associated with it. Specifying the -interactive option
        # as true will create such a interactive context which may be
        # required for executing programs with a graphical user interface
        # with the run method. However, note that creation of an interactive 
        # context requires the same user to be currently logged in
        # to the virtual machine console.
        #
        # Note that not all guest operating systems are supported by the login
        # method. Moreover, Linux virtual machines must be running X11 for
        # interactive contexts.
        #
        # This method requires VMWare Tools to be running in the virtual
        # machine.
        twapi::parseargs args {
            {interactive.bool 0}
        } -setvars -maxleftover 0
        wait_for_completion \
            [$Guest LoginInGuest $username $password \
                 [pick $interactive [VIX_LOGIN_IN_GUEST_REQUIRE_INTERACTIVE_ENVIRONMENT] 0] \
                 0]
    }

    method logout {} {
        # Logs out of a login context
        #
        # The current context created with the login method is closed.
        # Any methods that require a user context on the virtual machine
        # should not be called until a new context is reestablished.
        #
        # This method requires VMWare Tools to be running in the virtual
        # machine.
        wait_for_completion [$Guest LogoutFromGuest 0]
    }

    method getvar {var} {
        # Returns the value of a guest variable in the virtual machine
        # var - name of the guest variable
        #
        # The method returns the value of the specified guest variable
        # in the virtual machine or the empty string if it is not defined.
        # Guest variables are simply a means to associate data with a 
        # virtual machine and only exist while it is running. Use the
        # setvar method to set the value of a guest variable.
        #
        # This method requires the virtual machine to be running.
        
        return [wait_for_result \
                    [$Guest ReadVariable [VIX_VM_GUEST_VARIABLE] $var 0 0] \
                    VIX_PROPERTY_JOB_RESULT_VM_VARIABLE_STRING]
    }

    method setvar {var val} {
        # Sets the value of a guest variable in the virtual machine
        # var - name of the guest variable
        # val - value to set for the variable
        #
        # The method sets the value of the specified guest variable
        # in the virtual machine.
        # Guest variables are simply a means to associate data with a 
        # virtual machine and only exist while it is running. Use the
        # getvar method to set the value of a guest variable.
        #
        # This method requires the virtual machine to be running.

        wait_for_completion [$Guest WriteVariable [VIX_VM_GUEST_VARIABLE] $var $val 0 0]
    }

    method getconfig {var} {
        # Returns the value of an variable in the virtual machine configuration
        # var - name of the environment variable
        #
        # The method returns the value of the specified configuration variable
        # in the virtual machine or the empty string if it is not defined.
        # Configuration variable names are defined in the VMX file for
        # the virtual machine.
        #
        # This method requires the virtual machine to be running.
        
        return [wait_for_result \
                    [$Guest ReadVariable [VIX_VM_CONFIG_RUNTIME_ONLY] $var 0 0] \
                    VIX_PROPERTY_JOB_RESULT_VM_VARIABLE_STRING]
    }

    method getenv {envvar} {
        # Returns the value of an environment variable in the virtual machine
        # envvar - name of the environment variable
        #
        # The method returns the value of the specified environment variable
        # in the virtual machine or the empty string if it is not defined.
        #
        # This method requires a user login context to have been established and
        # the returned value is based on that user context.
        
        return [wait_for_result \
                    [$Guest ReadVariable [VIX_GUEST_ENVIRONMENT_VARIABLE] $envvar 0 0] \
                    VIX_PROPERTY_JOB_RESULT_VM_VARIABLE_STRING]
    }

    method setenv {envvar val} {
        # Sets the value of an environment variable in the virtual machine
        # envvar - name of the environment variable
        # val - value to set for the variable
        #
        # The method sets the value of the specified environment variable
        # in the virtual machine.
        #
        # This method requires a user login context to have been established and
        # the returned value is based on that user context. The scope
        # of the set environment variable in the virtual machine is dependent
        # on its operating system. On Windows guests, UAC has to be disabled
        # for this command to work.

        wait_for_completion [$Guest WriteVariable [VIX_GUEST_ENVIRONMENT_VARIABLE] $envvar $val 0 0]
    }

    method copy_from_vm {guest_path local_path} {
        # Copies a file or directory from the virtual machine.
        # guest_path - file or directory path in the guest virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        # local_path - target local file path where the file or directory is
        #  to be copied
        #
        # The method copies a file or a directory tree from the
        # virtual machine to the local file system
        # overwriting existing files and merging directories.
        # Errors may result in partial copies.
        #
        # This method requires a login context to have been established.
        
        check_path $guest_path
        wait_for_completion [$Guest CopyFileFromGuestToHost $guest_path $local_path 0 0 0]

    }

    method read_file {guest_path args} {
        # Returns a content of a file in the virtual machine
        # guest_path - file or directory path in the guest virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        # args - options are passed to the 'fconfigure' Tcl command
        #  to control CRLF mode, encoding etc.

        close [file tempfile local_path]
        my copy_from_vm $guest_path $local_path
        set fd [open $local_path]
        if {[llength $args]} {
            fconfigure $fd {*}$args
        }
        set data [read $fd]
        close $fd
        catch {file delete $local_path}
        return $data
    }

    method copy_to_vm {local_path guest_path} {
        # Copies a file or directory to the virtual machine.
        # local_path - target local file path where the file or directory is
        #  to be copied
        # guest_path - file or directory path in the guest virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        #
        # The method copies a file or a directory tree from the local
        # file system to the
        # virtual machine, overwriting existing files and merging directories.
        # Errors may result in partial copies.
        #
        # This method requires a login context to have been established.
        
        check_path $guest_path
        wait_for_completion [$Guest CopyFileFromHostToGuest $local_path $guest_path 0 0 0]
    }

    method write_file {guest_path data args} {
        # Returns content to a file in the virtual machine
        # guest_path - file or directory path in the guest virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        # args - options are passed to the 'fconfigure' Tcl command
        #  to control CRLF mode, encoding etc.

        set fd [file tempfile local_path]
        if {[llength $args]} {
            fconfigure $fd {*}$args
        }
        puts -nonewline $fd $data
        close $fd
        my copy_from_vm $local_path $guest_path
        catch {file delete $local_path}
        return
    }

    method mkdir {path} {
        # Creates a new directory in the virtual machine
        # path - directory path in the guest virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        #
        # The directory is created if it does not exist. It is not an
        # error for the directory to already exist.
        #
        # This method requires a login context to have been established.
        check_path $path
        twapi::trap {
            wait_for_completion [$Guest CreateDirectoryInGuest $path 0 0]
        } onerror {VIX 12} {
            # Ignore dir already exists errors
            # 12 -> VIX_E_FILE_ALREADY_EXISTS
        }
    }

    method rmdir {path} {
        # Deletes a directory in the virtual machine
        # path - directory path in the guest virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        #
        # The entire tree under the specified directory is deleted. It is not an
        # error if the directory does not exist.
        #
        # This method requires a login context to have been established.

        check_path $path
        twapi::trap {
            wait_for_completion [$Guest DeleteDirectoryInGuest $path 0 0]
        } onerror {VIX 4} {
            # Ignore dir does not exist errors
            # 4 -> VIX_E_FILE_NOT_FOUND
        }
    }

    method rmfile {path} {
        # Deletes a file in the virtual machine
        # path - file path in the guest virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        #
        # The specified file is deleted. It is not an
        # error if it does not exist.
        #
        # This method requires a login context to have been established.
        check_path $path
        twapi::trap {
            wait_for_completion [$Guest DeleteFileInGuest $path 0]
        } onerror {VIX 4} {
            # 4 -> VIX_E_FILE_NOT_FOUND
            # Ignore file does not exist errors
        }
    }

    method isdir {path} {
        # Check if the specified path is a directory
        # path - directory path in the virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        #
        # Returns 1 if the specified path is a directory and false otherwise.
        #
        # This method requires a login context to have been established.

        check_path $path
        return [wait_for_result \
                    [$Guest DirectoryExistsInGuest $path 0] \
                    VIX_PROPERTY_JOB_RESULT_GUEST_OBJECT_EXISTS]
    }        

    method isfile {path} {
        # Check if the specified path is a regular file.
        # path - file path in the virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        #
        # Returns 1 if the specified path is a regular file
        # and false otherwise.
        #
        # Note in particular that the method will return 0 even in the
        # case that the path exists but is not a regular file, such as
        # a directory or a device.
        #
        # This method requires a login context to have been established.
        check_path $path
        return [wait_for_result \
                    [$Guest FileExistsInGuest $path 0] \
                    VIX_PROPERTY_JOB_RESULT_GUEST_OBJECT_EXISTS]
    }        

    method fstat {path} {
        # Returns information about a file or directory.
        # path - file path in the virtual machine.
        #  This must be an absolute path in a format valid for the guest
        #  operating system.
        #
        # The returned value is a quadruple containing the size of the file
        # (0 if it is a directory), the last modification time in seconds
        # since the epoch, a boolean value that indicates if the path is a
        # directory and a boolean value that indicates if the path is a
        # symbolic link.
        #
        # This method requires a login context to have been established.

        check_path $path
        lassign [wait_for_results \
                     [$Guest GetFileInfoInGuest $path 0] \
                     VIX_PROPERTY_JOB_RESULT_FILE_SIZE \
                     VIX_PROPERTY_JOB_RESULT_FILE_MOD_TIME \
                     VIX_PROPERTY_JOB_RESULT_FILE_FLAGS] \
            size time flags
        return [list $size $time \
                    [expr {($flags & [VIX_FILE_ATTRIBUTES_DIRECTORY]) != 0}] \
                    [expr {($flags & [VIX_FILE_ATTRIBUTES_SYMLINK]) != 0}]]
    }

    method tempfile {} {
        # Creates a temporary file in the virtual machine.
        #
        # Creates a temporary file in the virtual machine. The deletion
        # of the file, if required, is up to the application.
        #
        # Returns the full path to the created file.
        #
        # This method requires a login context to have been established.
        return [wait_for_result \
                    [$Guest CreateTempFileInGuest 0 0 0] \
                    VIX_PROPERTY_JOB_RESULT_ITEM_NAME]
    }

    method rename {from to} {
        # Renames a file or directory in the virtual machine.
        # from - absolute file path in the virtual machine.
        # to - absolute file path in the virtual machine.
        #
        # This method requires a login context to have been established.

        check_path $from
        check_path $to
        wait_for_completion [$Guest RenameFileInGuest $from $to 0 0 0]
    }

    method dir {path args} {
        # Returns the contents of a directory in the virtual machine.
        # path - absolute directory path in the virtual machine.
        # -details BOOLEAN - by default, the method returns a list
        #   of names. If this option is specified as true, the
        #   details of each directory entry is returned.
        #
        # The method reads the contents of a directory in the virtual machine.
        # If -details is unspecified or is false, the return value is a list
        # of directory entry names. If -details is specified as true,
        # the returned value is a list of quintuples containing name of the
        # directory entry, its size
        # (0 if it is a directory), the last modification time in seconds
        # since the epoch, a boolean value that indicates if the path is a
        # directory and a boolean value that indicates if the path is a
        # symbolic link.
        #
        # This method requires a login context to have been established.

        twapi::parseargs args {{details.bool 0}} -setvars -maxleftover 0
        check_path $path
        set job [$Guest ListDirectoryInGuest $path 0 0]
        if {! $details} {
            return [wait_for_properties $job VIX_PROPERTY_JOB_RESULT_ITEM_NAME]
        }

        set contents {}
        foreach entry [wait_for_properties $job VIX_PROPERTY_JOB_RESULT_ITEM_NAME \
                           VIX_PROPERTY_JOB_RESULT_FILE_SIZE \
                           VIX_PROPERTY_JOB_RESULT_FILE_MOD_TIME \
                           VIX_PROPERTY_JOB_RESULT_FILE_FLAGS] {
            set isdir [expr {([lindex $entry 3] & [VIX_FILE_ATTRIBUTES_DIRECTORY]) != 0}]
            set islink [expr {([lindex $entry 3] & [VIX_FILE_ATTRIBUTES_SYMLINK]) != 0}]
            lappend contents [lreplace $entry 3 3 $isdir $islink]
        }

        return $contents
    }

    method pids {} {
        # Returns a list of process ids running in the virtual machine.
        #
        # This method requires a login context to have been established.
        return [wait_for_properties [$Guest ListProcessesInGuest 0 0] VIX_PROPERTY_JOB_RESULT_PROCESS_ID]
    }

    method processes {} {
        # Retrieves detailed information about the processes running in
        # the virtual machine.
        #
        # The return value is a sextuple containing
        #  - the process id
        #  - image name
        #  - account
        #  - command line,
        #  - the process start time (in seconds since the epoch), and
        #  - an indication if the process
        #    is running under a debugger (only on Windows virtual machines).
        #
        # This method requires a login context to have been established.

        return [wait_for_properties \
                    [$Guest ListProcessesInGuest 0 0] \
                    VIX_PROPERTY_JOB_RESULT_PROCESS_ID \
                    VIX_PROPERTY_JOB_RESULT_ITEM_NAME \
                    VIX_PROPERTY_JOB_RESULT_PROCESS_OWNER \
                    VIX_PROPERTY_JOB_RESULT_PROCESS_COMMAND \
                    VIX_PROPERTY_JOB_RESULT_PROCESS_START_TIME \
                    VIX_PROPERTY_JOB_RESULT_PROCESS_BEING_DEBUGGED]
    }            

    method kill {pid} {
        # Terminates a process in the virtual machine.
        #  pid - process id of the process to be terminated
        #
        # This method requires a login context to have been established.

        wait_for_completion [$Guest KillProcessInGuest $pid 0 0]
    }

    method exec {program args} {
        # Executes a program in the virtual machine.
        # program - absolute path of the program to run
        # -activatewindow BOOLEAN - specifies if the program window should
        #   be activated. See below for more
        # -cmdargs CMDLINE - command line to pass to the program
        # -wait BOOLEAN - Specifies whether to wait for the program to
        #   complete (default 0)
        #
        # The program must not assume a specific working directory and
        # any passed arguments should not be based on that assumption either.
        #
        # Programs that interact with the user and need to display on
        # the desktop console require that login context have been created
        # with the -interactive option to Host.login. The -activatewindow
        # option is only relevant for such programs. A true value for
        # the option ensures that the created window is visible and not
        # minimized. This option is only effective for Windows virtual machines.
        #
        # Returns the process id, exit code and elapsed time in seconds
        # as a triple.
        #
        # Note that if -wait is not specified as true, only the process
        # id element in the return value is valid.
        #
        # This method requires a login context to have been established.

        twapi::parseargs args {
            {cmdargs.arg {}}
            {activatewindow.bool 0}
            {wait.bool 0}
        } -setvars -maxleftover 0

        set flags 0
        if {$activatewindow} {
            incr flags [VIX_RUNPROGRAM_ACTIVATE_WINDOW]
        }
        if {! $wait} {
            incr flags [VIX_RUNPROGRAM_RETURN_IMMEDIATELY]
        }

        set job [$Guest RunProgramInGuest $program $cmdargs $flags 0 0]
        return [wait_for_results $job VIX_PROPERTY_JOB_RESULT_PROCESS_ID VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_EXIT_CODE VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_ELAPSED_TIME]
    }

    method script {program script args} {
        # Runs a script in the virtual machine using the specified program
        # program - absolute path of the script interpreter to run
        # script  - the text of the script to run. The size of the script
        #   is limited to about 60,000 characters.
        # -wait BOOLEAN - Specifies whether to wait for the program to
        #   complete (default 0)
        #
        # The program and script must not assume a specific 
        # working directory.
        #
        # Returns the process id, exit code and elapsed time in seconds
        # as a triple.
        #
        # Note that if -wait is not specified as true, only the process
        # id element in the return value is valid.
        #
        # This method requires a login context to have been established.

        twapi::parseargs args {
            {wait.bool 0}
        } -setvars -maxleftover 0

        set job [$Guest RunScriptInGuest \
                     $program \
                     $script \
                     [pick $wait 0 [VIX_RUNPROGRAM_RETURN_IMMEDIATELY]] \
                     0 0]
        return [wait_for_results $job \
                    VIX_PROPERTY_JOB_RESULT_PROCESS_ID \
                    VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_EXIT_CODE \
                    VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_ELAPSED_TIME]
    }

    method pause {} {
        # Pauses the execution of the virtual machine.
        #
        # When the virtual machine is paused, method that operate on
        # the guest should not be called except those related to
        # machine state such as power_off, reset etc.
        #
        # Call the unpause method to resume execution of the virtual machine.
        #
        # WARNING: do NOT call any commands that require virtual machine 
        # operation while it is paused.

        wait_for_completion [$Guest Pause 0 0 0]
    }

    method unpause {} {
        # Resumes the execution of a paused virtual machine.
        #
        wait_for_completion [$Guest Unpause 0 0 0]
    }

    method enable_shared_folders {} {
        # Enables the use of shared folders for the virtual machine.
        #
        # This method requires VMtools to be running in the virtual machine.

        wait_for_completion [$Guest EnableSharedFolders 1 0 0]
    }

    method disable_shared_folders {} {
        # Disables the use of shared folders for the virtual machine.
        #
        # This method requires VMtools to be running in the virtual machine.

        wait_for_completion [$Guest EnableSharedFolders 0 0 0]
    }

    method add_shared_folder {share_name host_path args} {
        # Adds a shared folder to the virtual machine.
        # share_name - the share name in the virtual machine
        # host_path - path of the directory on the host system to be shared
        # -mode MODE - the sharing mode, 'r' or 'readonly' (default) for
        #   read-only shared and 'rw' or 'readwrite' for shares that can
        #   be read or written
        #
        # NOTE: on Windows there may be a delay before the shared path
        # is usable in the virtual machine.
        #
        # This method requires VMtools to be running in the virtual machine.

        twapi::parseargs args {
            {mode readonly {readonly readwrite r rw}}
        } -setvars -maxleftover 0
        switch -exact -- $mode {
            r - readonly {set flags 0}
            rw - readwrite {set flags [VIX_SHAREDFOLDER_WRITE_ACCESS]}
        }

        wait_for_completion [$Guest AddSharedFolder $share_name $host_path $mode 0]
    }

    method remove_shared_folder {share_name} {
        # Removes a shared folder from the virtual machine.
        # share_name - the share name in the virtual machine
        #
        # This method requires VMtools to be running in the virtual machine.
        
        wait_for_completion [$Guest RemoveSharedFolder $share_name 0 0]
    }

    method shared_folders {} {
        # Returns list of shared folders in the virtual machine.
        #
        # The return value consists of triples each containing 
        # information about one shared folder. The first element of
        # the triple is the share name in the virtual machine, the
        # second is the shared directory on the host, and the third
        # is either 'readonly' or 'readwrite'.

        set count [wait_for_result [$Guest GetNumSharedFolders 0]]
        set shares {}
        for {set i 0} {$i < $count} {incr i} {
            set share [wait_for_results [$Guest GetSharedFolderState $i 0] \
                           VIX_PROPERTY_JOB_RESULT_ITEM_NAME \
                           VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_HOST \
                           VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_FLAGS]
            if {[lindex $share 2] & [VIX_SHAREDFOLDER_WRITE_ACCESS]} {
                lappend shares [lreplace $share 2 2 readwrite]
            } else {
                lappend shares [lreplace $share 2 2 readonly]
            }
        }
        return $shares
    }

    method create_snapshot {name args} {
        # Creates a new snapshot of the virtual machine.
        # name - name to assign to the snapshot. This need not be unique
        # -description TEXT - a text description for the snapshot
        # -includememory BOOLEAN - If false (default), memory is not saved with
        #   the snapshot. If true, the current memory content is saved.
        twapi::parseargs args {
            description.arg
            includememory.bool
        } -setvars -maxleftover 0 -nulldefault
        if {$includememory} {
            set includememory [VIX_SNAPSHOT_INCLUDE_MEMORY]
        }
        wait_for_completion [$Guest CreateSnapshot $name $description $includememory 0 0]
    }

    method current_snapshot {} {
        # Returns a Snapshot object representing the current snapshot of
        # the virtual machine
        set err [$Guest GetCurrentSnapshot [twapi::outvar var]]
        check_error $err
        return [my _wrap_snapshot $var]
    }

    method get_snapshot {name} {
        # Returns a Snapshot object representing the named snapshot of
        # the virtual machine
        # name - name of the snapshot. This can include a path through
        #  the snapshot tree with each snapshot separated by '/'
        #
        # VMware does not enforce uniqueness of snapshot names. In case
        # of duplicates, the method raises an exception.
        set err [$Guest GetNamedSnapshot $name [twapi::outvar var]]
        check_error $err
        return [my _wrap_snapshot $var]
    }

    method root_snapshot_count {} {
        # Returns the number of root snapshots of the virtual machine.
        set err [$Guest GetNumRootSnapshots [twapi::outvar count]]
        check_error $err
        return [twapi::variant_value $count 0 0 0]
    }

    method root_snapshot {index} {
        # Returns a Snapshot object corresponding to the root snapshot
        # at the specified position
        # index - position of the root snapshot
        #
        set err [$Guest GetRootSnapshot $index [twapi::outvar var]]
        check_error $err
        return [my _wrap_snapshot $var]
    }

    method delete_snapshot {snapshot args} {
        # Deletes a snapshot of the virtual machine and all associated state
        #   snapshot - the Snapshot object to be removed
        #   -recurse BOOLEAN - if specified as true, children of the
        #     specified snapshot are also deleted. Default is false.
        #
        # Note this deletes the actual snapshot of the virtual machine.
        # The snapshot object has to be destroyed by the caller after
        # the method returns.

        twapi::parseargs args {recurse.bool} -setvars -nulldefault -maxleftover 0
        if {$recurse} {
            set recurse [VIX_SNAPSHOT_REMOVE_CHILDREN]
        }
        set snapshot [uplevel 1 [list namespace which -command $snapshot]]
        wait_for_completion [$Guest RemoveSnapshot $Snapshots($snapshot) $recurse 0]
    }

    method revert_to_snapshot {snapshot args} {
        # Reverts the virtual machine to the specified snapshot
        # snapshot - The Snapshot object to revert to
        # -hide BOOLEAN - If false (default), the user interface
        #   is displayed on Workstation and Player VMware hosts.
        #   If true, the user interface is not shown. Only applies
        #   if the snapshot was taken with the virtual machine powered on.
        # -poweroff BOOLEAN - If true, the restored virtual machine is
        #   powered off even if it was powered on when the snapshot was
        #   taken. Default is false.
        #
        # The virtual machine state is restored to that when the snapshot
        # was taken.
        # Note that after reverting to a snapshot,
        # commands that require the use of VMware Tools on the
        # virtual machine should not be used until the latter is
        # up and running. The command wait_for_tools can be used
        # for this purpose.        

        twapi::parseargs args {
            {poweroff.bool 0}
            {hide.bool 0}
        } -setvars -maxleftover 0

        set flags [pick $poweroff [VIX_VMPOWEROP_SUPPRESS_SNAPSHOT_POWERON]]
        if {$hide} {
            set flags [expr {$flags | [VIX_VMPOWEROP_LAUNCH_GUI]}]
        }
        set snapshot [uplevel 1 [list namespace which -command $snapshot]]
        wait_for_completion [$Guest RevertToSnapshot $Snapshots($snapshot) $flags 0 0]
    }

    method upgrade_hardware {} {
        # Upgrades the hardware of the virtual machine
        #
        # The machine must be powered off before attempting to upgrade
        # the virtual hardware; otherwise the method returns an error.

        if {[my power_state] ne "powered_off"} {
            error "Virtual machine is not powered off."
        }
        wait_for_completion [$Guest UpgradeVirtualHardware 0 0]
        
    }

    method upgrade_vmware_tools {} {
        # Upgrades VMware Tools in the virtual machine
        #
        # Some version of VMware Tools must already be running in the
        # virtual machine.
        
        wait_for_completion [$Guest InstallTools [VIX_INSTALLTOOLS_AUTO_UPGRADE] "" 0]
    }

    method path {} {
        # Returns the full path of the VMX file for the virtual machine
        return [my _get_property VIX_PROPERTY_VM_VMX_PATHNAME]
    }

    method team_path {} {
        # Returns the path to the virtual machine team
        #
        # The command will raise an error if the virtual machine is not
        # part of a team. Use the team_member? method to check.
        return [my _get_property VIX_PROPERTY_VM_VMTEAM_PATHNAME]
    }

    method ncpus {} {
        # Returns the number of CPU's configured for the virtual machine
        return [my _get_property VIX_PROPERTY_VM_NUM_VCPUS]
    }

    method memory_size {} {
        # Returns the memory size configured for the virtual machine
        return [my _get_property VIX_PROPERTY_VM_MEMORY_SIZE]
    } 

    method readonly? {} {
        return [my _get_property VIX_PROPERTY_VM_READ_ONLY]
    }            

    method name {} {
        # Returns the name of the virtual machine
        return [my _get_property VIX_PROPERTY_VM_NAME]
    }

    method os {} {
        # Returns the operating system running in the virtual machine
        #
        # The returned value is an internal VMware name specific
        # to an operating system, for example 'winxppro'.
        return [my _get_property VIX_PROPERTY_VM_GUESTOS]
    }

    method team_member? {} {
        # Returns '1' if the virtual machine is a member of a team, else '0'
        return [my _get_property VIX_PROPERTY_VM_IN_VMTEAM]
    }

    method power_state {} {
        # Returns the power state of the virtual machine
        #
        # The returned value is a list of one or more values from the
        # following: 
        # 'powering_off', 'powered_off', 'powering_on', 'powered_on'
        # 'suspending', 'suspended', 'tools_running', 'resetting',
        # 'blocked_on_msg', 'paused', 'resuming'.

        set bits [my _get_property VIX_PROPERTY_VM_POWER_STATE]
        set states {}
        foreach bitname {
            VIX_POWERSTATE_POWERING_OFF
            VIX_POWERSTATE_POWERED_OFF
            VIX_POWERSTATE_POWERING_ON
            VIX_POWERSTATE_POWERED_ON
            VIX_POWERSTATE_SUSPENDING
            VIX_POWERSTATE_SUSPENDED
            VIX_POWERSTATE_TOOLS_RUNNING
            VIX_POWERSTATE_RESETTING
            VIX_POWERSTATE_BLOCKED_ON_MSG
            VIX_POWERSTATE_PAUSED
            VIX_POWERSTATE_RESUMING
        } {
            if {$bits & [$bitname]} {
                lappend states [string tolower [string range $bitname 15 end]]
            }
        }
        return $states
    }

    method tools_state {} {
        # Returns the state of VMware tools in the virtual machine
        #
        # The returned value is one of 'unknown', 'running', or 'not_installed'.
        return [twapi::dict* {
            1 unknown
            2 running
            4 not_installed
        } [my _get_property VIX_PROPERTY_VM_TOOLS_STATE]]
    }

    method running? {} {
        # Returns '1' if the virtual machine running, else '0'
        return [my _get_property VIX_PROPERTY_VM_IS_RUNNING]
    }

    method ssl_error {} {
        return [my _get_property VIX_PROPERTY_VM_SSL_ERROR]
    }

    method shared_folder_path {} {
        # Returns the shared folder path in the virtual machine
        #
        # VMware shared folders are placed under a specific location
        # in the virtual machine. This method returns the path
        # to this location.
        #
        # This method requires VMware Tools to be running in the virtual
        # machine.
        return [my _get_property VIX_PROPERTY_GUEST_SHAREDFOLDERS_SHARES_PATH]
    }

    method trace_Snapshot {oldname newname op} {
        # Internal command to track virtual machines. Do not call directly.

        if {$oldname eq $newname || ![info exists Snapshots($oldname)]} {
            return
        }
        if {$op eq "rename"} {
            set Snapshots($newname) $Snapshots($oldname)
        }
        unset Snapshots($oldname)
    }

    method _wrap_snapshot {var} {
        set comobj [twapi::variant_value $var 0 0 0]
        set snapshot [Snapshot new $comobj]
        set Snapshots($snapshot) $comobj; # Will need for remove_snapshot method
        trace add command $snapshot {rename delete} [list [self] trace_Snapshot]
        return $snapshot
    }

}


oo::class create vix::Snapshot {
    variable Snapshot
    mixin vix::_VixHandle
    constructor {comobj} {
        # Represents a snapshot of a virtual machine.
        #
        # comobj - Wrapped VIX Automation object
        #
        # Objects of this class should not be created directly. They
        # are returned by various methods of objects of this class
        # and the VM class.
        #
        # The methods of this class allow invoking of various operations
        # on virtual machine snapshots.
        
        namespace path [linsert [namespace path] end [namespace qualifiers [self class]]]
        set Snapshot $comobj
    }

    destructor {
        $Snapshot -destroy
    }

    method wrappee {} {
        # Returns the underlying twapi::Automation COM object
        #
        # The method is used to retrieve the wrapped COM object
        # either for debugging purposes or to invoke VIX methods
        # that are not directly supported by this class.
        # IMPORTANT: The returned object must NOT be directly destroyed
        # by the caller and must not be accessed beyond the lifetime
        # of the wrapper object.
        #
        # The command will raise an error if there is no associated
        # wrapped COM object.
        return $Snapshot
    }

    method parent {} {
        # Returns the parent snapshot
        set err [$Snapshot GetParent [twapi::outvar parent]]
        check_error $err
        return [Snapshot create $parent]
    }

    method child {index} {
        # Returns a child snapshot
        # index - index of the children snapshots
        # Returns a Snapshot object representing the child snapshot
        # at the specified index position.
        set err [$Snapshot GetChild $index [twapi::outvar child]]
        check_error $err
        return [Snapshot create $child]
    }

    method number_of_children {} {
        # Returns the number of children of the snapshot
        set err [$Snapshot GetNumChildren [twapi::outvar count]]
        check_error $err
        return $count
    }

    method display_name {} {
        # Returns the display name of the snapshot
        return [my _get_property VIX_PROPERTY_SNAPSHOT_DISPLAYNAME]
    }

    method description {} {
        # Returns the description name of the snapshot
        return [my _get_property VIX_PROPERTY_SNAPSHOT_DESCRIPTION]
    }
}


namespace eval vix {
    # Syntactically, easier to access VIX #defines as commands than as variables
    foreach {_vixdefine _vixvalue} {
        VIX_INVALID_HANDLE 0
        VIX_HANDLETYPE_NONE 0
        VIX_HANDLETYPE_HOST 2
        VIX_HANDLETYPE_VM 3
        VIX_HANDLETYPE_NETWORK 5
        VIX_HANDLETYPE_JOB 6
        VIX_HANDLETYPE_SNAPSHOT 7
        VIX_HANDLETYPE_PROPERTY_LIST 9
        VIX_HANDLETYPE_METADATA_CONTAINER 11
        VIX_OK 0
        VIX_PROPERTYTYPE_ANY 0
        VIX_PROPERTYTYPE_INTEGER 1
        VIX_PROPERTYTYPE_STRING 2
        VIX_PROPERTYTYPE_BOOL 3
        VIX_PROPERTYTYPE_HANDLE 4
        VIX_PROPERTYTYPE_INT64 5
        VIX_PROPERTYTYPE_BLOB 6
        VIX_PROPERTY_NONE 0
        VIX_PROPERTY_META_DATA_CONTAINER 2
        VIX_PROPERTY_HOST_HOSTTYPE 50
        VIX_PROPERTY_HOST_API_VERSION 51
        VIX_PROPERTY_HOST_SOFTWARE_VERSION 52
        VIX_PROPERTY_VM_NUM_VCPUS 101
        VIX_PROPERTY_VM_VMX_PATHNAME 103
        VIX_PROPERTY_VM_VMTEAM_PATHNAME 105
        VIX_PROPERTY_VM_MEMORY_SIZE 106
        VIX_PROPERTY_VM_READ_ONLY 107
        VIX_PROPERTY_VM_NAME 108
        VIX_PROPERTY_VM_GUESTOS 109
        VIX_PROPERTY_VM_IN_VMTEAM 128
        VIX_PROPERTY_VM_POWER_STATE 129
        VIX_PROPERTY_VM_TOOLS_STATE 152
        VIX_PROPERTY_VM_IS_RUNNING 196
        VIX_PROPERTY_VM_SUPPORTED_FEATURES 197
        VIX_PROPERTY_VM_SSL_ERROR 293
        VIX_PROPERTY_JOB_RESULT_ERROR_CODE 3000
        VIX_PROPERTY_JOB_RESULT_VM_IN_GROUP 3001
        VIX_PROPERTY_JOB_RESULT_USER_MESSAGE 3002
        VIX_PROPERTY_JOB_RESULT_EXIT_CODE 3004
        VIX_PROPERTY_JOB_RESULT_COMMAND_OUTPUT 3005
        VIX_PROPERTY_JOB_RESULT_HANDLE 3010
        VIX_PROPERTY_JOB_RESULT_GUEST_OBJECT_EXISTS 3011
        VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_ELAPSED_TIME 3017
        VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_EXIT_CODE 3018
        VIX_PROPERTY_JOB_RESULT_ITEM_NAME 3035
        VIX_PROPERTY_JOB_RESULT_FOUND_ITEM_DESCRIPTION 3036
        VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_COUNT 3046
        VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_HOST 3048
        VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_FLAGS 3049
        VIX_PROPERTY_JOB_RESULT_PROCESS_ID 3051
        VIX_PROPERTY_JOB_RESULT_PROCESS_OWNER 3052
        VIX_PROPERTY_JOB_RESULT_PROCESS_COMMAND 3053
        VIX_PROPERTY_JOB_RESULT_FILE_FLAGS 3054
        VIX_PROPERTY_JOB_RESULT_PROCESS_START_TIME 3055
        VIX_PROPERTY_JOB_RESULT_VM_VARIABLE_STRING 3056
        VIX_PROPERTY_JOB_RESULT_PROCESS_BEING_DEBUGGED 3057
        VIX_PROPERTY_JOB_RESULT_SCREEN_IMAGE_SIZE 3058
        VIX_PROPERTY_JOB_RESULT_SCREEN_IMAGE_DATA 3059
        VIX_PROPERTY_JOB_RESULT_FILE_SIZE 3061
        VIX_PROPERTY_JOB_RESULT_FILE_MOD_TIME 3062
        VIX_PROPERTY_JOB_RESULT_EXTRA_ERROR_INFO 3084
        VIX_PROPERTY_FOUND_ITEM_LOCATION 4010
        VIX_PROPERTY_SNAPSHOT_DISPLAYNAME 4200
        VIX_PROPERTY_SNAPSHOT_DESCRIPTION 4201
        VIX_PROPERTY_SNAPSHOT_POWERSTATE 4205
        VIX_PROPERTY_GUEST_SHAREDFOLDERS_SHARES_PATH 4525
        VIX_PROPERTY_VM_ENCRYPTION_PASSWORD 7001
        VIX_EVENTTYPE_JOB_COMPLETED 2
        VIX_EVENTTYPE_JOB_PROGRESS 3
        VIX_EVENTTYPE_FIND_ITEM 8
        VIX_EVENTTYPE_CALLBACK_SIGNALLED 2
        VIX_FILE_ATTRIBUTES_DIRECTORY 1
        VIX_FILE_ATTRIBUTES_SYMLINK 2
        VIX_HOSTOPTION_VERIFY_SSL_CERT 16384
        VIX_SERVICEPROVIDER_DEFAULT 1
        VIX_SERVICEPROVIDER_VMWARE_SERVER 2
        VIX_SERVICEPROVIDER_VMWARE_WORKSTATION 3
        VIX_SERVICEPROVIDER_VMWARE_PLAYER 4
        VIX_SERVICEPROVIDER_VMWARE_VI_SERVER 10
        VIX_SERVICEPROVIDER_VMWARE_WORKSTATION_SHARED 11
        VIX_API_VERSION -1
        VIX_FIND_RUNNING_VMS 1
        VIX_FIND_REGISTERED_VMS 4
        VIX_VMOPEN_NORMAL 0
        VIX_VMPOWEROP_NORMAL 0
        VIX_VMPOWEROP_FROM_GUEST 4
        VIX_VMPOWEROP_SUPPRESS_SNAPSHOT_POWERON 128
        VIX_VMPOWEROP_LAUNCH_GUI 512
        VIX_VMPOWEROP_START_VM_PAUSED 4096
        VIX_VMDELETE_DISK_FILES 2
        VIX_POWERSTATE_POWERING_OFF 1
        VIX_POWERSTATE_POWERED_OFF 2
        VIX_POWERSTATE_POWERING_ON 4
        VIX_POWERSTATE_POWERED_ON 8
        VIX_POWERSTATE_SUSPENDING 16
        VIX_POWERSTATE_SUSPENDED 32
        VIX_POWERSTATE_TOOLS_RUNNING 64
        VIX_POWERSTATE_RESETTING 128
        VIX_POWERSTATE_BLOCKED_ON_MSG 256
        VIX_POWERSTATE_PAUSED 512
        VIX_POWERSTATE_RESUMING 2048
        VIX_TOOLSSTATE_UNKNOWN 1
        VIX_TOOLSSTATE_RUNNING 2
        VIX_TOOLSSTATE_NOT_INSTALLED 4
        VIX_VM_SUPPORT_SHARED_FOLDERS 1
        VIX_VM_SUPPORT_MULTIPLE_SNAPSHOTS 2
        VIX_VM_SUPPORT_TOOLS_INSTALL 4
        VIX_VM_SUPPORT_HARDWARE_UPGRADE 8
        VIX_LOGIN_IN_GUEST_REQUIRE_INTERACTIVE_ENVIRONMENT 8
        VIX_RUNPROGRAM_RETURN_IMMEDIATELY 1
        VIX_RUNPROGRAM_ACTIVATE_WINDOW 2
        VIX_VM_GUEST_VARIABLE 1
        VIX_VM_CONFIG_RUNTIME_ONLY 2
        VIX_GUEST_ENVIRONMENT_VARIABLE 3
        VIX_SNAPSHOT_REMOVE_CHILDREN 1
        VIX_SNAPSHOT_INCLUDE_MEMORY 2
        VIX_SHAREDFOLDER_WRITE_ACCESS 4
        VIX_CAPTURESCREENFORMAT_PNG 1
        VIX_CAPTURESCREENFORMAT_PNG_NOCOMPRESS 2
        VIX_CLONETYPE_FULL 0
        VIX_CLONETYPE_LINKED 1
        VIX_INSTALLTOOLS_MOUNT_TOOLS_INSTALLER 0
        VIX_INSTALLTOOLS_AUTO_UPGRADE 1
        VIX_INSTALLTOOLS_RETURN_IMMEDIATELY 2
    } {
        interp alias {} [namespace current]::$_vixdefine {} lindex $_vixvalue
    }
    unset _vixdefine
    unset _vixvalue
}

proc vix::generate_docs {} {
    variable _ruffdoc

    package require ruff

    set ns [namespace current]

    # We do not want to document all commands as some are internal so
    # we use the low level Woof calls to extract relevant documentation.
    set docs [ruff::extract ${ns}::* -includeclasses 1 -includeprocs 0]
    set procs [list \
                   ${ns}::initialize [ruff::extract_proc ${ns}::initialize] \
                   ${ns}::finalize [ruff::extract_proc ${ns}::finalize]]
    dict set docs procs $procs
#    return [ruff::document html $docs "" -preamble [dict create ::vix [list {Vix reference} [ruff::extract_docstring {This is a Tcl interface for VIX}]]]]
    set preamble [dict create]
    foreach {section docstring} $_ruffdoc {
        dict lappend preamble $ns $section [ruff::extract_docstring $docstring]
    }
    return [ruff::document html $docs "" -preamble $preamble]
}

proc vix::distribute {{dir {}}} {
    variable version
    if {$dir eq ""} {
        set dir [pwd]
    }
    file copy -force -- [info script] [file join $dir vix-${version}.tm]
}

proc vix::document {{outfile {}}} {
    if {$outfile eq ""} {
        set outfile [file join [pwd] vix.html]
    }
    # If file already exists, try and make sure it is not some other
    # random file 
    if {[file exists $outfile]} {
        set fd [open $outfile]
        set content [read $fd]
        close $fd
        if {![regexp -nocase {<body>.*twapi_com.*vix::VM.*generated by ruff} $content]} {
            error "File $outfile exists and does not seem to be tcl-vix documentation."
        }
    }

    set fd [open $outfile w]
    try {
        puts $fd [generate_docs]
    } finally {
        close $fd
    }
}

proc vix::install {tm_path {dir {}}} {
    if {[file extension $tm_path] ne ".tm"} {
        error "Script is not a Tcl module. Must have a .tm extension."
    }
    if {$dir eq ""} {
        foreach dir [tcl::tm::list] {
            # Note not all directories on the path exist
            if {[file isdirectory $dir]} {
                # Only install into the 8.6 directory or site-tcl
                if {[file tail $dir] eq "8.6"} {
                    set dir86 $dir
                    break
                }
                if {[file tail $dir] eq "site-tcl"} {
                    set dirsite $dir
                    # Keep looking for a 8.6 dir
                }
            }
        }
        if {[info exists dir86]} {
            set dir $dir86
        } elseif {[info exists dirsite]} {
            set dir $dirsite
        } else {
            error "Could not locate directory to install into"
        }
    } else {
        if {![file isdirectory $dir]} {
            error "$dir is not a directory or does not exist"
        }
    }
    puts stdout "Installing to $dir..."
    file copy -force -- $tm_path $dir
}

proc vix::upload {tm_file} {
    if {[file extension $tm_file] ne ".tm"} {
        error "$tm_file is not a Tcl module"
    }
    exec pscp -agent $tm_file apnadkarni@frs.sourceforge.net:/home/frs/project/tcl-vix/[file tail $tm_file]
    exec pscp -agent [file join [file dirname $tm_file] vix.html] apnadkarni@web.sourceforge.net:/home/project-web/tcl-vix/htdocs/index.html
}

package provide $vix::package $vix::version

if {[string equal -nocase [lindex $::argv0 0] [info script]]} {
    switch -exact -- [lindex $::argv 0] {
        distribute {vix::distribute [lindex $::argv 1]}
        document {vix::document [lindex $::argv 1]}
        install {vix::install [info script] [lindex $::argv 1]}
        upload {vix::upload [info script]}
        default {
            puts stderr "Commands:"
            puts stderr "\tdistribute ?DIR?"
            puts stderr "\tdocument ?OUTFILE?"
            puts stderr "\tinstall ?DIR?"
            puts stderr "\tupload"
        }
    }
}
