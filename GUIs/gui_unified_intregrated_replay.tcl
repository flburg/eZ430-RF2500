##
## These may need to be set
##
set platform "fredsmac_windows"
set baudrate   57600
set parity     n
set databits   8
set stopbits   1
##

# Indices for the defaults array
set minindx 0
set maxindx 1
set tickindx 2
set alarmindx 3
set titleindx 4
set axisindx 5

# Defaults for each graphs
set defaults(temperature) [list 50 90 10 100 "Temperature" "Degrees F"]
set defaults(voltage)     [list 2.0 4.0 0.5 4.0 "Voltage" "V"]
set defaults(pressure)    [list 0 500 50 500 "Pressure" "PSI"]
set defaults(rssi)        [list 0 50 5 50 "RSSI" "nounits"]

# Color map for nodes, indexed by node ID (note index 0 is a placeholder)
set seriescolors [list "0" \
  "#ff0000" "#00ff00" "#0000ff" "#ffff00" \
  "#ff00ff" "#00ffff" "#f00000" "#00f000" \
  "#0000f0"]

# Background color for all graphs
set backgroundcolor "#606060"
#set backgroundcolor "#df8080"

# Fixed X-axis parameters
set xspan 100.0
set xmin 0.0
set xmax $xspan
set xtick [expr $xspan / 10]

# Time before an apparently inactive node is removed from the graphs
set timeoutsecs 5

# File to which log entries are written when receiving real data, and
# from which values are read when replaying.
set logfile "log_gui_temperature.txt"

set screensize [wm maxsize .]

# This is a hack - should be more flexible and dynamic
if {[string match $platform "fredsmac_windows"]} {
    set comport 6
    set width [expr [lindex $screensize 0] - 400]
    set height [expr [lindex $screensize 1] - 200]
} elseif {[string match $platform "pc"]} {
    set comport 8
    set width [expr [lindex $screensize 0] - 400]
    set height [expr [lindex $screensize 1] - 200]
} else {
    set width [lindex $screensize 0]
    set height [expr [lindex $screensize 1] - 100]
}

##
## Global variables:
##     state:     Global state of app e.g. start, stop, exit.
##     defaults:  Array of default values for graphs and series.
##                Indexed by graph parameter e.g. rssi
##     vars:      Array of variables for each graph that describe state
##                e.g. axis min, max, plot widget handle.
##                Indexed by param name e.g. rssi followed by tag e.g. plot
##     connectednodes:  Array of timestamps indexed by node id.
##

package require Plotchart

