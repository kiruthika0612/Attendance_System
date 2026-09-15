#!/usr/bin/tclsh

# This library can be used together with www 2.0+ to use a proxy based on a
# Proxy Auto Configure (pac) file:
#	package require proxypac
#	www configure -proxyfilter {proxypac <pacurl>}
# Example: http://pac.webdefence.global.blackspider.com:8082/proxy.pac

package require www

namespace eval www::proxypac {
    variable oldpac {} 
    namespace export proxypac

    proc proxypac {pacurl url host} {
	variable oldpac
	if {[string equal -length [string length $url] $pacurl $url]} {
	    # The pac url itself must be reachable directly
	    return DIRECT
	}
	try {
	    if {$pacurl ne $oldpac} {
		set data [www get $pacurl]
		set oldpac $pacurl
		parse $data
	    }
	    set proxies [execute FindProxyForURL $url $host]
	    return [lmap proxy [split $proxies {;}] {
		if {[string is space $proxy]} continue
		string trim $proxy
	    }]
	} on error {err opts} {
	    www::log "Failed to auto-configure proxy: $err"
	    # In case of any error, use a direct connection
	    return [list DIRECT]
	}
    }

    proc validip {ipchars} {
	set valid [lmap n [split $ipchars .] {
	    expr {[string is digit -strict $n] && $n < 256}
	}]
	return [expr {[join $valid ""] eq "1111"}]
    }

    proc resolve {host} {
	if {[catch {package require dns}]} return
	set tok [dns::resolve $host]
	dns::wait $tok
	set result [lindex [dns::address $tok] 0]
	dns::cleanup $tok
	return $result
    }
}

