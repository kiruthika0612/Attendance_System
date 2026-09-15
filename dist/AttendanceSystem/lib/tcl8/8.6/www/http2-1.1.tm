# Helper library for adding http/2 support to www

# https://httpbin.org/

package require www 2.7

# trace add execution fileevent enter entertrace
proc entertrace {cmd op} {puts $cmd}

if {[package vsatisfies [package require tls] 1.8-]} {
    # Override the encrypt proc from the www package to add the -alpn option
    proc www::encrypt {sock host} {
	variable tlscfg
	tls::import $sock -servername $host -alpn {h2 http/1.1} {*}$tlscfg
    }
}

oo::class create www::http2helper {
    method Contact {} {
	my variable fd
	if {![next]} {return 0}
	# Wait for the TLS handshake to complete
	fileevent $fd writable [list [info coroutine] handshake]
	yield
	fileevent $fd writable {}
	# Check the ALPN negotiation result
	if {[catch {dict get [tls::status $fd] alpn} alpn]} {set alpn ""}
	if {$alpn eq "h2"} {
	    oo::objdefine [self] mixin http2
	    my Startup {}
	}
	return 1
    }

    method PushRequest {} {
	my variable waiting pending
	set waiting [lassign $waiting request]

	if {[dict get $request scheme] eq "http"} {
	    dict lappend request upgrade h2c http2
	    # Add the headers needed for an HTTP/2 upgrade
	    dict update request headers hdrs {
		foreach {name value} [www::http2 headers] {
		    header append hdrs $name $value
		}
	    }
	}

	lappend pending [dict create Request $request Attempt 0]
	return $request
    }
}

oo::define www::connection {
    mixin -append www::http2helper
}

namespace eval www::http2 {
    variable defaultsettings {
	tablesize	4096
	pushenable	1
	maxstreams	2147483647
	windowsize	65536
	maxframesize	16384
	maxtablesize	2147483647
    }
    variable preferredsettings {
	tablesize	65536
	pushenable	0
	maxstreams	100
	windowsize	1048576
	maxtablesize	262144
    }
    variable errorcodes {
	NO_ERROR
	PROTOCOL_ERROR
	INTERNAL_ERROR
	FLOW_CONTROL_ERROR
	SETTINGS_TIMEOUT
	STREAM_CLOSED
	FRAME_SIZE_ERROR
	REFUSED_STREAM
	CANCEL
	COMPRESSION_ERROR
	CONNECT_ERROR
	ENHANCE_YOUR_CALM
	INADEQUATE_SECURITY
	HTTP_1_1_REQUIRED
    }
    variable fixed {
	{""}
	{:authority}
	{:method GET}
	{:method POST}
	{:path /}
	{:path /index.html}
	{:scheme http}
	{:scheme https}
	{:status 200}
	{:status 204}
	{:status 206}
	{:status 304}
	{:status 400}
	{:status 404}
	{:status 500}
	{accept-charset}
	{accept-encoding "gzip, deflate"}
	{accept-language}
	{accept-ranges}
	{accept}
	{access-control-allow-origin}
	{age}
	{allow}
	{authorization}
	{cache-control}
	{content-disposition}
	{content-encoding}
	{content-language}
	{content-length}
	{content-location}
	{content-range}
	{content-type}
	{cookie}
	{date}
	{etag}
	{expect}
	{expires}
	{from}
	{host}
	{if-match}
	{if-modified-since}
	{if-none-match}
	{if-range}
	{if-unmodified-since}
	{last-modified}
	{link}
	{location}
	{max-forwards}
	{proxy-authenticate}
	{proxy-authorization}
	{range}
	{referer}
	{refresh}
	{retry-after}
	{server}
	{set-cookie}
	{strict-transport-security}
	{transfer-encoding}
	{user-agent}
	{vary}
	{via}
	{www-authenticate}
    }
}

