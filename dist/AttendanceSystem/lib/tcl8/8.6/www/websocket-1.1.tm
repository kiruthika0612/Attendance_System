# Helper library for adding websocket support to www

package require www 2.7

proc www::websocket {args} {
    set opts {-upgrade {WebSocket www::WebSocket}}
    set args [getopt arg $args {
	-timeout:milliseconds {dict set opts -timeout $arg}
	-auth:data {dict set opts -auth $arg}
	-digest:cred {dict set opts -digest $arg}
	-maxredir:cnt {dict set opts -maxredir $arg}
    }]
    if {[llength $args] < 1 || [llength $args] > 3} {
	throw {WWW WEBSOCKET ARGS} {wrong # args:\
	  should be "www::websocket url ?protocols? ?extensions?"}
    }
    lassign $args url protocols extensions
    try {
	set hdrs [WebSocket headers]
	if {[llength $protocols]} {
	    lappend hdrs Sec-WebSocket-Protocol [join $protocols {, }]
	}
	if {[dict size $extensions]} {
	    set ext [join [lmap name [dict keys $extensions] {
		set list [list $name]
		if {[dict exists $extensions $name parameters]} {
		    lappend $list [dict get $extensions $name parameters]
		}
		join $list {; }
	    }] {, }]
	    lappend hdrs Sec-WebSocket-Extensions $ext
	}
	www get {*}$opts -headers $hdrs $url
    } on ok {result info} {
	if {[dict get $info status code] != 101} {
	    # The only correct response for a successful websocket connection
	    # is 101 Switching Protocols. Even 200 OK is not good.
	    set code [dict get $info status code]
	    set codegrp [string replace $code 1 2 XX]
	    set reason [dict get $info status reason]
	    dict set info -code 1
	    dict set info -errorcode [list WWW CODE $codegrp $code $reason]
	    return -options [dict incr info -level] $result
	}
	set websock [dict get $info websocket]
	set hdrs [dict get $info headers]
	set protocol [if {[dict exists $hdrs sec-websocket-protocol]} {
	    dict get $hdrs sec-websocket-protocol
	}]
	if {[dict exists $hdrs sec-websocket-extensions]} {
	    set ext [header [$hdrs sec-websocket-extensions] *]
	    set mixins [lmap value [lreverse $ext] {
		set list [lmap n [split $value {;}] {string trim $n}]
		set params [lassign $list name]
		dict set parameters $name $params
		dict get $extensions $name implementation
	    }]
	    oo::objdefine $websock \
	      mixin www::WSExtension {*}$mixins www::WebSocket
	    # Inform the extensions of their parameters, if any
	    $websock parameters $parameters
	}
	# Return the websocket object command (and the negotiated protocol)
	return protocol $protocol [dict get $info websocket]
    }
}

namespace ensemble configure www \
  -subcommands [linsert [namespace ensemble configure www -subcommands] end websocket]

