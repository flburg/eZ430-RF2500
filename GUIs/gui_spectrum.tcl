##
## These may need to be set
##
set baudrate   57600
set parity     n
set databits   8
set stopbits   1
##

##
## Global state variables:
##     state:     Global state of app e.g. start, stop, exit.
##     timestamp: Cumulative count of number of access point packets received.
##     logmod:	  Modulus of timestamp for writing to log. 
##                (fmod($timestamp,$logmod)
##

set state stop
set timestamp 0

set logmod 1

##
## CONSTANTS
##

# File to which log entries are written.
set logfile "log_gui_spectrum.txt"

#####################
## MAIN PROCEDURES ##
#####################

##
## Build the control widget window.
##
proc create_controls {} {
    global state 

    wm title . "Control Panel"

    catch {destroy .controls}

    frame .controls
    pack .controls

    set w .controls.buttons

    frame $w
    pack $w -side top -pady 3m

    button $w.stop -text "Stop" -command {set state "stop"} -relief raised
    pack $w.stop -side left -padx 2m

    button $w.go -text "Go" -command {set state "go"} -relief raised
    pack $w.go -side left -padx 24

    button $w.exit -text "Exit" -relief raised -command exitgui
    pack $w.exit -side left -padx 2m
}

set lastseqno 0
array set data {}
set data(0) ""
set data(1) ""
set data(2) ""

##
## Read from the serial port.
##
proc read_port {comfd logfd} {
    global state
    global data
    global timestamp
    global logmod
    global data
    global lastseqno

    if {[string match $state "stop"]} {
        return
    }

    # Get a record from the com port.
    # The first token should be the start-of-record symbol.
    set retval [read $comfd 54]
    binary scan $retval c sor

    while {$sor != -1} {
        puts "WARNING: Unsynchronized read: sor = $sor"
	return
    }

    set args [binary scan $retval ccccccccc46 sor node id rssi type missedacks axis seqno d]

    if {$args != 9} {
        puts "WARNING: Incorrect number of arguments: $args"
        return
    }

    flush $comfd

    # Test for a sample from the access point.
    if {$id == 0} {
        # AP sets the time base for live data.
        set timestamp [expr $timestamp + 1]
	return
    } 

puts $node
puts $id
puts $rssi
puts $type
puts $axis
puts $seqno

    if {$seqno == 1} {
        set data($axis) $d
	if {$lastseqno != 7} {
            puts "MISSING SEQUENCE(s) ON AXIS 2 AT TIMESTAMP $timestamp"
        }	    
    } else {
        set data($axis) [concat $data($axis) $d]
	if {$seqno != [expr $lastseqno + 1]} {
            puts "MISSING SEQUENCE(s) ON AXIS $axis AT TIMESTAMP $timestamp"
        }	    
    }

    set lastseqno $seqno

puts $data($axis)
puts ""
puts ""
    if {$seqno == 7} {
        puts $logfd "$timestamp $axis $data($axis)"
        flush $logfd
    }
}

###############
## UTILITIES ##
###############

##
## Locate the correct serial port.
##

package require registry
 
proc get_serial_port {} {
    set serial_base "HKEY_LOCAL_MACHINE\\HARDWARE\\DEVICEMAP\\SERIALCOMM"
    set values [registry values $serial_base]

    set target [lsearch -glob $values "*USBSER*"]

    set result ""
    if {$target > -1} {
       set result [registry get $serial_base [lindex $values $target]]
    }
 
    return $result
}

##
## Open the log file.
##
proc open_log {logfile} {
    return [open $logfile w+]
}

##
## Open the serial port.
##
proc open_com {} {
    global baudrate
    global parity
    global databits
    global stopbits

    set port [get_serial_port]
    if {[string length $port] > 4} {
        set comfd [open "\\\\.\\$port" r+]
    } else {
        set comfd [open $port r+]
    }

    fconfigure $comfd -mode $baudrate,$parity,$databits,$stopbits \
      -blocking 1 -encoding binary -translation binary -buffering none \
      -buffersize 1024

    fconfigure $comfd -translation binary

    return $comfd
}

##
## Called when the Exit button is pressed.
##
proc exitgui {} {
    global logfd comfd

    catch {close $logfd}
    catch {close $comfd}

    exit
}

##########################
## Initialize and start ##
##########################

create_controls

set logfd [open_log $logfile]
if {[catch {set comfd [open_com]} errmsg]} {
    error $errmsg
}

# Call read_port when there's something on the port to read.
fileevent $comfd readable [list read_port $comfd $logfd]

