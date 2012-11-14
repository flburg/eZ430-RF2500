##
## These may need to be set
##
set platform "fredsmbp_win7"
#set platform "fredsmac_windows"

# This is a hack - should be more flexible and dynamic
set screensize [wm maxsize .]
if {[string match $platform "fredsmbp_win7"]} {
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
##

set state stop
set timestamp 0
set timeout_secs 5
set playrate_msecs 1000

set xspan 100.0
set xmin 0.0
set xmax $xspan
set xtick [expr $xspan / 10]

##
## CONSTANTS
##

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

# File from which values are read.
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
    global logfile
    global playrate_msecs

    set entrywidth 10

    wm title . "Replay Control Panel"

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
    
    # Create the log file name entry.

    set w .controls.fileentry

    frame $w
    pack $w -side top -pady 1m

    label $w.flabel -text "Log file:   "
    pack $w.flabel -side left

    entry $w.fname -textvariable logfile -width 50
    pack $w.fname -side left
    bind $w.fname <KeyPress-Return> {set state "restart"}

    # Create the sample rate entry.

    set w .controls.playrate

    frame $w
    pack $w -side top -pady 1m

    label $w.labl1 -text "Rate:   "
    pack $w.labl1 -side left

    entry $w.rate -textvariable playrate_msecs -width 5
    pack $w.rate -side left

    label $w.labl2 -text " ms/sample"
    pack $w.labl2 -side left

    # Create the run control buttons.

    set w .controls.buttons

    frame $w
    pack $w -side top -pady 1m

    button $w.stop -text "Stop" -command {set state "stop"} -relief raised
    pack $w.stop -side left -padx 1m

    button $w.go -text "Go" -command {set state "go"} -relief raised
    pack $w.go -side left -padx 1m

    button $w.rego -text "Restart" -command {set state "restart"} -relief raised
    pack $w.rego -side left -padx 1m

    button $w.exit -text "Exit" -relief raised -command exitgui
    pack $w.exit -side left -padx 1m
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
    wm title .graphs "Sensor Replay Graph"
#    lower .graphs

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
## Read from the log file. The log line format is 
## somewhat different from the access point line format.
##
set lasttime 0
proc read_log {} {
    global state
    global data
    global lasttime
    global logfd
    global playrate_msecs

    if {[string match $state "restart"]} {
        reopen_log
    }

    if {[string match $state "stop"]} {
        after $playrate_msecs read_log
        return
    }

    # Get all lines with the same timestamp from the log file.
    while {1 == 1} {
        gets $logfd line
        if {[eof $logfd]} {
            reopen_log
        }

        set timestamp [lindex $line 0]
        set node      [lindex $line 1]
        set id        [lindex $line 2]
        set temp      [lindex $line 3]
        set voltage   [lindex $line 4]
        set rssi      [lindex $line 5]
        set pressure  [lindex $line 6]

        set data(timestamp) $timestamp
        set data(id) $id
        set data(temperature) $temp
        set data(voltage) $voltage
        set data(rssi) $rssi
        set data(pressure) $pressure

        plot_point $id

        if {$timestamp != $lasttime} {
            set lasttime $timestamp
            break
        }
    }

    after $playrate_msecs read_log
}

##
## Plot a datapoint for a node on all active graphs.
##
proc plot_point {id} {
    global defaults
    global vars
    global data
    global timeout_secs
    global xmin xmax xspan
    global connected

    # Protect against trash at end of file.
    if {![string is integer $id] || $id <= 0} {
        return
    }

    puts "$data(timestamp) $data(id) $data(temperature) \
      $data(voltage) $data(rssi) $data(pressure)"

    set timestamp $data(timestamp)

    # Test for X axis out-of-bounds.  
    # If found, reset axis parameters and rebuild graphs.
    if {$timestamp == $xmax} {
        set xmin $timestamp
        set xmax [expr $xmin + $xspan] 
        create_graph
    }

    # If this node has not been plotted yet, add it to the active graphs.
    if {![llength [array names connected -exact $id]]} {
        add_series $id
    }

    # Update the nodes timestamp, and check all nodes for timeouts.
    set connected($id) $timestamp
    check_timeout $timestamp

    # Plot this sample on each graph.
    foreach param [array names defaults] {
        update_alarms $id $param

        if {$vars(${param}state) == 0} {
            continue
        }
        $vars(${param}plot) plot $id $timestamp $data($param)
    }

    post_alarms
}

###############
## UTILITIES ##
###############

##
## Open the log file.
##
proc open_log {logfile} {
    return [open $logfile r]
}

##
## Close and reopen the log file on restart
##
proc reopen_log {} {
    global state
    global logfd logfile
    global timestamp
    global xmin xmax xspan

    set xmin 0
    set xmax [expr $xmin + $xspan] 

    close $logfd
    set logfd [open_log $logfile]
    create_graph
    set state "go"
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
read_log