oo::class create www::WebSocket {
    method Startup {headers} {
	my variable fd
	variable callback {}
	# This socket cannot be used for future connections
	release [self]
	fconfigure $fd -translation binary -buffering none -blocking 0
	# Return the websocket object to the caller
	my Result websocket [self]
	my Return [my PopRequest]
    }

    method Read {} {
	my variable fd
	return [read $fd]
    }

    method Write {data} {
	my variable fd
	puts -nonewline $fd $data
    }

    method Handler {} {
	my variable fd callback
	fileevent $fd readable [list [info coroutine] data]
	set data ""
	set payload ""
	while {![eof $fd]} {
	    yield
	    append data [my Read]
	    if {[binary scan $data B4Xcucu flags code len] != 3} continue
	    if {$len < 126} {
		set pos 2
	    } elseif {$len == 126} {
		if {[binary scan $data x2Su len] != 1} continue
		set pos 4
	    } elseif {$len == 127} {
		if {[binary scan $data x2Wu len] != 1} continue
		set pos 10
	    } else {
		# Error: Messages from server to client should not be masked
		my close 1002
	    }
	    if {[string length $data] < $pos + $len} continue
	    set code [expr {$code & 0xf}]
	    set payload [string range $data $pos [expr {$pos + $len - 1}]]
	    set data [string range $data [expr {$pos + $len}] end]
	    if {$code == 0} {
		append message $payload
	    } else {
		set opcode $code
		# Control frames MAY be injected in the middle of a
		# fragmented message. (RFC6455 5.4)
		# Control frames are identified by opcodes where the most
		# significant bit of the opcode is 1. (RFC6455 5.5)
		if {$code < 8} {set message $payload}
	    }
	    if {![string index $flags 0]} continue
	    if {$opcode < 8} {
		my Receive $opcode $message $flags
	    } else {
		my Receive $opcode $payload $flags
	    }
	}
	if {[dict exists $callback close]} {
	    # 1006 is designated for use in applications expecting a status
	    # code to indicate that the connection was closed abnormally,
	    # e.g., without sending or receiving a Close control frame.
	    {*}[dict get $callback close] close 1006 "eof on connection"
	}
	my destroy
    }

    # Methods that can be overridden by extensions

    method Read {} {
	my variable fd
	return [read $fd]
    }

    method Write {data} {
	my variable fd
	puts -nonewline $fd $data
    }

    method Receive {opcode data flags} {
	my variable callback
	switch $opcode {
	    1 {
		if {[dict exists $callback text]} {
		    set str [encoding convertfrom utf-8 $data]
		    {*}[dict get $callback text] text $str
		} else {
		    my close 1003
		}
	    }
	    2 {
		if {[dict exists $callback binary]} {
		    {*}[dict get $callback binary] binary $data
		} else {
		    my close 1003
		}
	    }
	    8 {
		if {[dict exists $callback close]} {
		    if {[binary scan $data Sua* code reason] != 2} {
			set code 1005
			set reason ""
		    }
		    {*}[dict get $callback close] close $code $reason
		    set callback {}
		}
	    }
	    9 {
		if {[dict exists $callback ping]} {
		    {*}[dict get $callback ping] ping $data
		} else {
		    my pong $data
		}
	    }
	    10 {
		if {[dict exists $callback pong]} {
		    {*}[dict get $callback pong] pong $data
		}
	    }
	}
    }

    method Transmit {opcode data {flags 1}} {
	binary scan $data cu* bytes
	# The requirement to use a strong source of entropy makes no sense
	# So we'll just use Tcl's simple linear congruential generator
	set key [expr {int(rand() * 0x100000000)}]
	binary scan [binary format I $key] cu* mask
	set length [llength $bytes]
	# Apply the mask
	set i 0
	set bytes [lmap n $bytes {
	    set m [lindex $mask [expr {$i & 3}]]
	    incr i
	    expr {$n ^ $m}
	}]
	set type \
	  [expr {$opcode | "0b[string reverse [format %04s $flags]]0000"}]
	set data [binary format c $type]
	if {$length < 126} {
	    append data [binary format c [expr {$length | 0x80}]]
	} elseif {$length < 65536} {
	    append data [binary format cS [expr {126 | 0x80}] $length]
	} else {
	    append data [binary format cW [expr {127 | 0x80}] $length]
	}
	append data [binary format c*c* $mask $bytes]
	my Write $data
    }

    # Public methods

    method callback {types prefix} {
	variable callback
	set running [dict size $callback]
	if {$prefix ne ""} {
	    foreach type $types {
		dict set callback $type $prefix
	    }
	} elseif {[llength $types]} {
	    set callback [dict remove $callback {*}$types]
	} else {
	    set callback {}
	}
	if {[dict size $callback]} {
	    if {!$running} {coroutine websockcoro my Handler}
	} else {
	    if {$running} {rename websockcoro ""}
	}
    }

    method text {str} {
	my Transmit 1 [encoding convertto utf-8 $str]
    }

    method binary {data} {
	my Transmit 2 $data
    }

    method close {{code 1005} {reason ""}} {
	# 1005 is designated for use in applications expecting a status code
	# to indicate that no status code was actually present.
	set payload [if {$code != 1005} {
	    binary format Sa* $code [encoding convertto utf-8 $reason]
	}]
	my Transmit 8 $payload
	# The client SHOULD wait for the server to close the connection but
	# MAY close the connection at any time after sending and receiving
	# a Close message, e.g., if it has not received a TCP Close from
	# the server in a reasonable time period.
	# my destroy
    }

    method ping {{data ""}} {
	my Transmit 9 $data
    }

    method pong {{data ""}} {
	my Transmit 10 $data
    }
}

oo::class create www::WSExtension {
    method parameters {parameters} {
	dict for {mixin params} $parameters {
	    nextto $mixin $params
	}
    }
}

oo::objdefine www::WebSocket {
    method key {} {
	# Generate a websocket key containing base64-encoded random bytes
	# This key is only intended to prevent a caching proxy from
	# re-sending a previous WebSocket conversation, and does not
	# provide any authentication, privacy or integrity.
	# It is therefor not necessary to check the returned hash.
	for {set i 0} {$i < 12} {incr i} {
	    lappend bytes [expr {int(rand() * 256)}]
	}
	return [binary encode base64 [binary format c* $bytes]]
    }

    method headers {} {
	return [list Sec-WebSocket-Key [my key] Sec-WebSocket-Version 13]
    }
}

www register ws 80
www register wss 443 www::encrypt 1
