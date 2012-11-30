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
##     vars:      Array of variables for each graph that describe state
##                e.g. axis min, max, plot widget handle.
##                Indexed by param name e.g. rssi followed by tag e.g. plot
##     connected: Array of timestamps indexed by node id, for use in timeouts.
##     alarms:    Array of active over/under limit conditions
##     xspan, xmin, xmax, xtick:
##                X axis paramters. xmin and xmax are updated dynamically,
##                xspan and xtick are constants at present.
##     logmod:	  Modulus of timestamp for writing to log. 
##                (fmod($timestamp,$logmod)
##

set state stop
set timestamp 0
set timeout_secs 5

set xspan 100.0
set xmin 0.0
set xmax $xspan
set xtick [expr $xspan / 10]

set logmod 1

##
## CONSTANTS
##

# Width and height of graph window. Should be user-resizable (todo).
set screensize [wm maxsize .]
set width [expr [lindex $screensize 0] - 400]
set height [expr [lindex $screensize 1] - 200]

# Expected length of string read from serial port.
set recordstringlength 32

# map for the defaults array
set defaultsmap [list "ymin" "ymax" "ytick" "ylolim" "yhilim" "title" "ylabel"]
# Defaults for each graph
set defaults(temperature) [list 50 90 10 32 100 "Temperature" "Degrees F"]
set defaults(voltage)     [list 2.0 4.0 0.5 2.5 4.0 "Voltage" "V"]
set defaults(pressure)    [list 0 500 50 50 500 "Pressure" "PSI"]
set defaults(rssi)        [list 0 50 5 10 50 "RSSI" "nounits"]

# Color map for nodes, indexed by node ID (note index 0 is a placeholder)
# Format is #rrggbb in 8 bit hex
set seriescolors [list "0" \
  "#ff0000" "#00ff00" "#0000ff" \
  "#ffff00" "#ff00ff" "#00ffff" \
  "#c0c000" "#00c0c0" "#c000c0" \
  "#c00000" "#00c000" "#0000c0" \
  "#800000" "#008000" "#000080" \
  "#808000" "#008080" "#800080" \
  "#400000" "#004000" "#000040" \
  "#404000" "#004040" "#400040" \
]

# Background color for all graphs.
set backgroundcolor "#aaaaaa"
#set backgroundcolor "#df8080"

# File to which log entries are written.
set logfile "log_gui.txt"

package require Plotchart

#####################
## MAIN PROCEDURES ##
#####################