namespace eval www::http2::huffman {
    namespace ensemble create -subcommands {decode encode}
    variable map {
	1111111111000			\x00
	11111111111111111011000		\x01
	1111111111111111111111100010	\x02
	1111111111111111111111100011	\x03
	1111111111111111111111100100	\x04
	1111111111111111111111100101	\x05
	1111111111111111111111100110	\x06
	1111111111111111111111100111	\x07
	1111111111111111111111101000	\x08
	111111111111111111101010	\x09
	111111111111111111111111111100	\x0A
	1111111111111111111111101001	\x0B
	1111111111111111111111101010	\x0C
	111111111111111111111111111101	\x0D
	1111111111111111111111101011	\x0E
	1111111111111111111111101100	\x0F
	1111111111111111111111101101	\x10
	1111111111111111111111101110	\x11
	1111111111111111111111101111	\x12
	1111111111111111111111110000	\x13
	1111111111111111111111110001	\x14
	1111111111111111111111110010	\x15
	111111111111111111111111111110	\x16
	1111111111111111111111110011	\x17
	1111111111111111111111110100	\x18
	1111111111111111111111110101	\x19
	1111111111111111111111110110	\x1A
	1111111111111111111111110111	\x1B
	1111111111111111111111111000	\x1C
	1111111111111111111111111001	\x1D
	1111111111111111111111111010	\x1E
	1111111111111111111111111011	\x1F
	010100				\x20
	1111111000			\x21
	1111111001			\x22
	111111111010			\X23
	1111111111001			\x24
	010101				\x25
	11111000			\x26
	11111111010			\x27
	1111111010			\x28
	1111111011			\x29
	11111001			\x2A
	11111111011			\x2B
	11111010			\x2C
	010110				\x2D
	010111				\x2E
	011000				\x2F
	00000				\x30
	00001				\x31
	00010				\x32
	011001				\x33
	011010				\x34
	011011				\x35
	011100				\x36
	011101				\x37
	011110				\x38
	011111				\x39
	1011100				\x3A
	11111011			\x3B
	111111111111100			\x3C
	100000				\x3D
	111111111011			\x3E
	1111111100			\x3F
	1111111111010			\x40
	100001				\x41
	1011101				\x42
	1011110				\x43
	1011111				\x44
	1100000				\x45
	1100001				\x46
	1100010				\x47
	1100011				\x48
	1100100				\x49
	1100101				\x4A
	1100110				\x4B
	1100111				\x4C
	1101000				\x4D
	1101001				\x4E
	1101010				\x4F
	1101011				\x50
	1101100				\x51
	1101101				\x52
	1101110				\x53
	1101111				\x54
	1110000				\x55
	1110001				\x56
	1110010				\x57
	11111100			\x58
	1110011				\x59
	11111101			\x5A
	1111111111011			\x5B
	1111111111111110000		\x5C
	1111111111100			\x5D
	11111111111100			\x5E
	100010				\x5F
	111111111111101			\x60
	00011				\x61
	100011				\x62
	00100				\x63
	100100				\x64
	00101				\x65
	100101				\x66
	100110				\x67
	100111				\x68
	00110				\x69
	1110100				\x6A
	1110101				\x6B
	101000				\x6C
	101001				\x6D
	101010				\x6E
	00111				\x6F
	101011				\x70
	1110110				\x71
	101100				\x72
	01000				\x73
	01001				\x74
	101101				\x75
	1110111				\x76
	1111000				\x77
	1111001				\x78
	1111010				\x79
	1111011				\x7A
	111111111111110			\x7B
	11111111100			\x7C
	11111111111101			\x7D
	1111111111101			\x7E
	1111111111111111111111111100	\x7F
	11111111111111100110		\x80
	1111111111111111010010		\x81
	11111111111111100111		\x82
	11111111111111101000		\x83
	1111111111111111010011		\x84
	1111111111111111010100		\x85
	1111111111111111010101		\x86
	11111111111111111011001		\x87
	1111111111111111010110		\x88
	11111111111111111011010		\x89
	11111111111111111011011		\x8A
	11111111111111111011100		\x8B
	11111111111111111011101		\x8C
	11111111111111111011110		\x8D
	111111111111111111101011	\x8E
	11111111111111111011111		\x8F
	111111111111111111101100	\x90
	111111111111111111101101	\x91
	1111111111111111010111		\x92
	11111111111111111100000		\x93
	111111111111111111101110	\x94
	11111111111111111100001		\x95
	11111111111111111100010		\x96
	11111111111111111100011		\x97
	11111111111111111100100		\x98
	111111111111111011100		\x99
	1111111111111111011000		\x9A
	11111111111111111100101		\x9B
	1111111111111111011001		\x9C
	11111111111111111100110		\x9D
	11111111111111111100111		\x9E
	111111111111111111101111	\x9F
	1111111111111111011010		\xA0
	111111111111111011101		\xA1
	11111111111111101001		\xA2
	1111111111111111011011		\xA3
	1111111111111111011100		\xA4
	11111111111111111101000		\xA5
	11111111111111111101001		\xA6
	111111111111111011110		\xA7
	11111111111111111101010		\xA8
	1111111111111111011101		\xA9
	1111111111111111011110		\xAA
	111111111111111111110000	\xAB
	111111111111111011111		\xAC
	1111111111111111011111		\xAD
	11111111111111111101011		\xAE
	11111111111111111101100		\xAF
	111111111111111100000		\xB0
	111111111111111100001		\xB1
	1111111111111111100000		\xB2
	111111111111111100010		\xB3
	11111111111111111101101		\xB4
	1111111111111111100001		\xB5
	11111111111111111101110		\xB6
	11111111111111111101111		\xB7
	11111111111111101010		\xB8
	1111111111111111100010		\xB9
	1111111111111111100011		\xBA
	1111111111111111100100		\xBB
	11111111111111111110000		\xBC
	1111111111111111100101		\xBD
	1111111111111111100110		\xBE
	11111111111111111110001		\xBF
	11111111111111111111100000	\xC0
	11111111111111111111100001	\xC1
	11111111111111101011		\xC2
	1111111111111110001		\xC3
	1111111111111111100111		\xC4
	11111111111111111110010		\xC5
	1111111111111111101000		\xC6
	1111111111111111111101100	\xC7
	11111111111111111111100010	\xC8
	11111111111111111111100011	\xC9
	11111111111111111111100100	\xCA
	111111111111111111111011110	\xCB
	111111111111111111111011111	\xCC
	11111111111111111111100101	\xCD
	111111111111111111110001	\xCE
	1111111111111111111101101	\xCF
	1111111111111110010		\xD0
	111111111111111100011		\xD1
	11111111111111111111100110	\xD2
	111111111111111111111100000	\xD3
	111111111111111111111100001	\xD4
	11111111111111111111100111	\xD5
	111111111111111111111100010	\xD6
	111111111111111111110010	\xD7
	111111111111111100100		\xD8
	111111111111111100101		\xD9
	11111111111111111111101000	\xDA
	11111111111111111111101001	\xDB
	1111111111111111111111111101	\xDC
	111111111111111111111100011	\xDD
	111111111111111111111100100	\xDE
	111111111111111111111100101	\xDF
	11111111111111101100		\xE0
	111111111111111111110011	\xE1
	11111111111111101101		\xE2
	111111111111111100110		\xE3
	1111111111111111101001		\xE4
	111111111111111100111		\xE5
	111111111111111101000		\xE6
	11111111111111111110011		\xE7
	1111111111111111101010		\xE8
	1111111111111111101011		\xE9
	1111111111111111111101110	\xEA
	1111111111111111111101111	\xEB
	111111111111111111110100	\xEC
	111111111111111111110101	\xED
	11111111111111111111101010	\xEE
	11111111111111111110100		\xEF
	11111111111111111111101011	\xF0
	111111111111111111111100110	\xF1
	11111111111111111111101100	\xF2
	11111111111111111111101101	\xF3
	111111111111111111111100111	\xF4
	111111111111111111111101000	\xF5
	111111111111111111111101001	\xF6
	111111111111111111111101010	\xF7
	111111111111111111111101011	\xF8
	1111111111111111111111111110	\xF9
	111111111111111111111101100	\xFA
	111111111111111111111101101	\xFB
	111111111111111111111101110	\xFC
	111111111111111111111101111	\xFD
	111111111111111111111110000	\xFE
	11111111111111111111101110	\xFF
    }
    variable rmap [lreverse $map]
    lappend map 111111111111111111111111111111 \x00
}

