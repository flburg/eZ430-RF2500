##
## These may need to be set
##
set baudrate   57600
set parity     n
set databits   8
set stopbits   1
##

##################################################
## VERSION WITH NO GRAPHICS SUPPORT (text only) ##
##################################################

##
## Global state variables:
##     timestamp: Cumulative count of number of access point packets received.
##     connected: Array of timestamps indexed by node id, for use in timeouts.
##     alarms:    Array of active over/under limit conditions
##     logmod:	  Modulus of timestamp for writing to log. 
##                (fmod($timestamp,$logmod)
##

set timestamp 0
set timeout_secs 300

set logmod 1

##
## CONSTANTS
##

# File to which log entries are written.
set logfile "log_gui.txt"

package require Plotchart

#####################
## MAIN PROCEDURES ##
#####################

##
## Read from the serial port.
##
proc read_port {comfd logfd} {
    global data
    global timestamp
    global connected
    global logmod
    global xmin xmax xspan
    global recordstringlength

    # Get a record from the com port.
    # The first token should be the start-of-record symbol.
    set retval [read $comfd 14]
    binary scan $retval c sor

    while {$sor != -1} {
        puts "WARNING: Unsynchronized read: sor = $sor"
	return
    }

    set args [binary scan $retval ccccssssuc sor node id rssi temp volt pres seqno missedacks]
    if {$args != 9} {
        puts "WARNING: Incorrect number of arguments: $args"
        return
    }

## Fix this error checking code
#    if {$id > 0} {
#        if {![string is double -strict $temp]} {
#            puts "bad temp: $node $temp $voltage $rssi $pressure"
#           return
#        }
#        if {![string is integer -strict $rssi]} {
#            puts "bad RSSI: $node $temp $voltage $rssi $pressure"
#            return
#        }
#        if {![string is integer $pressure]} {
#            puts "bad pressure: $node $temp $voltage $rssi :$pressure:"
#            return
#        }
#    }

    # Test for a sample from the access point.
    if {$id == 0} {
        # AP sets the time base for live data.
        set timestamp [expr $timestamp + 1]
        # Check all nodes for timeouts.
        check_timeout $timestamp
	return
    } 

    if {$seqno == 0} {
        puts "Impact alarm from node $id"
	return
    }

    set volt [expr double(((double($volt) / 1024) * 2.5) * 2)]

    set data(id) $id
    set data(temperature) [format "%.2f" [expr (($temp * 1.8)+320)/10]]
    set data(voltage) [format "%.3f" $volt]
    set data(rssi) $rssi
    set data(pressure) $pres
    set data(seqno) $seqno
    set data(missedacks) $missedacks

    puts "$timestamp $node $data(id) $data(temperature) \
      $data(voltage) $data(rssi) $data(pressure) $data(seqno) $data(missedacks)"

    if {![expr fmod($timestamp,$logmod)]} {
        puts $logfd "$timestamp $node $data(id) $data(temperature) \
          $data(voltage) $data(rssi) $data(pressure) $data(seqno) $data(missedacks)"
        flush $logfd
    }

    # Update the nodes timestamp.
    set connected($id) $timestamp
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
## Check for series timeout.  When a sample is received from a node,
## the connected array entry for that node is updated with the
## current timestamp.  If the timestamp is old by $timeout_secs, the
## node ID is removed from the connected array. This causes the series 
## for the node to be removed from all graphs at the next graph redraw  
## and the alarms to be silenced when the next datapoint is plotted for 
## any node. 
##
proc check_timeout {timestamp} {
    global connected
    global timeout_secs

    foreach id [array names connected] {
        if {[expr $timestamp - $connected($id)] > $timeout_secs} {
            array unset connected $id
        }
    }
}

##########################
## Initialize and start ##
##########################

set logfd [open_log $logfile]
if {[catch {set comfd [open_com]} errmsg]} {
    error $errmsg
}

# Call read_port when there's something on the port to read.
fileevent $comfd readable [list read_port $comfd $logfd]