##
## Build the control widget window.
##
proc create_controls {} {
    global state 
    global defaults
    global vars

    set entrywidth 10

    wm title . "Graph Control Panel"

    catch {destroy .controls}

    frame .controls
    pack .controls

    set w .controls.fields
    
    frame $w -bg blue
    pack $w -side top
    
    frame $w.headers -bg blue
    pack $w.headers -side top -fill x -padx 2m -pady 2m
    
    create_hdrfield $w.headers "Param" [expr $entrywidth + 4]
    create_hdrfield $w.headers "YMin" $entrywidth
    create_hdrfield $w.headers "YMax" $entrywidth
    create_hdrfield $w.headers "YTick" $entrywidth
    create_hdrfield $w.headers "YLoLimit" $entrywidth
    create_hdrfield $w.headers "YHiLimit" $entrywidth

    foreach param [array names defaults] {
        frame $w.$param 
        pack $w.$param -side top -fill x

        checkbutton $w.$param.cb -variable vars(${param}state) \
	  -text $param -width $entrywidth -anchor w -command create_graph
        pack $w.$param.cb -side left

        create_entry $w $param ymin $entrywidth
        create_entry $w $param ymax $entrywidth
        create_entry $w $param ytick $entrywidth
        create_entry $w $param ylolim $entrywidth
        create_entry $w $param yhilim $entrywidth
    }
    
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

##
## Create one or more graphs, determined by control widget checkboxes.
##
proc create_graph {} {
    global defaults
    global vars
    global connected
    global backgroundcolor
    global width height
    global xmin xmax xtick

    catch {destroy .graphs}

    # Compute the number of graphs so we know how to set the graph height.
    set numgraphs 0
    foreach param [array names defaults] {
        if {$vars(${param}state) == 1} {
            set numgraphs [expr $numgraphs + 1]
        }
    }

    if {$numgraphs == 0} {
        return
    }

    tk::toplevel .graphs
    wm title .graphs "Real Time Sensor Graph"
#    lower .graphs

    # Build the graphs for each selected parameter (control widget checkboxes)
    foreach param [array names defaults] {
        if {$vars(${param}state) == 0} {
            continue
        }

        canvas .graphs.$param \
	  -background white -width $width -height [expr $height / $numgraphs]
        pack .graphs.$param -fill x

        set vars(${param}plot) [::Plotchart::createXYPlot .graphs.$param \
            [list $xmin $xmax $xtick] \
	    [list $vars(${param}ymin) $vars(${param}ymax) $vars(${param}ytick)]]

        $vars(${param}plot) title [lindex $defaults($param) 5]
        $vars(${param}plot) xtext "seconds"
        $vars(${param}plot) ytext [lindex $defaults($param) 6]
        $vars(${param}plot) background "plot" $backgroundcolor "right"
#        $vars(${param}plot) background "gradient" $backgroundcolor "right"

	foreach id [array names connected] {
            create_series $param $id
	}

        # transparent legend background
#        $vars(${param}plot) legendconfig -background ""
    }
}

##
## Read from the serial port.
##
proc read_port {comfd logfd} {
    global state
    global data
    global recordstringlength

    if {[string match $state "stop"]} {
        return
    }

    # Get a record from the com port.
    # The first token should be the start-of-record symbol.
    set retval [read $comfd 14]
    binary scan $retval c sor

    # This is a little dangerous because comfd is blocking!!
    while {$sor != -1} {
        puts "WARNING: Unsynchronized read: sor = $sor"
        set retval [read $comfd 1]
        binary scan $retval c sor
    }

    set args [binary scan $retval ccccsss sor node id rssi temp volt pres]
    if {$args != 7} {
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

    set volt [expr double(((double($volt) / 1024) * 2.5) * 2)]

    set data(id) $id
    set data(temperature) [format "%.2f" [expr (($temp * 1.8)+320)/10]]
    set data(voltage) [format "%.3f" $volt]
    set data(rssi) $rssi
    set data(pressure) $pres

    plot_point $node $id
}

##
## Plot a datapoint for a node on all active graphs.
##
proc plot_point {node id} {
    global defaults
    global vars
    global data
    global timestamp
    global xmin xmax xspan
    global connected
    global logfd logmod

    puts "$timestamp $node $data(id) $data(temperature) \
      $data(voltage) $data(rssi) $data(pressure)"

    # Test for a sample from the access point.
    if {$data(id) == 0} {
        # AP sets the time base for live data.
        set timestamp [expr $timestamp + 1]
        # Post active alarms and update the alarms array.
        post_alarms
        # Check all nodes for timeouts.
        check_timeout $timestamp

        # Test for X axis out-of-bounds.  
        # If found, reset axis parameters and rebuild graphs.
        if {[expr $timestamp == $xmax]} {
            set xmin $timestamp
            set xmax [expr $xmin + $xspan] 
            create_graph
        }

	return
    } 

    # If this node has not been plotted yet, add it to the active graphs.
    if {![llength [array names connected -exact $id]]} {
        add_series $id
    }

    # Update the nodes timestamp.
    set connected($id) $timestamp

    # Plot this sample on each graph.
    foreach param [array names defaults] {
        update_alarms $id $param

        if {$vars(${param}state) == 0} {
            continue
        }
        $vars(${param}plot) plot $id $timestamp $data($param)
    }

    if {![expr fmod($timestamp,$logmod)]} {
        puts $logfd "$timestamp $node $data(id) $data(temperature) \
          $data(voltage) $data(rssi) $data(pressure)"
        flush $logfd
    }

    return $timestamp
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

    set comfd [open [get_serial_port]: r+]
    fconfigure $comfd -mode $baudrate,$parity,$databits,$stopbits \
      -blocking 1 -encoding binary -translation binary -buffering none \
      -buffersize 1024

    fconfigure $comfd -translation binary

    return $comfd
}

##
## Create a header entry widget for y-axis parameters e.g. ymin, ymax.
## Used instead of a label to force column alignment with all fonts.
## Called when graphs are rebuilt. Note that the entry is read-only.
##
proc create_hdrfield {w headertext width} {
    # widget names can't start with a capital
    set name [string tolower $headertext]
 
    # entry variables must be global
    global ${name}text
    set ${name}text $headertext

    entry $w.$name -state readonly -readonlybackground blue \
      -fg white -textvariable ${name}text \
      -justify center -relief flat -width $width
    pack $w.$name -side left
}

##
## Create an entry widget for numerical y-axis parameters e.g. ymin, ymax.
## Called when graphs are rebuilt.
##
proc create_entry {w p name width} {
    global vars
    global defaults defaultsmap

    set vars(${p}$name) [lindex $defaults($p) [lsearch $defaultsmap $name]]
    entry $w.$p.$name -textvariable vars(${p}${name}) -width $width
    pack $w.$p.$name -side left
    bind $w.$p.$name <KeyPress-Return> create_graph 
}

##
## Create a series for a new graph.  Called from create_graph.
##
proc create_series {param id} {
    global vars
    global seriescolors

    puts "CREATED SERIES: $vars(${param}plot) $id \
      $param [lindex $seriescolors $id]"

    $vars(${param}plot) dataconfig $id \
      -colour [lindex $seriescolors $id] -width 3
    $vars(${param}plot) legend $id "Node $id"
}

##
## Add a series for an existing graph.  Called from plot_point.
##
proc add_series {id} {
    global defaults
    global vars
    global seriescolors

    foreach param [array names defaults] {
        if {$vars(${param}state) == 0} {
            continue
        }

        puts "ADDED SERIES: $id $param [lindex $seriescolors $id]"

        $vars(${param}plot) dataconfig $id \
          -colour [lindex $seriescolors $id] -width 3
        $vars(${param}plot) legend $id "Node $id"
    }
}

##
## If a parameter is over or under a limit, add it to the alarms array
## or overwrite an existing entry. Otherwise, remove it from the array.
##
proc update_alarms {id param} {
    global data
    global vars
    global alarms

    if {$data($param) > $vars(${param}yhilim)} {
        set alarms(${param}${id}) \
          [list $id $param $data($param) $vars(${param}yhilim) "over"]
    } elseif {$data($param) < $vars(${param}ylolim)} {
        set alarms(${param}${id}) \
          [list $id $param $data($param) $vars(${param}ylolim) "under"]
    } else {
        catch {array unset alarms ${param}${id}}
    }
}

##
## Show or remove out of limit alarm message.
##
proc post_alarms {} {
    global alarms
    global connected

    set w .controls

    catch {destroy $w.alarms}

    frame $w.alarms
    pack $w.alarms -side top -fill x

    set w $w.alarms

    foreach alarm [array names alarms] {
        set id        [lindex $alarms($alarm) 0]
	# If the id is no longer in the connected list, remove the alarm
	if {[lsearch [array names connected] $id] == -1} {
            array unset alarms $alarm
            continue
        }
        set param     [lindex $alarms($alarm) 1]
        set value     [lindex $alarms($alarm) 2]
        set limit     [lindex $alarms($alarm) 3]
        set overunder [lindex $alarms($alarm) 4]

        label $w.$alarm -bg red -fg white \
          -text "$param $overunder limit for node $id: is $value, limit is $limit" \
          -justify center 
        pack $w.$alarm -side top -fill x
    }
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

