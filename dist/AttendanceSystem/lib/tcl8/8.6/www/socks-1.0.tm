# SOCKS V4a: http://ftp.icm.edu.pl/packages/socks/socks4/SOCKS4.protocol
# SOCKS V5: RFC 1928

namespace eval www::socks {
    variable username guest password guest
    namespace ensemble create -map {socks4 {init socks4} socks5 {init socks5}}
}

proc www::socks::command {sock data {count 2} {timeout 2000}} {
    if {$data ne ""} {
	puts -nonewline $sock $data
	flush $sock
    }
    set coro [info coroutine]
    if {[llength $coro]} {
	set id [after $timeout [list $coro timeout]]
	fileevent $sock readable [list $coro data]
    } else {
	fconfigure $sock -blocking 1
	set id {}
    }
    set resp {}
    set len 0
    while {![eof $sock]} {
	append resp [read $sock [expr {$count - $len}]]
	set len [string length $resp]
	if {$len >= $count} {
	    after cancel $id
	    return $resp
	}
	if {[llength $coro] == 0} continue
	set event [yield]
	if {$event eq "data"} continue
	if {$event eq "timeout"} break
    }
    throw {SOCKS PROTOCOL ERROR} "did not get expected response from proxy"
}

proc www::socks::init {version sock host port} {
    # Make sure this is running in a coroutine
    if {[llength [info coroutine]] == 0} {
	return [coroutine $sock init $version $sock $host $port]
    }
    dict set cfg -translation [fconfigure $sock -translation]
    dict set cfg -blocking [fconfigure $sock -blocking]
    dict set event readable [fileevent $sock readable]
    dict set event writable [fileevent $sock writable]
    fileevent $sock writable {}
    fconfigure $sock -translation binary -blocking 0
    if {[catch {$version $sock $host $port} result opts]} {
	variable lasterror $result
    }
    fconfigure $sock {*}$cfg
    dict for {ev cmd} $event {
	fileevent $sock $ev $cmd
    }
    return -options [dict incr opts -level] $result
}

proc www::socks::socks4 {sock host port} {
    variable username
    set ip4 [split $host .]
    if {[llength $ip4] == 4 && [string is digit -strict [lindex $ip4 end]]} {
	set data [binary format ccSc4a*x 4 1 $port $ip4 $username]
    } else {
	# SOCKS4a
	set data [binary format ccSx3ca*xa*x 4 1 $port 1 $username $host]
    }
    binary scan [command $sock $data 8] cucuSc4 vn cd dstport dstip
    if {$vn != 0} {
	throw {SOCKS CONNECT VERSION} \
	  "unsupported socks connection version: $vn"
    }
    if {$cd != 90} {
	throw [list SOCKS CONNECT [format ERROR%02X $cd]] \
	  "socks connection failed with error code $cd"
    }
    return [join $dstip .]:$dstport
}

proc www::socks::socks5 {sock host port} {
    fconfigure $sock -translation binary -blocking 0
    # Authenticate
    set methods [list 0 2]
    set data [binary format ccc* 5 [llength $methods] $methods]
    binary scan [command $sock $data 2] cucu version method

    if {$method == 0} {
	# No authentication required
    } elseif {$method == 1} {
	# GSS-API RFC 1961
	# Not implemented
	throw {SOCKS AUTH UNKNOWN} "unsupported authentication method: $method"
    } elseif {$method == 2} {
	# Username/password RFC 1929
	authenticate $sock
    } else {
	throw {SOCKS AUTH NOTACCEPTED} "no acceptable authentication methods"
    }

    # Connect
    set data [binary format ccc 5 1 0]
    set ip4 [split $host .]
    if {[llength $ip4] == 1 && [llength [set ip6 [split $host :]]] >= 3} {
	# IPv6 address
	set x [lsearch -exact $ip6 {}]
	if {$x >= 0} {
	    set ip6 [lsearch -inline -exact -all -not $ip6 {}]
	    set insert [lrepeat [expr {8 - [llength $ip6]}] 0]
	    set ip6 [linsert $ip6 $x {*}$insert]
	}
	append data [binary format cS8S 4 $ip6 $port]
    } elseif {[llength $ip4] == 4 && [string is digit -strict [lindex $ip4 end]]} {
	# IPv4 address
	append data [binary format cc4S 1 $ip4 $port]
    } else {
	# hostname
	append data [binary format cca*S 3 [string length $host] $host $port]
    }
    binary scan [command $sock $data 4 10000] ccxc version reply atyp
    if {$reply != 0} {
	throw [list SOCKS CONNECT [format ERROR%02X $reply]] \
	  "socks connection failed with error code $reply"
    }
    switch $atyp {
	1 {
	    binary scan [command $sock {} 6] c4S dstip dstport
	    return [join $dstip .]:$dstport
	}
	3 {
	    binary scan [command $sock {} 1] c len
	    binary scan [command $sock {} [expr {$len + 2}]] a${len}S dsthost dstport
	    return $dsthost:$dstport
	}
	4 {
	    binary scan [command $sock {} 18] S8S dstip dstport
	    return format {[%s]:$d} [join $dstip :] $dstport
	}
    }
}

proc www::socks::authenticate {sock} {
    variable username
    variable password
    set data [binary format cca*ca* 1 \
      [string length $username] $username [string length $password] $password]
    binary scan [command $sock 2] cucu version status
    if {$version != 1} {
	throw {SOCKS AUTH RFC1929 VERSION} \
	  "unsupported username/password authentication version: $version"
    }
    if {$status != 0} {
	throw {SOCKS AUTH RFC1929 STATUS} \
	  "username/password authentication failed: $status"
    }
}