if {[catch {package require duktape::oo 0.11}]} {
    proc www::proxypac::parse {data} {
	set code [convert [string map [list \r\n \n] $data]]
	proxypacrun eval $code
    }

    proc www::proxypac::execute {args} {
	proxypacrun eval $args
    }

    proc www::proxypac::convert {data} {
	variable tokenlist
	set p 0
	set re {/[/=*]?|[*]/|[+][+=]?|[*][*]?=?|-=?|<[<=]?|>>>|>[>=]?|%=?|&&?|[|][|]?|!=?=?|={1,3}|[][(),.{}"';\n?~^]|[ \t]+}

	set tokenlist [lmap n [regexp -all -indices -inline $re $data] {
	    lassign $n x1 x2
	    set str [string range $data $p [expr {$x1 - 1}]]
	    set sep [string range $data $x1 $x2]
	    set p [expr {$x2 + 1}]
	    list $str $sep
	}]

	set code [lmap line [block] {
	    set tabs [string length [lindex [regexp -inline ^\t* $line] 0]]
	    set indent [string repeat \t [expr {$tabs / 2}]]
	    append indent [string repeat "    " [expr {$tabs % 2}]]
	    regsub ^\t* $line $indent
	}]
	return [join $code \n]
    }

    proc www::proxypac::peek {{trim 1}} {
	variable tokenlist
	variable count
	if {[incr count] > 20} {
	    fail "endless loop"
	}
	if {[llength $tokenlist] == 0} return
	lassign [lindex $tokenlist 0] str tag
	if {![string is space $tag] || !$trim} {
	    return [lindex $tokenlist 0]
	} elseif {$str ne ""} {
	    if {[lindex $tokenlist 1 0] ne ""} {
		return [lindex $tokenlist 0]
	    }
	    lset tokenlist 1 0 $str
	}
	set tokenlist [lrange $tokenlist 1 end]
	tailcall peek
    }

    proc www::proxypac::poke {str tag} {
	variable tokenlist
	lset tokenlist 0 [list $str $tag]
    }

    proc www::proxypac::next {{trim 1}} {
	variable tokenlist
	variable count 0
	set tokenlist [lrange $tokenlist 1 end]
	tailcall peek $trim
    }

    proc www::proxypac::end {} {
	variable tokenlist
	return [expr {[llength $tokenlist] == 0}]
    }

    proc www::proxypac::code {} {
	lassign [peek] str tag
	if {$str eq "" && $tag eq "\{"} {
	    next
	    lappend rc {*}[block]
	    lassign [peek] str tag
	    if {$tag ne "\}"} {
		fail "expected \}"
	    }
	    next
	} else {
	    lappend rc {*}[statement]
	}
	return $rc
    }

    proc www::proxypac::block {} {
	while {![end]} {
	    lassign [peek] str tag
	    switch $str {
		{} {
		    if {$tag in {// /*}} {
			comment
		    }
		}
		default {
		    set block [statement]
		    lappend rc {*}$block
		}
	    }
	    lassign [peek] str tag
	    if {$tag eq "\}"} {
		break
	    }
	}
	return $rc
    }

    proc www::proxypac::comment {} {
	variable tokenlist
	variable count 0
	lassign [peek] str tag
	if {$tag eq "//"} {
	    set end \n
	} else {
	    set end "*/"
	}
	set nl [lsearch -exact -index 1 $tokenlist $end]
	if {$nl < 0} {set nl end}
	set tokenlist [lreplace $tokenlist 0 $nl]
    }

    proc www::proxypac::statement {} {
	lassign [peek] str tag
	switch $str {
	    function {
		if {![string is space $tag]} {
		    fail "expected white space"
		}
		set rc [function]
	    }
	    if {
		set rc [ifelse]
	    }
	    return {
		set rc [jsreturn]
	    }
	    var {
		if {![string is space $tag]} {
		    fail "expected white space"
		}
		set rc [var]
	    }
	    for {
		if {$tag ne "("} {
		    fail "expected ("
		}
		set rc [forloop]
	    }
	    default {
		if {![regexp {^[\w$]+$} $str]} {
		    fail "unsupported JavaScript command: $str"
		} elseif {$tag eq "="} {
		    set rc [assignment $str]
		} elseif {$tag eq "("} {
		    set rc [list [funccall $str]]
		} else {
		    fail "unsupported JavaScript command: $str (tag = $tag)"
		}
	    }
	}
	lassign [peek] str tag
	if {$tag eq ";"} {
	    lassign [next] str tag
	}
	return $rc
    }

    proc www::proxypac::jsreturn {} {
	lassign [peek] str tag
	if {$str eq "" && $tag in {; \n}} {
	    return [list return]
	} else {
	    poke "" $tag
	    return [list "return [expression]"]
	}
    }

    proc www::proxypac::expression {{top 1}} {
	lassign [peek] str tag
	set rc {}
	set unary {}
	set strcat 0
	while 1 {
	    if {$str eq "" && $tag in {+ - ! ~}} {
		append unary $tag
		lassign [next] str tag
		continue
	    }
	    switch -regexp $str {
		{^$} {
		    set op [lindex $rc end]
		    if {$op eq "=="} {
			lset rc end eq
		    } elseif {$op eq "!="} {
			lset rc end ne
		    }
		    if {$tag in {\" '}} {
			set quote $tag
			set strvar ""
			while 1 {
			    lassign [next 0] str tag
			    if {$tag eq $quote} {
				append strvar $str
				break
			    } else {
				append strvar $str $tag
			    }
			}
			lappend rc [format {{%s}} $strvar]
			lassign [next] str tag
			if {$str ne ""} {
			    fail "invalid expression"
			}
			set strcat 1
		    } elseif {$tag in "("} {
			next
			lappend rc [format (%s) [expression 0]]
			lassign [peek] str tag
			if {$tag ne ")"} {
			    fail "expected )"
			}
			next
		    }
		}
		{^[\w$]+$} {
		    if {$tag eq "("} {
			lappend rc [format {[%s]} [funccall $str]]
		    } elseif {$tag eq "\["} {
			lappend rc [arrayelem $str]
		    } elseif {[string is double $str]} {
			lappend rc $str
		    } elseif {[string tolower $str] in {true false}} {
			lappend rc $str
		    } else {
			lappend rc [format {$%s} $str]
		    }
		}
		default {
		    fail "expected expression"
		}
	    }
	    lassign [peek] str tag
	    while {$tag eq "."} {
		lset rc end [method [lindex $rc end]]
		lassign [peek] str tag
	    }
	    if {$unary ne ""} {
		lset rc end $unary[lindex $rc end]
		set unary {}
	    }
	    switch $tag {
		+ - - - * - ** - / - % -
		== - != - > - < - >= - <= - ? - : -
		& - | - ^ - << - >> - && - || {
		    lappend rc $tag
		}
		=== {
		    lappend rc ==
		}
		!== {
		    lappend rc !=
		}
		>>> {
		    lappend rc >>
		}
		default {
		    break
		}
	    }
	    lassign [next] str tag
	}
	if {!$top} {
	    return [join $rc " "]
	} elseif {[llength $rc] == 1} {
	    set rc [lindex $rc 0]
	    if {[string match {{*}} $rc]} {
		return [list [string range $rc 1 end-1]]
	    } else {
		return $rc
	    }
	} elseif {!$strcat} {
	    return [format {[expr {%s}]} [join $rc " "]]
	}
	set cat {}
	set expr {}
	set rest [lassign $rc arg]
	set strcat [string match {{*}} $arg]
	if {$strcat} {
	    lappend cat $arg
	} else {
	    lappend expr $arg
	}
	foreach {op arg} $rest {
	    if {$op ne "+" || !$strcat && ![string match {{*}} $arg]} {
		lappend expr $op $arg
	    } else {
		if {[llength $expr]} {
		    if {[llength $expr] > 1} {
			lappend cat [format {[expr {%s}]} [join $expr]]
		    } else {
			lappend cat [lindex $expr 0]
		    }
		}
		set expr {}
		if {[string match {{*}} $arg]} {
		    set strcat 1
		    lappend cat $arg
		} else {
		    lappend expr $arg
		}
	    }
	}
	if {[llength $expr]} {
	    if {[llength $expr] > 1} {
		lappend cat [format {[expr {%s}]} [join $expr]]
	    } else {
		lappend cat [lindex $expr 0]
	    }
	}
	return [format {[string cat %s]} [join $cat]]
    }

    proc www::proxypac::function {} {
	lassign [next] name tag
	if {$tag ne "("} {
	    fail "expected open parenthesis"
	}
	set arglist {}
	lassign [next] str tag
	if {$str ne ""} {
	    while 1 {
		lappend arglist $str
		if {$tag eq ")"} break
		if {$tag ne ","} {
		    fail "expected , or )"
		}
		lassign [next] str tag
	    }
	} elseif {$tag ne ")"} {
	    fail "expected )"
	}
	lappend rc "proc $name [list $arglist] \{"
	lassign [next] str tag
	lappend rc {*}[indent [code]]
	lappend rc "\}"
	return $rc
    }

    proc www::proxypac::funccall {name} {
	set cmd $name
	lassign [next] str tag
	if {$str ne "" || $tag ne ")"} {
	    while 1 {
		append cmd " " [expression]
		lassign [peek] str tag
		if {$tag eq ")"} break
		if {$tag ne ","} {
		    fail "expected , or )"
		}
		next
	    }
	}
	next
	return $cmd
    }

    proc www::proxypac::ifelse {} {
	lassign [peek] str tag
	if {$tag ne "("} {
	    fail "expected ("
	}
	next
	lappend rc [format "if {%s} \{" [expression 0]]
	lassign [next] str tag
	lappend rc {*}[indent [code]]
	lassign [peek] str tag
	if {$str eq "else"} {
	    lappend rc {\} else \{}
	    lassign [next] str tag
	    lappend rc {*}[indent [code]]
	}
	lappend rc "\}"
	return $rc
    }

    proc www::proxypac::forloop {} {
	lassign [peek] str tag
	if {$tag ne "("} {
	    fail "expected ("
	}
	lassign [next] name tag
	if {$name eq "var" && [string is space $tag]} {
	    lassign [next] name tag
	}
	if {![regexp {^[\w$]+$} $name]} {
	    fail "expected identifier"
	}
	if {$tag eq "="} {
	} elseif {[string is space $tag]} {
	    lassign [next] str tag
	    if {$str ni {in of} || ![string is space $tag]} {
		fail "expected 'in' or 'of'"
	    }
	    if {$str eq "in"} {
		set op keys
	    } else {
		set op values
	    }
	    lassign [next] str tag
	    lappend rc [format "foreach %s \[dict %s $%s\] \{" $name $op $str]
	    if {$tag ne ")"} {
		fail "expected )"
	    }
	    next
	    lappend rc {*}[indent [code]]
	    lappend rc "\}"
	}
	return $rc
    }

    proc www::proxypac::method {obj} {
	lassign [next] method tag
	set cmd [format {%s %s} $method $obj]
	if {$tag eq "("} {
	    lassign [next] str tag
	    if {$str ne "" || $tag ne ")"} {
		while 1 {
		    append cmd " " [expression]
		    lassign [peek] str tag
		    if {$tag eq ")"} break
		    if {$tag ne ","} {
			fail "expected , or )"
		    }
		    next
		}
	    }
	    next
	}
	return [format {[%s]} $cmd]
    }

    proc www::proxypac::assignment {name} {
	lassign [next] str tag
	switch $str {
	    new {
		if {![string is space $tag]} {
		    fail "expected white space"
		}
		lassign [next] str tag
		switch $str {
		    Array {
			if {$tag ne "("} {
			    fail "expected ("
			}
			set cmd "dict create"
			lassign [next] str tag
			set index 0
			if {$str ne "" || $tag ne ")"} {
			    while 1 {
				append cmd " " $index " " [expression]
				incr index
				lassign [peek] str tag
				next
				if {$tag eq ","} continue
				if {$tag eq ")"} break
				fail "expected , or )"
			    }
			} else {
			    next
			}
			return [list [format {set %s [%s]} $name $cmd]]
		    }
		    default {
			fail "$str objects are not supported"
		    }
		}
	    }
	    {} {
		if {$tag eq "\["} {
		    set cmd list
		    lassign [next] str tag
		    if {$str ne "" || $tag ne "]"} {
			while 1 {
			    append cmd " " [expression]
			    lassign [peek] str tag
			    next
			    if {$tag eq ","} continue
			    if {$tag eq "\]"} break
			    fail "expected , or \]"
			}
		    }
		    return [list [format {set %s [%s]} $name $cmd]]
		}
	    }
	}
	return [list [format {set %s %s} $name [expression]]]
    }

    proc www::proxypac::var {} {
	lassign [next] str tag
	if {![regexp {^[\w$]+$} $str]} {
	    fail "expected identifier"
	}
	if {$tag in {; \n}} return
	return [assignment $str]
    }

    proc www::proxypac::arrayelem {name} {
	next
	set sub [expression]
	lassign [peek] str tag
	if {$tag ne "\]"} {
	    fail "expected \]"
	}
	next
	return [format {[dict get $%s %s]} $name $sub]
    }

    proc www::proxypac::indent {list} {
	return [lmap line $list {format \t%s $line}]
    }

    proc www::proxypac::fail {str} {
	error $str
    }

    namespace eval www::proxypac {
	interp create [namespace current]::proxypacrun
	proxypacrun alias resolve [namespace which resolve]
	proxypacrun alias validip [namespace which validip]

	proxypacrun eval {
	    proc substring {str start {end 0}} {
		if {[llength [info level 0]] < 4} {
		    set end [string length $str]
		}
		if {$start < $end} {
		    return [string range $str $start [expr {$end - 1}]]
		} else {
		    return [string range $str $end [expr {$start - 1}]]
		}
	    }

	    proc toLowerCase {str} {
		return [string tolower $str]
	    }

	    rename split tclsplit
	    proc split {str {separator ""} {limit 2147483647}} {
		if {[llength [info level 0]] == 1} {
		    set list [list $str]
		} elseif {$separator eq ""} {
		    set list [tclsplit $str ""]
		} else {
		    set list {}
		    set p 0
		    while {[set x [string first $separator $str $p]] >= 0} {
			lappend list [string range $str $p [expr {$x - 1}]]
			set p [expr {$x + [string length $separator]}]
		    }
		    lappend list [string range $str $p end]
		}
		set rc {}
		set num 0
		foreach n $list {
		    if {$num >= $limit} break
		    dict set rc $num $n
		    incr num
		}
		return $rc
	    }
	}

	proc jsfunction {name type args body} {
	    proxypacrun alias $name \
	      apply [list $args $body [namespace current]]
	    # proxypacrun eval [list proc $name $args $body]
	}
    }
} else {
    namespace eval www::proxypac {
	duktape::oo::Duktape create js

	proc parse {data} {
	    js eval $data
	}

	proc execute {args} {
	    js call {*}$args
	}

	proc jsfunction {name type args body} {
	    js tcl-function $name $type $args $body
	}
    }
}

namespace eval www::proxypac {
    variable ipaddress ""

    jsfunction isPlainHostName boolean {host} {
	return [expr {[string first . $host] < 0}]
    }

    jsfunction dnsDomainIs boolean {host domain} {
	set x [string first . $host]
	return [expr {$x >= 0 && [string range $host $x end] eq $domain}]
    }

    jsfunction localHostOrDomainIs boolean {host hostdom} {
	return \
	  [expr {$host eq $hostdom || $host eq [lindex [split $host .] 0]}]
    }

    jsfunction isValidIpAddress boolean {ipchars} {
	return [validip $ipchars]
    }

    jsfunction isResolvable boolean {host} {
	return [expr {[resolve $host] ne ""}]
    }

    jsfunction isInNet boolean {host pattern mask} {
	if {![validip $host]} {
	    set host [resolve $host]
	    if {$host eq ""} {return 0}
	}
	foreach ip1 [split $host .] ip2 [split $pattern .] m [split $mask .] {
	    if {($ip1 & $m) != ($ip2 & $m)} {return 0}
	}
	return 1
    }

    jsfunction dnsResolve string {host} {
	return [resolve $host]
    }

    jsfunction convert_addr integer {ipaddr} {
	binary scan [binary format c4 [split $ipaddr .]] Iu addr
	return $addr
    }

    jsfunction myIpAddress string {} {
	variable ipaddress
	if {$ipaddress eq ""} {
	    try {
		set fd ""
		set fd [socket -server dummy -myaddr [info hostname] 0]
		set ipaddress [lindex [fconfigure $fd -sockname] 0]
	    } on error {} {
		set ipaddress 127.0.0.1
	    } finally {
		if {$fd ne ""} {close $fd}
	    }
	}
	return $ipaddress
    }

    jsfunction dnsDomainLevels integer {host} {
	return [regexp {[.]} $host]
    }

    jsfunction shExpMatch boolean {str shexp} {
	return [string match $shexp $str]
    }

    jsfunction weekdayRange boolean {wd1 {wd2 ""} {gmt ""}} {
	set weekdays {SUN MON TUE WED THU FRI SAT}
	if {$wd2 eq "GMT"} {
	    set gmt 1
	    set match [list $wd1]
	} else {
	    set gmt [expr {$gmt eq "GMT"}]
	    set d1 [lsearch -exact $weekdays $wd1]
	    set d2 [lsearch -exact $weekdays $wd2]
	    if {$d1 < $d2} {
		set match [lrange $weekdays $d1 $d2]
	    } else {
		set match [list $wd1 $wd2]
	    }
	}
	set wd0 [clock format [clock seconds] -gmt $gmt -format %a]
	return [expr {[string toupper $wd0] in $match}]
    }

    jsfunction dateRange boolean {args} {
	set gmt [expr {[lindex $args end] eq "GMT"}]
	set len [expr {[llength $args] - $gmt}]
	if {$len < 1} {return 0}
	set now [clock seconds]
	if {$len == 1} {
	    set arg [lindex $args 0]
	    if {![string is integer -strict $arg]} {
		set mon [clock format $now -format %b -gmt $gmt]
		return [expr {$arg eq [string toupper $mon]}]
	    } elseif {$arg < 32} {
		set day [clock format $now -format %e -gmt $gmt]
		return [expr {$arg == $day}]
	    } else {
		set year [clock format $now -format %Y -gmt $gmt]
		return [expr {$arg == $year}]
	    }
	}
	lassign [clock format $now -format {%Y %b} -gmt $gmt] year month
	set d1 [list $year JAN 1 0 0 0]
	set d2 [list $year DEC 31 23 59 59]
	set middle [expr {$len / 2}]
	for {set i 0} {$i < $middle} {incr i} {
	    set arg [lindex $args $i]
	    if {![string is integer -strict $arg]} {
		lset d1 1 $arg
	    } elseif {$arg < 32} {
		lset d1 2 $arg
		if {$len <= 2} {
		    lset d1 1 $month
		    lset d2 1 $month
		}
	    } else {
		lset d1 0 $arg
	    }
	}
	for {set i $middle} {$i < $len} {incr i} {
	    set arg [lindex $args $i]
	    if {![string is integer -strict $arg]} {
		lset d2 1 $arg
	    } elseif {$arg < 32} {
		lset d2 2 $arg
	    } else {
		lset d2 0 $arg
	    }
	}
	set time1 [clock scan [join $d1 :] -format %Y:%b:%d:%T -gmt $gmt]
	set time2 [clock scan [join $d2 :] -format %Y:%b:%d:%T -gmt $gmt]
	if {$time1 < $time2} {
	    return [expr {$now >= $time1 && $now <= $time2}]
	} else {
	    return [expr {$now >= $time2 && $now <= $time1}]
	}
    }

    jsfunction timeRange boolean {args} {
	set gmt [expr {[lindex $args end] eq "GMT"}]
	set len [expr {[llength $args] - $gmt}]
	if {$len < 1} {
	    return 0
	} elseif {$len > 6 || $len == 3 || $len == 5} {
	    return -code error "timeRange: bad number of arguments"
	}
	set t1 {0 0 0}
	set t2 {23 59 59}
	set n [expr {($len + 1) / 2}]
	for {set i1 0; set i2 [expr {$len / 2}]} {$i1 < $n} {incr i1; incr i2} {
	    lset t1 $i1 [lindex $args $i1]
	    if {$i2 < $len} {
		lset t2 $i1 [lindex $args $i2]
	    }
	}
	set time1 [clock scan [join $t1 :] -format %T -gmt $gmt]
	set time2 [clock scan [join $t2 :] -format %T -gmt $gmt]
	set now [clock seconds]
	if {$time1 < $time2} {
	    return [expr {$now >= $time1 && $now <= $time2}]
	} else {
	    return [expr {$now >= $time2 && $now <= $time1}]
	}
    }

    jsfunction alert undefined {} {}
}

namespace import www::proxypac::*