##
## Build the control widget window
##
proc create_controls {} {
    global state 
    global replay
    global defaults
    global vars

    set entrywidth 6

    catch {destroy .controls}

    frame .controls
    pack .controls

    set w .controls.datafields
    
    frame $w -bg blue
    pack $w -side top
    
    frame $w.headers -bg blue
    pack $w.headers -side top -fill x -padx 2m -pady 2m
    
    label $w.headers.track -bg blue -fg white \
      -text "Track" -justify left -width 12
    pack $w.headers.track -side left
    
    label $w.headers.ymin -bg blue -fg white \
      -text "YMin" -justify center -width [expr $entrywidth - 1]
    pack $w.headers.ymin -side left

    label $w.headers.ymax -bg blue -fg white \
      -text "YMax" -justify center -width [expr $entrywidth + 3]
    pack $w.headers.ymax -side left
    
    label $w.headers.ytick -bg blue -fg white \
      -text "YTick" -justify center -width [expr $entrywidth + 0]
    pack $w.headers.ytick -side left
    
    label $w.headers.alarm -bg blue -fg white \
      -text "Alarm" -justify center -width [expr $entrywidth + 0]
    pack $w.headers.alarm -side left
    
    foreach param [array names defaults] {
        frame $w.$param 
        pack $w.$param -side top -fill x

        checkbutton $w.$param.b -variable vars(${param}state) \
	  -text $param -width 12 -anchor w -command create_graph
        pack $w.$param.b -side left

	set vars(${param}min) [lindex $defaults($param) 0]
        entry $w.$param.mn -textvariable vars(${param}min) -width $entrywidth
        pack $w.$param.mn -side left
        bind $w.$param.mn <KeyPress-Return> create_graph 

	set vars(${param}max) [lindex $defaults($param) 1]
        entry $w.$param.mx -textvariable vars(${param}max) -width $entrywidth
        pack $w.$param.mx -side left
        bind $w.$param.mx <KeyPress-Return> create_graph

	set vars(${param}tick) [lindex $defaults($param) 2] 
        entry $w.$param.tc -textvariable vars(${param}tick) -width $entrywidth
        pack $w.$param.tc -side left
        bind $w.$param.tc <KeyPress-Return> create_graph

	set vars(${param}alarm) [lindex $defaults($param) 3] 
        entry $w.$param.al -textvariable vars(${param}alarm) -width $entrywidth
        pack $w.$param.al -side left
        bind $w.$param.al <KeyPress-Return> create_graph
    }
    
    set w .controls.replay

    frame $w
    pack $w -side top -pady 5m

    checkbutton $w.b -variable replay \
      -text replay -anchor w
    pack $w.b -side left

    set w .controls.buttons

    frame $w
    pack $w -side top -pady 3m

    button $w.stop -text "Stop" -command {set state "stop"} -relief raised
    pack $w.stop -side left -padx 2m

    button $w.go -text "Go" -command {set state "go"} -relief raised
    pack $w.go -side left -padx 2m

    button $w.exit -text "Exit" -relief raised -command exitgui
    pack $w.exit -side left -padx 2m
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

##
## Create one or more graphs, determined by control widget checkboxes.
##
proc create_graph {} {
    global defaults
    global vars
    global connectednodes
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
    lower .graphs

    # Build the graphs for each selected paramter (control widget checkboxes)
    foreach param [array names defaults] {
        if {$vars(${param}state) == 0} {
            continue
        }

        canvas .graphs.$param \
	  -background white -width $width -height [expr $height / $numgraphs]
        pack .graphs.$param -fill x

        set vars(${param}plot) [::Plotchart::createXYPlot .graphs.$param \
            [list $xmin $xmax $xtick] \
	    [list $vars(${param}min) $vars(${param}max)  $vars(${param}tick)]]

# Example of how to create a right axis
#        if {$someflag} {
#            set r [::Plotchart::createRightAxis .graphs.c \
#              [list $rymin $rymax $rytick]]
#            $r ytext "Voltage"
#            $r dataconfig voltage -colour $voltagelinecolor -width 3
#            $s legend voltage "sensor voltage"
#        }

        $vars(${param}plot) title [lindex $defaults($param) 4]
        $vars(${param}plot) xtext "seconds"
        $vars(${param}plot) ytext [lindex $defaults($param) 5]
        $vars(${param}plot) background "plot" $backgroundcolor "right"
#        $vars(${param}plot) background "gradient" $backgroundcolor "right"

	foreach id [array names connectednodes] {
            create_series $param $id
	}

        # transparent legend background
#        $vars(${param}plot) legendconfig -background ""
    }
}

##
## Create a series for a new graph.  Called from create_graph.
##
proc create_series {param id} {
    global vars
    global seriescolors

    puts "CREATED SERIES: $vars(${param}plot) $id [lindex $seriescolors $id]"

    $vars(${param}plot) dataconfig $id \
      -colour [lindex $seriescolors $id] -width 3
    $vars(${param}plot) legend $id $id
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

        puts "ADDED SERIES: $id [lindex $seriescolors $id]"

        $vars(${param}plot) dataconfig $id \
          -colour [lindex $seriescolors $id] -width 3
        $vars(${param}plot) legend $id $id
    }
}