proc www::http2::huffman::decode {data} {
    variable map
    binary scan $data B* bits
    append bits 111111111111111111111111111111
    set str [regsub \0001*$ [string map $map $bits] {}]
    return [encoding convertfrom utf-8 $str]
}

proc www::http2::huffman::encode {str {utf8 0}} {
    variable rmap
    if {!$utf8} {set str [encoding convertto utf-8 $str]}
    set bits [string map $rmap $str]
    append bits [string repeat 1 [expr {-[string length $bits] % 8}]]
    return [binary format B* $bits]
}

proc www::http2::errormessage {code} {
    variable errorcodes
    set str [lindex $errorcodes $code]
    if {$str eq ""} {set str "UNKNOWN_ERROR_CODE_$code"}
    return $str
}

proc www::http2::errorcode {value} {
    variable errorcodes
    set code [lsearch -exact $errorcodes $value]
    if {$code < 0 && $value ne "INTERNAL_ERROR"} {
	tailcall errorcode INTERNAL_ERROR
    }
    return $code
}

proc www::http2::integer {var cnt} {
    upvar 1 $var data
    set mask [expr {(1 << $cnt) - 1}]
    binary scan $data cu integer
    set integer [expr {$integer & $mask}]
    set i 1
    if {$integer == $mask} {
	while 1 {
	    binary scan [string index $data $i] cu next
	    set integer [expr {$integer + (($next & 0x7f) << 7 * ($i - 1))}]
	    incr i
	    if {($next & 0x80) == 0} break
	}
    }
    set data [string range $data $i end]
    return $integer
}

proc www::http2::makeint {num cnt {flags 0}} {
    set mask [expr {(1 << $cnt) - 1}]
    if {$num < $mask} {
	lappend rc [expr {$num | $flags << $cnt}]
    } else {
	lappend rc [expr {$mask | $flags << $cnt}]
	set num [expr {$num - $mask}]
	while {$num >= 128} {
	    lappend rc [expr {$num & 0x7f | 0x80}]
	    set num [expr {$num >> 7}]
	}
	lappend rc $num
    }
    return [binary format c* $rc]
}

proc www::http2::makestr {str} {
    set data [encoding convertto utf-8 $str]
    set huff [huffman encode $data 1]
    if {[string length $huff] < [string length $data]} {
	return [makeint [string length $huff] 7 1]$huff
    } else {
	return [makeint [string length $data] 7 0]$data
    }
}

proc www::http2::strlen {str} {
    set len [string length [encoding convertto utf-8 $str]]
    return [expr {$len + [string length [makeint $len 7]]}]
}

