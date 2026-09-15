namespace eval www::digest {
    variable noncecount
}

# HTTP/1.1 401 Unauthorized
# WWW-Authenticate: Digest
#	realm="testrealm@host.com",
#	qop="auth,auth-int",
#	nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093",
#	opaque="5ccc069c403ebaf9f0171e9517f40e41"

proc www::digest::md5 {str} {
    package require md5
    return [string tolower [::md5::md5 -hex $str]]
}

proc www::digest::sha256 {str} {
    package require sha256
    return [::sha2::sha256 -hex $str]
}

proc www::digest::digest {challenge username password method uri {body ""}} {
    variable noncecount
    if {[dict exists $challenge algorithm]} {
	set algorithm [dict get $challenge algorithm]
    } else {
	set algorithm MD5
    }
    switch $algorithm {
	MD5 - MD5-sess {set hash md5}
	SHA-256 - SHA-256-sess {set hash sha256}
	default {
	    error "unsupported algorithm: $algorithm"
	}
    }
    set interlude [dict get $challenge nonce]
    set keys {username realm nonce uri response}
    if {[dict exists $challenge qop]} {
	set qops [split [dict get $challenge qop] ,]
	if {"auth" in $qops} {
	    set qop auth
	} elseif {"auth-int" in $qops} {
	    set qop auth-int
	} else {
	    error "unsupported qop: [join $qops {, }]"
	}
	set nonce [dict get $challenge nonce]
	# Generate a random cnonce
	set cnonce [format %08x [expr {int(rand() * 0x100000000)}]]
	set nc [format %08X [incr noncecount($nonce)]]
	append interlude : $nc : $cnonce : $qop
	lappend keys qop nc cnonce
	if {[dict exists $challenge algorithm]} {lappend keys algorithm}
	if {[dict exists $challenge opaque]} {lappend keys opaque}
    } else {
	set qop auth
    }
    foreach n $keys {
	dict set rc $n \
	  [if {[dict exists $challenge $n]} {dict get $challenge $n}]
    }
    dict set rc username $username
    dict set rc uri $uri
    if {[dict exists $rc qop]} {
	dict set rc qop $qop
	dict set rc cnonce $cnonce
	dict set rc nc $nc
    }
    set A1 [$hash $username:[dict get $challenge realm]:$password]
    if {[string match {*-sess} $algorithm]} {append A1 : $nonce : $cnonce}
    set A2 [$hash $method:$uri]
    if {$qop eq "auth-int"} {append A2 : $body}
    dict set rc response [$hash $A1:$interlude:$A2]
    set authlist {}
    dict for {key val} $rc {
	if {$key ni {qop nc}} {
	    lappend authlist [format {%s="%s"} $key $val]
	} else {
	    lappend authlist $key=$val
	}
    }
    return "Digest [join $authlist ,]"
}