##
## Check for series timeout.  When a sample is received from a node,
## the connectednodes array entry for that node is updated with the
## current timestamp.  If the timestamp is old by $timeoutsecs, the
## series for the node is removed from all graphs. Not used by replay.
##
proc check_timeout {timestamp} {
    global connectednodes
    global timeoutsecs

    foreach id [array names connectednodes] {
        if {[expr $timestamp - $connectednodes($id)] > $timeoutsecs} {
            array unset connectednodes $id
        }
    }
}

##
## Plot a datapoint for a node on all active graphs.
##
proc plot_point {node id} {
    global defaults
    global vars
    global data
    global alarms
    global replay
    global timestamp
    global xmin xmax xspan
    global connectednodes
    global logfd

    puts "$timestamp $node $data(id) $data(temperature) \
      $data(voltage) $data(rssi) $data(pressure)"

    # Test for a sample from the access point.
    if {[string match "\$HUB0*" $node]} {
# Not plotting hub temperature now
#        $leftside plot receiver $timestamp $temp

        # Hub sets the time base for live data.
        set timestamp [expr $timestamp + 1]

	return
    } 

    # Test for X axis out-of-bounds.  
    # If found, reset axis parameters and rebuild graphs.
    if {[expr $timestamp == $xmax]} {
        set xmin $timestamp
        set xmax [expr $xmin + $xspan] 
        create_graph
    }

    # If this node has not been plotted yet, add it to the active graphs.
    if {[llength [array names connectednodes -exact $id]] == 0} {
        add_series $id
    }

    # Update the nodes timestamp, and check all nodes for timeouts.
    set connectednodes($id) $timestamp
    check_timeout $timestamp

    # Plot this sample on each graph.
    foreach param [array names defaults] {
        if {$data($param) > $vars(${param}alarm)} {
            set alarms(${param}${id}) \
              [list $id $param $data($param) $vars(${param}alarm)]

        } else {
            catch {array unset alarms ${param}${id}}
        }

        if {$vars(${param}state) == 0} {
            continue
        }
        $vars(${param}plot) plot $id $timestamp $data($param)
    }

    # If we're replaying from a log, we don't want to write to the log.
    if {$replay == 0} {
        puts $logfd "$timestamp $node $data(id) $data(temperature) \
          $data(voltage) $data(rssi) $data(pressure)"
        flush $logfd
    }

    check_alarms

    return $timestamp
}

##
## Show alarm for over limit.
##
proc check_alarms {} {
    global alarms

    set w .controls

    catch {destroy $w.alarms}

    frame $w.alarms
    pack $w.alarms -side top -fill x

    set w $w.alarms

    foreach alarm [array names alarms] {
        set id    [lindex $alarms($alarm) 0]
        set param [lindex $alarms($alarm) 1]
        set value [lindex $alarms($alarm) 2]
        set limit [lindex $alarms($alarm) 3]

        label $w.$alarm -bg red -fg white \
          -text "$param over limit for node $id: is $value, max $limit" \
          -justify center 
        pack $w.$alarm -side top -fill x
    }
}

##
## Read from a serial port.  This is for live data.
##
proc read_port {} {
    global state
    global replay
    global data
    global recordstringlength
    global comfd

    if {[string match $state "stop"] || $replay == 1} {
        return
    }

    # Read from the serial port.
    set retval [gets $comfd line]
    if {$retval > 0 && $retval != $recordstringlength} {
        puts "bad string length = $retval, expecting $recordstringlength"
        return
    }

    if {![regexp "^\\$" $line]} {
#        puts "bad string format: $line"
        return
    }

    # Access point line format is:
    #   
    set buf [split $line ',']
    set node [lindex $buf 0]
    set temp [string trim [lindex $buf 1] " F"]
    set voltage [lindex $buf 2]
    set rssi [string range [lindex $buf 3] 1 2]
    set id [lindex $buf 5]
    set pressure [lindex $buf 6]

## HACK: fix the string leading zero problem
    if {[string match [string index $pressure 0] "0"]} {
       set pressure [string range $pressure 1 3]
    } else {
       set pressure [string range $pressure 0 3]
    }

    if {![string is double -strict $temp]} {
        puts "bad temp: $node $temp $voltage $rssi $pressure"
        return
    }
    if {![string is integer -strict $rssi]} {
        puts "bad RSSI: $node $temp $voltage $rssi $pressure"
        return
    }
    if {![string is integer -strict $pressure]} {
        puts "bad pressure: $node $temp $voltage $rssi $pressure"
        return
    }

    set data(id) $id
    set data(temperature) $temp
    set data(voltage) $voltage
    set data(rssi) $rssi
    set data(pressure) $pressure

    plot_point $node $id
}