oo::class create www::http2 {
    method Startup {headers} {
	log "HTTP/2 connection: [self]"
	namespace path [linsert [namespace path] 0 ::www::http2]
	namespace upvar ::www::http2 \
	  defaultsettings default preferredsettings prefs
	my variable fd space limit
	variable data "" stream {} laststream -1 lastreceived 0
	variable backlog {} continuation 0 concurrent 0
	# Connection windows start at 64k
	set space(0) 65536	;# Receiving window
	set limit(0) 65536	;# Sending window
	# Initialize the header compression tables
	variable context
	dict set context compress \
	  [dict create table $::www::http2::fixed size 0 maxsize 4096]
	dict set context decompress \
	  [dict create table $::www::http2::fixed size 0 maxsize 4096]
	# Set initial local and remote settings
	variable settings $default remote $default
	fconfigure $fd -translation binary -buffering none -blocking 0
	# Send magic
	log "[self] Startup: PRI * HTTP/2.0\\r\\n\\r\\nSM\\r\\n\\r\\n"
	puts -nonewline $fd "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
	my ChangeSettings $prefs
	if {[header exists $headers upgrade]} {
	    # Upgrade from HTTP/1.1 to HTTP/2
	    set request [my PopRequest]
	    # The HTTP/1.1 request that is sent prior to upgrade is assigned
	    # a stream identifier of 1 with default priority values. Stream 1
	    # is implicitly "half-closed" from the client toward the server,
	    # since the request is completed as an HTTP/1.1 request.
	    # (RFC7540 3.2)
	    set laststream 1
	    set coro [my StartStream 1 half_closed_local]
	    $coro request [dict get $request Request] upgrade
	}
	# Process any HTTP/2 frames the server may have sent along with the 101
	if {[my Trap my Frame]} {
	    # Set the connection window size to 16MB
	    my ResizeWindow 0 16777216
	    fileevent $fd readable [callback Trap my Frame]
	    # Pick up any requests that have already been queued
	    my Process
	}
    }

    method ConnectionError {type msg} {
	my variable lastreceived
	log "ConnectionError $type $msg"
	# Send GoAway message
	my SendFrame 0 7 0b0 \
	  [binary format IIa* $lastreceived [errorcode $type] $msg]
	# After sending the GOAWAY frame for an error condition, the endpoint
	# MUST close the TCP connection. (RFC7540 5.4.1)
	if {$type ne "NO_ERROR"} {my destroy}
    }

    method StreamError {sid type msg} {
	log "StreamError ($sid): $type $msg"
	# Send RST_STREAM message
	my SendFrame $sid 3 0b0 [binary format I [errorcode $type]]
    }

    method PackString {var} {
	upvar 1 $var data
	binary scan $data B encoded
	set len [integer data 7]
	set str [string range $data 0 [expr {$len - 1}]]
	if {$encoded} {set str [huffman decode $str]}
	set data [string range $data $len end]
	return $str
    }

    method Index {op name value} {
	my variable context
	set index [llength $::www::http2::fixed]
	dict with context $op {
	    set table [linsert $table $index [list $name $value]]
	    incr size [expr {[strlen $name] + [strlen $value] + 32}]
	}
	return [my Evict $op]
    }

    method Evict {op} {
	my variable context
	dict with context $op {
	    while {$size > $maxsize} {
		lassign [lindex $table end] name value
		set table [lrange $table 0 end-1]
		incr size [expr {-([strlen $name] + [strlen $value] + 32)}]
	    }
	}
	return $table
    }

    method ChangeSettings {request} {
	my variable settings waitack
	my SendFrame 0 4 0b0 [http2 settings $request $settings]
	set waitack $request
    }

    method ResizeWindow {stream size} {
	my variable space
	set incr [expr {$size - $space($stream)}]
	if {$incr > 0} {
	    my SendFrame $stream 8 0b0 [binary format I $incr]
	    set space($stream) $size
	}
    }

    method Trap {args} {
	try $args trap {WWW HTTP2 CONNECTIONERROR} {msg info} {
	    my ConnectionError [lindex [dict get $info -errorcode] 3] $msg
	    return 0
	} on error {msg info} {
	    log "Trap: $msg\
	      ([dict get $info -errorcode])\n[dict get $info -errorinfo]"
	    my ConnectionError INTERNAL_ERROR $msg
	    return 0
	}
	return 1
    }

    method Frame {} {
	my variable fd stream data continuation
	if {[eof $fd]} {
	    my destroy
	    return
	}
	append data [read $fd]
	while {[string length $data] >= 9} {
	    binary scan $data IuXcub8Iu len type flags sid
	    set len [expr {$len >> 8}]
	    if {[string length $data] < 9 + $len} return
	    set payload [string range $data 9 [expr {9 + $len - 1}]]
	    if {$type} {
		binary scan $payload H* hex
		log [format {< (%s %d) %d %s %s} \
		  [self] $sid $type [string reverse $flags] $hex]
	    } elseif {[binary scan $payload H40 hex]} {
		log [format {< (%s %d) %d %s %s... <%d bytes>} [self] $sid \
		  $type [string reverse $flags] $hex [string length $payload]]
	    } else {
		binary scan $payload H* hex
		log [format {< (%s %d) %d %s %s} \
		  [self] $sid $type [string reverse $flags] $hex]
	    }
	    set data [string range $data [expr {9 + $len}] end]

	    if {$continuation} {
		# A receiver MUST treat the receipt of any other type of frame
		# or a frame on a different stream as a connection error of
		# type PROTOCOL_ERROR. (RFC7540 6.2)
		if {$type != 9 || $sid != $continuation} {
		    throw {WWW HTTP2 CONNECTIONERROR PROTOCOL_ERROR} \
		      "unexpected non-CONTINUATION frame or stream_id is invalid"
		}
	    }
	    if {$sid} {
		if {[dict exists $stream $sid coro]} {
		    [dict get $stream $sid coro] message $type $flags $payload
		} else {
		    log "Message for closed stream $sid"
		}
	    } else {
		# Stream 0: connection
		switch $type {
		    4 {
			# Settings
			my Settings $flags $payload
		    }
		    6 {
			# Ping
			my Ping $flags $payload
		    }
		    7 {
			# GoAway
			my GoAway $flags $payload
		    }
		    8 {
			# WindowUpdate
			my WindowUpdate 0 $payload
		    }
		}
	    }
	}
    }

    method ClientStream {} {
	my variable laststream
	# Clients only use odd numbered streams
	return [my StartStream [incr laststream 2]]
    }

    method StartStream {sid {state idle}} {
	my variable stream
	set coro stream$sid
	dict set stream $sid coro $coro
	dict set stream $sid weight 16
	dict set stream $sid parent 0
	dict set stream $sid deps {}
	dict set stream $sid state idle
	coroutine $coro my Stream $sid $state
	return $coro
    }

    method Stream {sid state} {
	my variable stream settings remote space limit backlog
	set space($sid) [dict get $settings windowsize]
	set limit($sid) [dict get $remote windowsize]
	set result {}
	set id {}
	set promise 0
	set cmd list
	my StateTransition $state
	try {
	    while {[dict get $stream $sid state] ne "closed"} {
		set args [lassign [yieldto {*}$cmd] event]
		set cmd list
		switch $event {
		    message {
			my Message {*}$args
			if {$promise} {set flags [lindex $args 1]}
		    }
		    promise {
			my StateTransition reserved_remote
			my Continuation {*}$args
			set promise 1
			set flags [lindex $args 0]
		    }
		    request {
			set tags [lassign $args request]
			dict set result Request $request
			if {"upgrade" ni $tags} {my Transmit $sid $request}
		    }
		    failed {
			throw {*}$args
		    }
		    close {
			break
		    }
		}
		if {$promise && [string index $flags 2]} {
		    # Push promise headers complete
		    # The headers received until now belong to the request
		    dict set result Request headers [dict get result headers]
		    dict unset result headers
		    # Check for some mandatory parts
		    foreach key {method scheme host resource} {
			if {![dict exists result $key]} {
			    throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
			      "missing mandatory request header: $key"
			}
		    }

		}
	    }
	    my Return $result
	} trap {WWW DATA TIMEOUT} {msg info} {
	    my StreamError $sid CANCEL $msg
	    my Failed [dict get $info -errorcode] $msg $sid
	} trap {WWW HTTP2 STREAMERROR} {msg info} {
	    set type [lindex [dict get $info -errorcode] 3]
	    my StreamError $sid $type $msg
	    my Failed [dict get $info -errorcode] $msg $sid
	} on error {msg info} {
	    my StreamError $sid INTERNAL_ERROR $msg
	    my Failed [dict get $info -errorcode] $msg $sid
	} finally {
	    # Cleanup
	    unset space($sid) limit($sid)
	    dict unset backlog $sid
	    dict unset stream $sid coro
	    my StateTransition closed
	    # Keep streams that have dependencies for load sharing purposes
	    for {
		set num $sid
	    } {
		[dict get $stream $sid state] eq "closed" \
		  && [llength [dict get $stream $num deps]] == 0
	    } {
		set num $parent
	    } {
		set parent [dict get $stream $num parent]
		dict unset stream $num
		if {$parent == 0} break
		dict update stream $parent ref {
		    dict set ref deps \
		      [lsearch -all -inline -exact -not [dict get $ref deps] $num]
		}
	    }
	}
    }

    method StreamId {} {
	upvar #1 sid sid
	return $sid
    }

    method Result {args} {
	upvar #1 result result
	if {[llength $args] > 1} {
	    dict set result {*}$args
	} elseif {[llength $args] == 0} {
	    return $result
	} elseif {[dict exists $result {*}$args]} {
	    return [dict get $result {*}$args]
	}
	return
    }

    method Timeout {} {
	my variable timeout
	upvar #1 request request
	if {[dict exists $request timeout]} {
	    return [dict get $request timeout]
	} else {
	    return $timeout
	}
    }

    method Timedout {sid} {
	my variable stream
	if {[dict exists $stream $sid coro]} {
	    set coro [dict get $stream $sid coro]
	    $coro failed {WWW DATA TIMEOUT} "timeout waiting for a response"
	}
    }

    method Failed {code msg {sid 0}} {
	if {$sid} {
	    set callback [dict get [my Result Request] callback]
	    set opts [dict create -code 1 -level 1 -errorcode $code]
	    $callback -options $opts $msg
	} else {
	    my variable stream
	    set type INTERNAL_ERROR
	    foreach n1 $code n2 {WWW HTTP2 CONNECTIONERROR} {
		if {$n1 eq $n2} continue
		if {$n2 eq ""} {set type $n1}
		break
	    }
	    my ConnectionError $type $msg
	    dict for {sid dict} $stream {
		if {[dict exists $dict coro]} {
		    [dict get $dict coro] failed $code $msg
		}
	    }
	}
    }

    method Message {type flags payload} {
	switch $type {
	    0 {
		# Data
		my Data $flags $payload
	    }
	    1 {
		# Headers
		my Headers $flags $payload
	    }
	    2 {
		# Priority
		my Priority $flags $payload
	    }
	    3 {
		# ResetStream
		my ResetStream $flags $payload
	    }
	    5 {
		# PushPromise
		my PushPromise $flags $payload
	    }
	    8 {
		# WindowUpdate
		my WindowUpdate [my StreamId] $payload
	    }
	    9 {
		# Continuation
		my Continuation $flags $payload
	    }
	    4 - 6 - 7 {
		# Settings
		# Ping
		# GoAway
		throw {WWW HTTP2 CONNECTIONERROR PROTOCOL_ERROR} \
		  "message may not be associated with an individual stream"
	    }
	}
    }

    method Data {flags data} {
	set sid [my StreamId]
	my ValidStates STREAM_CLOSED open half_closed_local
	my variable space settings
	if {[string index $flags 3]} {
	    binary scan $data cu padding
	    set data [string range $data 1 [expr {$len - $padding - 1}]]
	}
	my Progress $data
	set diff [expr {-[string length $data]}]
	if {[incr space($sid) $diff] < [dict get $settings windowsize] / 2} {
	    my ResizeWindow $sid [dict get $settings windowsize]
	}
	if {[incr space(0) $diff] < 1048576} {
	    my ResizeWindow 0 16777216
	}
	if {[string index $flags 0]} {
	    # Check content-length header, if present?
	    # The body may have a different length due to encoding
	    # throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
	    #   "content-length mismatch"
	    my EndStream
	}
    }

    method Headers {flags data} {
	my ValidStates PROTOCOL_ERROR \
	  idle reserved_remote open half_closed_local
	my StateTransition idle open reserved_remote half_closed_local
	if {[string index $flags 3]} {
	    # Padded
	    set len [string length $data]
	    if {[string index $flags 5]} {
		# Priority
		binary scan $data cuBXIucu padding excl dep weight
		set data [string range $data 6 [expr {$len - $padding - 1}]]
		my Prioritize [my StreamId] \
		  [expr {$dep & 0x7fffffff}] $excl $weight
	    } else {
		binary scan $data cu padding
		set data [string range $data 1 [expr {$len - $padding - 1}]]
	    }
	} elseif {[string index $flags 5]} {
	    # Priority
	    binary scan $data Iucu dep weight
	    set data [string range $data 5 end]
	}
	if {[string index $flags 0]} {my EndStream}
	my Continuation $flags $data
    }

    method Priority {flags data} {
	binary scan $data BXIucu excl dep weight
	my Prioritize [my StreamId] [expr {$dep & 0x7fffffff}] $excl $weight
    }

    method ResetStream {flags data} {
	my StateTransition closed
	binary scan $data Iu code
	log "Reset stream: Code = $code"
    }

    method Settings {flags data} {
	my variable settings remote waitack space limit
	if {[string index $flags 0]} {
	    if {![info exists waitack]} {
		# ERROR: There is no settings update pending
		return
	    }
	    # Our settings update has been accepted
	    if {[dict exists $waitack windowsize]} {
		# Adjust the window sizes for all existing streams
		set diff [expr {[dict get $waitack windowsize] \
		  - [dict get $settings windowsize]}]
		foreach n [array names space] {
		    if {$n} {incr space($n) $diff}
		}
	    }
	    set settings [dict merge $settings $waitack]
	    unset waitack
	    return
	}
	while {[binary scan $data SuIu id value] == 2} {
	    switch $id {
		1 {
		    # SETTINGS_HEADER_TABLE_SIZE
		    dict set remote tablesize $value
		}
		2 {
		    # SETTINGS_ENABLE_PUSH
		    if {$value <= 1} {
			dict set remote pushenable $value
		    } else {
			throw {WWW HTTP2 CONNECTIONERROR PROTOCOL_ERROR} \
			  "invalid value for SETTINGS_ENABLE_PUSH: $value"
		    }
		}
		3 {
		    # SETTINGS_MAX_CONCURRENT_STREAMS
		    dict set remote maxstreams $value
		}
		4 {
		    # SETTINGS_INITIAL_WINDOW_SIZE
		    set diff [expr {$value - [dict get $remote windowsize]}]
		    # Adjust all existing streams
		    foreach n [array names limit] {
			if {$n} {incr limit($n) $diff}
		    }
		    dict set remote windowsize $value
		}
		5 {
		    # SETTINGS_MAX_FRAME_SIZE
		    dict set remote maxframesize $value
		}
		6 {
		    # SETTINGS_MAX_HEADER_LIST_SIZE
		    dict set remote maxtablesize $value
		}
	    }
	    set data [string range $data 6 end]
	}
	if {$data ne ""} {
	    throw {WWW HTTP2 CONNECTIONERROR FRAME_SIZE_ERROR} \
	      "frame length must be a multiple of 6 octets"
	}
	# Acknowledge the received settings
	my SendFrame 0 4 0b1
    }

    method PushPromise {flags data} {
	my variable lastreceived
	my ValidStates PROTOCOL_ERROR open half_closed_local
	if {[string index $flags 3]} {
	    set len [string length $data]
	    binary scan $data cuIu padding new
	    set data [string range $data 5 [expr {$len - $padding - 1}]]
	} else {
	    binary scan $data Iu new
	    set data [string range $data 4 end]
	}
	# Streams initiated by the server MUST use even-numbered stream
	# identifiers. The identifier of a newly established stream MUST be
	# numerically greater than all streams that the initiating endpoint
	# has opened or reserved. An endpoint that receives an unexpected
	# stream identifier MUST respond with a connection error of type
	# PROTOCOL_ERROR. (RFC7540 5.1.1)
	if {$new % 2 || $new <= $lastreceived} {
	    throw {WWW HTTP2 CONNECTIONERROR PROTOCOL_ERROR} \
	      "unexpected stream identifier: $new"
	}
	set lastreceived $new
	set coro [my StartStream $new]
	coro promise $flags $data
    }

    method Ping {flags data} {
	if {[string index $flags 0]} {
	    # Received ping ACK
	} else {
	    # Received ping, send ACK
	    my SendFrame 0 6 0b1 $data
	}
    }

    method GoAway {flags data} {
	binary scan $data IuIua* last code msg
	log "GoAway: Code = [errormessage $code], Last stream = $last, $msg"
	my SendFrame 0 7 0b0 [binary format II $last 0]
    }

    method WindowUpdate {sid data} {
	my variable limit backlog
	# A WINDOW_UPDATE frame with a length other than 4 octets MUST be
	# treated as a connection error of type FRAME_SIZE_ERROR (RFC7540 6.9)
	if {[string length $data] != 4} {
	    throw {WWW HTTP2 CONNECTIONERROR FRAME_SIZE_ERROR} \
	      "WINDOW_UPDATE frame must have a length of 4"
	}
	binary scan $data Iu incr
	# A receiver MUST treat the receipt of a WINDOW_UPDATE frame with
	# an flow-control window increment of 0 as a stream error of type
	# PROTOCOL_ERROR ((RFC7540 6.9)
	if {$incr == 0} {
	    if {$sid} {
		throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
		  "flow-control window increment may not be 0"
	    } else {
		throw {WWW HTTP2 CONNECTIONERROR PROTOCOL_ERROR} \
		  "flow-control window increment may not be 0"
	    }
	}
	incr limit($sid) $incr
	if {$sid} {
	    if {![dict exists $backlog $sid]} return
	    if {min($limit(0), $limit($sid)) == 0} return
	} else {
	    if {[dict size $backlog] == 0} return
	}
	# Resume sending data, if necessary
	fileevent $fd writable [callback Flow]
    }

    method Continuation {flags data} {
	my variable context continuation stream
	# header block fragment (RFC7540 4.3)
	set table [dict get $context decompress table]
	set headers [my Result headers]
	while {[string length $data]} {
	    binary scan $data B4 rep
	    if {[string index $rep 0]} {
		# Indexed Header Field Representation (RFC7541 6.1)
		set type HH
		set int [integer data 7]
		lassign [lindex $table $int] name value
	    } elseif {[string index $rep 1]} {
		# Literal Header Field with Incremental Indexing (RFC7541 6.2)
		set int [integer data 6]
		if {$int == 0} {
		    # New name
		    set type MM
		    set name [my PackString data]
		} else {
		    set type HM
		    set name [lindex $table $int 0]
		}
		set value [my PackString data]
		# Unshare the table to prevent copy on write
		set table {}
		set table [my Index decompress $name $value]
	    } elseif {[string index $rep 2]} {
		# Dynamic Table Size Update (RFC7541 6.3)
		set maxsize [integer data 5]
		dict set context decompress maxsize $maxsize
		log "New max table size: $maxsize"
		# Evict entries that cause the table to exceed the maximum size
		my Evict decompress
		continue
	    } elseif {[string index $rep 3]} {
		# Literal Header Field Never Indexed (RFC7541 6.2.3)
		set int [integer data 4]
		if {$int == 0} {
		    # New name
		    set type xx
		    set name [my PackString data]
		} else {
		    set type Hx
		    set name [lindex $table $int 0]
		}
		set value [my PackString data]
	    } else {
		# Literal Header Field without Indexing (RFC7541 6.2.2)
		set int [integer data 4]
		if {$int == 0} {
		    # New name
		    set type --
		    set name [my PackString data]
		} else {
		    set type H-
		    set name [lindex $table $int 0]
		}
		set value [my PackString data]
	    }
	    log "$type $name: $value"
	    if {$name eq ":status"} {
		# Any request or response that contains a pseudo-header field
		# that appears in a header block after a regular header field
		# MUST be treated as malformed. (RFC7540 8.1.2.1)
		if {[llength $headers]} {
		    throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
		      "pseudo-header after a regular header: $name"
		}
		# HTTP/2.0 doesn't provide a version or reason
		set dict {line "" version HTTP/2.0 reason ""}
		dict set dict code $value
		my Result status $dict
	    } elseif {[string match :* $name]} {
		switch $name {
		    :authority {my Result host $value}
		    :method {my Result method $value}
		    :path {my Result resource $value}
		    :scheme {my Result scheme $value}
		    default {
			# Endpoints MUST treat a request or response that
			# contains undefined or invalid pseudo-header fields
			# as malformed (RFC7540 8.1.2.1)
			throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
			  "undefined pseudo-header field: $name"
		    }
		}
		# These pseudo-header fields are only allowed in a PushPromise
		if {$sid % 2} {
		    throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
		      "invalid pseudo-header field: $name"
		}
		# Any request or response that contains a pseudo-header field
		# that appears in a header block after a regular header field
		# MUST be treated as malformed. (RFC7540 8.1.2.1)
		if {[llength $headers]} {
		    throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
		      "pseudo-header after a regular header: $name"
		}
	    } else {
		lappend headers $name $value
	    }
	}
	my Result headers $headers
	# Check END_HEADERS flag
	if {[string index $flags 2] == 0} {
	    set continuation [my StreamId]
	    return
	}
	set continuation 0
	set enc [header get $headers content-encoding all -lowercase]
	my Result Encoding [lmap name [lreverse $enc] {
	    set coro encodingcoro_$name
	    coroutine $coro {*}[encodingcmd $name]
	    set coro
	}]
    }

    method ValidStates {code args} {
	set state [my StateTransition]
	if {$state ni $args} {
	    throw [list WWW HTTP2 STREAMERROR $code] \
	      "illegal frame type for the current state: $state"
	}
    }

    method StateTransition {args} {
	my variable stream concurrent
	set sid [my StreamId]
	set state [dict get $stream $sid state]
	set from $state
	if {[llength $args] == 1} {
	    set state [lindex $args 0]
	} elseif {[dict exists $args $state]} {
	    set state [dict get $args $state]
	}
	if {$state ne $from} {
	    # Update the number of concurrently active streams
	    set open {open half_closed_local half_closed_remote}
	    incr concurrent [expr {($state in $open) - ($from in $open)}]
	    log "State ($sid): $from -> $state\nActive streams = $concurrent"
	    dict set stream $sid state $state
	}
	return $state
    }

    method EndStream {} {
	upvar #1 id id
	# Cancel the response timeout
	after cancel $id
	my StateTransition open half_closed_remote half_closed_local closed
    }

    method Prioritize {sid dep excl weight} {
	my variable stream
	if {$dep == $sid} {
	    throw {WWW HTTP2 STREAMERROR PROTOCOL_ERROR} \
	      "a stream cannot depend on itself"
	    # my StreamError $sid PROTOCOL_ERROR
	    return
	}
	set s [dict get $stream $dep parent]
	while {$s} {
	    if {$s == $sid} {
		# Prevent imminent dependency loop: "The formerly dependent
		# stream is first moved to be dependent on the reprioritized
		# stream's previous parent. The moved dependency retains its
		# weight." (RFC7540 5.3.3)
		my Prioritize $dep [dict get $stream $sid parent] 0 \
		  [dict get $stream $dep weight]
		break
	    }
	    set s [dict get $stream $s parent]
	}
	set parent [dict get $stream $sid parent]
	if {$parent && $dep != $parent} {
	    dict update stream $parent ref {
		# Remove the stream from the depency list of the old parent
		dict set ref deps \
		  [lsearch -all -inline -exact -not [dict get $ref deps] $sid]
	    }
	}
	if {$dep} {
	    if {$excl} {
		set deps [dict get $stream $dep deps]
		# This stream is the sole dependent stream of its parent
		dict set stream $dep deps [list $sid]
		# Add the old dependencies to this stream
		dict update stream $sid ref {
		    foreach n $deps {
			if {$n ni [dict get $ref deps]} {
			    dict lappend ref deps $n
			}
		    }
		}
	    } else {
		dict update stream $dep ref {
		    if {$sid ni [dict get $ref deps]} {
			dict lappend ref deps $sid
		    }
		}
	    }
	} elseif {$excl} {
	    set deps {}
	    dict for {ref data} $stream {
		if {$ref != sid && [dict get $data parent] == 0} {
		    lappend deps $ref
		    dict set stream $ref parent $sid
		}
	    }
	    dict set stream $sid deps $deps
	}
	dict set stream $sid parent $dep
	dict set stream $sid weight $weight
    }

    method Transmit {sid request} {
	my variable fd remote
	upvar #1 id id
	set method [string toupper [dict get $request method]]
	my StateTransition idle open reserved_local half_closed_remote
	set rc [my Header :method $method]
	if {$method ni {CONNECT}} {
	    # Don't expect repeated request for the same path; don't index it
	    append rc [my Header :path [dict get $request resource] 0]
	    append rc [my Header :scheme [dict get $request scheme]]
	}
	append rc [my Header :authority [dict get $request host]]
	set headers [dict get $request headers]
	# Do not include connection-specific header fields
	set skip \
	  {connection keep-alive proxy-connection transfer-encoding upgrade}
	foreach n [header get $headers connection all] {
	    if {$n ni $skip} {lappend skip $n}
	}
	set size [string length $rc]
	set end [expr {![dict exists $request body]}]
	if {$end} {
	    my StateTransition \
	      open half_closed_local half_closed_remote closed
	}
	# Don't index headers that likely have a different value every time
	set dynamic {date if-none-match}
	set type 1
	foreach {name value} $headers {
	    set name [string tolower $name]
	    if {$name in $skip} continue
	    if {$name eq "cookie"} {
		# Compressing the Cookie Header Field (RFC7540 8.1.2.5)
		set str ""
		foreach val [split $value {;}] {
		    append str [my Header $name [string trim $val]]
		}
	    } else {
		set str [my Header $name $value [expr {$name ni $dynamic}]]
	    }
	    # Keep frame size below limits
	    set add [string length $str]
	    if {$size + $add > [dict get $remote maxframesize]} {
		# Send the partial headers
		my SendFrame $sid $type $end $rc
		# Additional parts will be in a CONTINUATION frames
		set type 9
		set end 0
		set rc ""
		set size 0
	    }
	    append rc $str
	    incr size $add
	}
	my SendFrame $sid $type [expr {$end | 0b100}] $rc
	set id [after [my Timeout] [callback Timedout $sid]]
	if {[dict exists $request body]} {
	    my Push $sid [dict get $request body]
	}
    }

    method Push {sid data} {
	my variable backlog fd
	dict update backlog $sid dict {
	    dict append dict data $data
	    dict incr dict done 0
	}
	fileevent $fd writable [callback Flow]
    }

    method Flow {} {
	my variable fd backlog limit
	set sid [my Balance]
	if {$sid == 0} {
	    # No data to send, or no bandwidth left
	    fileevent $fd writable {}
	    return
	}
	dict with backlog $sid {
	    # Calculate the amount of data left to be sent
	    set len [expr {[string length $data] - $done}]
	    # Determine how much data to actually send
	    # Limit to 8k for load balancing
	    set max [expr {min($len, $limit(0), $limit($sid), 8192)}]
	    set end [expr {$max == $len}]
	    # Send the data frame
	    my SendFrame $sid 0 $end \
	      [string range $data $done [expr {$done + $max - 1}]]
	    # Keep track of what has already been sent
	    incr done $max
	}
	# Update the flow-control window administration
	incr limit(0) [expr {-$max}]
	incr limit($sid) [expr {-$max}]
	# Clean up when all data for the current stream has been sent
	if {$end} {
	    dict unset backlog $sid
	    my StateTransition open half_closed_local half_closed_remote closed
	}
    }

    method Balance {} {
	# Select a stream based on dependencies and weighting
	my variable backlog limit stream
	if {$limit(0) == 0} {
	    # All streams are blocked
	    return 0
	}
	# Create a list of streams with data waiting and available bandwidth
	set list [lmap n [dict keys $backlog] {
	    if {$limit($n)} {set n} else continue
	}]
	# Build a tree of streams and their weight
	set weight {}
	foreach n $list {
	    while {$n != 0} {
		set parent [dict get $stream $n parent]
		dict set weight $parent $n [dict get $stream $n weight]
		set n $parent
	    }
	}
	# Walk down the tree and pick a branch based on their weight
	set sid 0
	# Stop when a stream is found that has data to send
	while {[dict exists $weight $sid] && $sid ni $list} {
	    set w 0
	    set weights {}
	    dict for {num value} [dict get $weight $sid] {
		lappend weights [list $num $w]
		incr w $value
	    }
	    set v [expr {int(rand() * $w)}]
	    set index [lsearch -integer -index 1 -bisect $weights $v]
	    set sid [lindex $weights $index 0]
	}
	return $sid
    }

    method Header {name value {add 1}} {
	my variable context
	set entry 0
	set table [dict get $context compress table]
	set list [lsearch -all -exact -index 0 $table $name]
	foreach n $list {
	    if {[lindex $table $n 1] eq $value} {
		set entry $n
	    }
	}
	if {$entry} {
	    log "HH $name: $value"
	    return [makeint $entry 7 1]
	} else {
	    if {[llength $list]} {set entry [lindex $list 0]}
	    if {$add} {
		set type MM
		set rc [makeint $entry 6 1]
		my Index compress $name $value
	    } else {
		set type --
		set rc [makeint $entry 4]
	    }
	    if {$entry == 0} {
		append rc [makestr $name]
	    } else {
		set type [string replace $type 0 0 H]
	    }
	    append rc [makestr $value]
	    log "$type $name: $value"
	    return $rc
	}
    }

    method SendFrame {sid type flags {data ""}} {
	my variable fd
	set flags [format %08b $flags]
	binary scan $data H* hex
	log [format {> (%s %d) %d %s %s} [self] $sid $type $flags $hex]
	set len [string length $data]
	set frame \
	  [string range [binary format IcB8I $len $type $flags $sid] 1 end]
	append frame $data
	puts -nonewline $fd $frame
    }

    method PushRequest {} {
	# The fact that the http2 class is already mixed into the object means
	# that no upgrade has to be requested for http requests
	# Skip www::http2helper and go straight to www::connection
	nextto www::connection
    }

    # Override methods from www library
    method Process {} {
	my variable fd waiting pending concurrent settings
	if {[llength $waiting] == 0} return
	if {$concurrent >= [dict get $settings maxstreams]} return
	# Process the next request
	set waiting [lassign $waiting request]
	lappend pending [dict create Request $request Attempt 0]
	if {$fd eq ""} {
	    my Connect
	} else {
	    my Request
	}
    }

    method Request {} {
	my variable fd pending timeout id
	if {[eof $fd]} {
	    my Connect
        }
	set pending [lassign $pending transaction]
	set coro [my ClientStream]
	$coro request [dict get $transaction Request]
	my Process
    }

    method request {data} {
	nextto ::www::connection $data
    }
}

oo::objdefine www::http2 {
    method settings {new old} {
	set data ""
	dict for {key val} $old {
	    incr parameter
	    if {[dict exists $new $key] && [dict get $new $key] != $val} {
		append data [binary format SI $parameter [dict get $new $key]]
	    }
	}
	return $data
    }

    method headers {} {
	namespace upvar ::www::http2 \
	  defaultsettings defs preferredsettings prefs
	set settings [binary encode base64 [my settings $prefs $defs]]
	return [list Connection HTTP2-Settings HTTP2-Settings $settings]
    }
}