##
## Whe in replay mode, read data from the log file.  The log line format is 
## somewhat different from the access point line format.
##
proc read_log {} {
    global state
    global replay
    global data
    global logfd
    global timestamp

    if {[string match $state "stop"] || $replay == 0} {
        return
    }

    # Get a line from the log file.
    set retval [gets $logfd line]

#    if {![regexp "^\\$" $line]} {
#        puts "bad string format: $line"
#        return
 #   }

    set timestamp [lindex $line 0]
    set node [lindex $line 1]
    set id [lindex $line 2]
    set temp [lindex $line 3]
    set voltage [lindex $line 4]
    set rssi [lindex $line 5]
    set pressure [lindex $line 6]

## HACK: fix the string leading zero problem
    if {[string match [string index $pressure 0] "0"]} {
       set pressure [string range $pressure 1 3]
    } else {
       set pressure [string range $pressure 0 3]
    }

    if {![string is double -strict $temp]} {
        puts "bad temp: $node $temp $voltage $rssi $pressure"
        after 1000 read_log
        return
    }
    if {![string is integer -strict $rssi]} {
        puts "bad RSSI: $node $temp $voltage $rssi $pressure"
        after 1000 read_log
        return
    }
    if {![string is integer -strict $pressure]} {
        puts "bad pressure: $node $temp $voltage $rssi $pressure"
        after 1000 read_log
        return
    }

    set data(id) $id
    set data(temperature) $temp
    set data(voltage) $voltage
    set data(rssi) $rssi
    set data(pressure) $pressure

    plot_point $node $id
}

##
## For live data, open the serial port.
##
proc open_com {} {
    global comport
    global comfd logfd
    global logfile
    global baudrate
    global parity
    global databits
    global stopbits

    set comfd [open com$comport: r+]
#    set comfd [open com$comport: r+]
#puts tp5
#    if {[catch {set comfd [open com$comport w+]}]} {
#puts commerr
#        return 1
#    }

    if {[catch {fconfigure $comfd -mode $baudrate,$parity,$databits,$stopbits \
      -blocking 0 -translation auto -buffering none -buffersize 12}]} {
        catch {close $comfd}
        return 1
    }

    # When the port is readable, call read_port.
    fileevent $comfd readable run

    return 0
}

##
## Initialize and start.
##

set timestamp 0
set state stop
set replay 0
set lastreplay 1
set comopen 0

create_controls
open_com

proc run {} {
    global state
    global replay lastreplay
    global logopen
    global logfd comfd
    global logfile
    global comopen

    if {[string match $state "go"]} {
        if {$replay == 1} {
            if {$lastreplay == 0} {
                catch {close $comfd}
		set comopen 0
                catch {close $logfd}
                set logfd [open $logfile r]
                set lastreplay 1
            }
            read_log
            after 1000 run
        } else {
            if {$lastreplay == 1} {
                catch {close $logfd}
                set logfd [open $logfile w+]
                set lastreplay 0
            }

	    if {$comopen == 0} {
                if {![open_com]} {
                    set comopen 1
                }
            }
            after 1000 run
        }
    }
    after 1000 run
}

#after 1000 plot_point
#
#while {$run} {
#    if {[string match $a "go"]} {
#        after 1000 plot_point
#        vwait doneflag
#    } else {
#        after 1000
#    }
#}

