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
##

set state stop
set timestamp 0
set timeout_secs 5

set xspan 100.0
set xmin 0.0
set xmax $xspan
set xtick [expr $xspan / 10]

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

        set vars(${param}plot) [createXYPlot .graphs.$param \
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

    set args [binary scan $retval ccccscs sor node id rssi temp volt pres]
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

    set data(id) $id
    set data(temperature) [format "%.2f" [expr (($temp * 1.8)+320)/10]]
    set data(voltage) [format "%.1f" [expr double(double($volt) / 10)]]
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
    global logfd

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

    puts $logfd "$timestamp $node $data(id) $data(temperature) \
      $data(voltage) $data(rssi) $data(pressure)"
    flush $logfd

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



#############################################################################
## Plotchart code with flat namespace suitable for importing into a 
## stand-alone tcl script that is portable as an exe.
#############################################################################

# plot3d.tcl --
#    Facilities to draw simple 3D plots in a dedicated canvas
#
# Note:
#    This source file contains the private functions for 3D plotting.
#    It is the companion of "plotchart.tcl"
#

# Draw3DAxes --
#    Draw the axes in a 3D plot
# Arguments:
#    w           Name of the canvas
#    xmin        Minimum x coordinate
#    xmax        Maximum x coordinate
#    xstep       Step size
#    ymin        Minimum y coordinate
#    ymax        Maximum y coordinate
#    ystep       Step size
#    zmin        Minimum z coordinate
#    zmax        Maximum z coordinate
#    zstep       Step size
#    names       List of labels for the x-axis (optional)
# Result:
#    None
# Note:
#    To keep the axes in positive orientation, the x-axis appears
#    on the right-hand side and the y-axis appears in front.
#    This may not be the most "intuitive" presentation though.
#
#    If the step for the x-axis is zero or negative, it is not
#    drawn - adopted from Keith Vetter's extension.
#
# Side effects:
#    Axes drawn in canvas
#
proc Draw3DAxes { w xmin  ymin  zmin
                                 xmax  ymax  zmax
                                 xstep ystep zstep
                                 {names {}}        } {
   global scaling

   $w delete axis3d

   #
   # Create the support lines first
   #
   foreach {pxxmin pyxmin} [coords3DToPixel $w $scaling($w,xmin) $scaling($w,ymin) $scaling($w,zmin)] {break}
   foreach {pxxmax pyxmax} [coords3DToPixel $w $scaling($w,xmax) $scaling($w,ymin) $scaling($w,zmin)] {break}
   foreach {pxymax pyymax} [coords3DToPixel $w $scaling($w,xmax) $scaling($w,ymax) $scaling($w,zmin)] {break}
   foreach {pxzmax pyzmax} [coords3DToPixel $w $scaling($w,xmax) $scaling($w,ymin) $scaling($w,zmax)] {break}
   foreach {pxzmx2 pyzmx2} [coords3DToPixel $w $scaling($w,xmin) $scaling($w,ymin) $scaling($w,zmax)] {break}
   foreach {pxymx2 pyymx2} [coords3DToPixel $w $scaling($w,xmin) $scaling($w,ymax) $scaling($w,zmin)] {break}
   foreach {pxzymx pyzymx} [coords3DToPixel $w $scaling($w,xmax) $scaling($w,ymax) $scaling($w,zmax)] {break}

   if { $xstep > 0 } {
       $w create line $pxxmax $pyxmax $pxxmin $pyxmin -fill black -tag axis3d
       $w create line $pxxmax $pyxmax $pxymax $pyymax -fill black -tag axis3d
       $w create line $pxymax $pyymax $pxymx2 $pyymx2 -fill black -tag axis3d
       $w create line $pxzmax $pyzmax $pxzymx $pyzymx -fill black -tag axis3d
       $w create line $pxxmax $pyxmax $pxzmax $pyzmax -fill black -tag axis3d
       $w create line $pxzmax $pyzmax $pxzmx2 $pyzmx2 -fill black -tag axis3d
       $w create line $pxymax $pyymax $pxzymx $pyzymx -fill black -tag axis3d
   }
   $w create line $pxxmin $pyxmin $pxymx2 $pyymx2 -fill black -tag axis3d
   $w create line $pxxmin $pyxmin $pxzmx2 $pyzmx2 -fill black -tag axis3d

   #
   # Numbers to the z-axis
   #
   set z $zmin
   while { $z < $zmax+0.5*$zstep } {
      foreach {xcrd ycrd} [coords3DToPixel $w $xmin $ymin $z] {break}
      set xcrd2 [expr {$xcrd-3}]
      set xcrd3 [expr {$xcrd-5}]

      $w create line $xcrd2 $ycrd $xcrd $ycrd -tag axis3d
      $w create text $xcrd3 $ycrd -text $z -tag axis3d -anchor e
      set z [expr {$z+$zstep}]
   }

   #
   # Numbers or labels to the x-axis (shown on the right!)
   #
   if { $xstep > 0 } {
       if { $names eq "" } {
           set x $xmin
           while { $x < $xmax+0.5*$xstep } {
               foreach {xcrd ycrd} [coords3DToPixel $w $x $ymax $zmin] {break}
               set xcrd2 [expr {$xcrd+4}]
               set xcrd3 [expr {$xcrd+6}]

               $w create line $xcrd2 $ycrd $xcrd $ycrd -tag axis3d
               $w create text $xcrd3 $ycrd -text $x -tag axis3d -anchor w
               set x [expr {$x+$xstep}]
           }
       } else {
           set x [expr {$xmin+0.5*$xstep}]
           foreach label $names {
               foreach {xcrd ycrd} [coords3DToPixel $w $x $ymax $zmin] {break}
               set xcrd2 [expr {$xcrd+6}]

               $w create text $xcrd2 $ycrd -text $label -tag axis3d -anchor w
               set x [expr {$x+$xstep}]
           }
       }
   }

   #
   # Numbers to the y-axis (shown in front!)
   #
   set y $ymin
   while { $y < $ymax+0.5*$ystep } {
      foreach {xcrd ycrd} [coords3DToPixel $w $xmin $y $zmin] {break}
      set ycrd2 [expr {$ycrd+3}]
      set ycrd3 [expr {$ycrd+5}]

      $w create line $xcrd $ycrd2 $xcrd $ycrd -tag axis3d
      $w create text $xcrd $ycrd3 -text $y -tag axis3d -anchor n
      set y [expr {$y+$ystep}]
   }

   set scaling($w,xstep) $xstep
   set scaling($w,ystep) $ystep
   set scaling($w,zstep) $zstep

   #
   # Set the default grid size
   #
   GridSize3D $w 10 10
}

# GridSize3D --
#    Set the grid size for a 3D function plot
# Arguments:
#    w           Name of the canvas
#    nxcells     Number of cells in x-direction
#    nycells     Number of cells in y-direction
# Result:
#    None
# Side effect:
#    Store the grid sizes in the private array
#
proc GridSize3D { w nxcells nycells } {
   global scaling

   set scaling($w,nxcells) $nxcells
   set scaling($w,nycells) $nycells
}

# Draw3DFunction --
#    Plot a function of x and y
# Arguments:
#    w           Name of the canvas
#    function    Name of a procedure implementing the function
# Result:
#    None
# Side effect:
#    The plot of the function - given the grid
#
proc Draw3DFunction { w function } {
   global scaling

   set nxcells $scaling($w,nxcells)
   set nycells $scaling($w,nycells)
   set xmin    $scaling($w,xmin)
   set xmax    $scaling($w,xmax)
   set ymin    $scaling($w,ymin)
   set ymax    $scaling($w,ymax)
   set dx      [expr {($xmax-$xmin)/double($nxcells)}]
   set dy      [expr {($ymax-$ymin)/double($nycells)}]

   foreach {fill border} $scaling($w,colours) {break}

   #
   # Draw the quadrangles making up the plot in the right order:
   # first y from minimum to maximum
   # then x from maximum to minimum
   #
   for { set j 0 } { $j < $nycells } { incr j } {
      set y1 [expr {$ymin + $dy*$j}]
      set y2 [expr {$y1   + $dy}]
      for { set i $nxcells } { $i > 0 } { incr i -1 } {
         set x2 [expr {$xmin + $dx*$i}]
         set x1 [expr {$x2   - $dx}]

         set z11 [$function $x1 $y1]
         set z12 [$function $x1 $y2]
         set z21 [$function $x2 $y1]
         set z22 [$function $x2 $y2]

         foreach {px11 py11} [coords3DToPixel $w $x1 $y1 $z11] {break}
         foreach {px12 py12} [coords3DToPixel $w $x1 $y2 $z12] {break}
         foreach {px21 py21} [coords3DToPixel $w $x2 $y1 $z21] {break}
         foreach {px22 py22} [coords3DToPixel $w $x2 $y2 $z22] {break}

         $w create polygon $px11 $py11 $px21 $py21 $px22 $py22 \
                           $px12 $py12 $px11 $py11 \
                           -fill $fill -outline $border
      }
   }
}

# Draw3DData --
#    Plot a matrix of data as a function of x and y
# Arguments:
#    w           Name of the canvas
#    data        Nested list of data in the form of a matrix
# Result:
#    None
# Side effect:
#    The plot of the data
#
proc Draw3DData { w data } {
   global scaling

   set  nxcells [llength [lindex $data 0]]
   set  nycells [llength $data]
   incr nxcells -1
   incr nycells -1

   set xmin    $scaling($w,xmin)
   set xmax    $scaling($w,xmax)
   set ymin    $scaling($w,ymin)
   set ymax    $scaling($w,ymax)
   set dx      [expr {($xmax-$xmin)/double($nxcells)}]
   set dy      [expr {($ymax-$ymin)/double($nycells)}]

   foreach {fill border} $scaling($w,colours) {break}

   #
   # Draw the quadrangles making up the data in the right order:
   # first y from minimum to maximum
   # then x from maximum to minimum
   #
   for { set j 0 } { $j < $nycells } { incr j } {
      set z1data [lindex $data $j]
      set z2data [lindex $data [expr {$j+1}]]
      set y1 [expr {$ymin + $dy*$j}]
      set y2 [expr {$y1   + $dy}]
      for { set i $nxcells } { $i > 0 } { incr i -1 } {
         set x2 [expr {$xmin + $dx*$i}]
         set x1 [expr {$x2   - $dx}]

         set z11 [lindex $z1data [expr {$i-1}]]
         set z21 [lindex $z1data $i           ]
         set z12 [lindex $z2data [expr {$i-1}]]
         set z22 [lindex $z2data $i           ]

         foreach {px11 py11} [coords3DToPixel $w $x1 $y1 $z11] {break}
         foreach {px12 py12} [coords3DToPixel $w $x1 $y2 $z12] {break}
         foreach {px21 py21} [coords3DToPixel $w $x2 $y1 $z21] {break}
         foreach {px22 py22} [coords3DToPixel $w $x2 $y2 $z22] {break}

         $w create polygon $px11 $py11 $px21 $py21 $px22 $py22 \
                           $px12 $py12 $px11 $py11 \
                           -fill $fill -outline $border
      }
   }
}

# Draw3DRibbon --
#     Plot yz-data as a 3D ribbon
#
# Arguments:
#     w               Widget to draw in
#     yzData          List of duples, each of which is y,z pair
#                     (y is left-to-right, z is up-and-down, x is front-to-back).
#
# Note:
#     Contributed by Keith Vetter (see the Wiki)
#
proc Draw3DRibbon { w yzData } { 
    global scaling

    set  nxcells 1
    set  nycells [llength $yzData]
    incr nxcells -1
    incr nycells -1

    set x1    $scaling($w,xmin)
    set x2    [expr {($scaling($w,xmax) - $x1)/10.0}]

    foreach {fill border} $scaling($w,colours) {break}

    #
    # Draw the quadrangles making up the data in the right order:
    # first y from minimum to maximum
    # then x from maximum to minimum
    #
    for { set j 0 } { $j < $nycells } { incr j } {
        set jj [expr {$j+1}]
        set y1 [lindex $yzData $j 0]
        set y2 [lindex $yzData $jj 0]
        set z1 [lindex $yzData $j 1]
        set z2 [lindex $yzData $jj 1]

        foreach {px11 py11} [coords3DToPixel $w $x1 $y1 $z1] break
        foreach {px12 py12} [coords3DToPixel $w $x1 $y2 $z2] break
        foreach {px21 py21} [coords3DToPixel $w $x2 $y1 $z1] break
        foreach {px22 py22} [coords3DToPixel $w $x2 $y2 $z2] break
        $w create polygon $px11 $py11 $px21 $py21 $px22 $py22 \
            $px12 $py12 $px11 $py11 \
            -fill $fill -outline $border
    }
}

# Draw3DLineFrom3Dcoordinates --
#    Plot a line in the three-dimensional axis system
# Arguments:
#    w           Name of the canvas
#    data        List of xyz-coordinates
#    colour      The colour to use
# Result:
#    None
# Side effect:
#    The projected line
#
proc Draw3DLineFrom3Dcoordinates { w data colour } {
   global scaling

   set xmin    $scaling($w,xmin)
   set xmax    $scaling($w,xmax)
   set xprev   {}

   set coords  {}
   set colours {}
   foreach {x y z} $data {
       foreach {px py} [coords3DToPixel $w $x $y $z] {break}

       lappend coords $px $py

       if { $xprev == {} } {
           set xprev $x
       }
       set factor [expr {0.5*(2.0*$xmax-$xprev-$x)/($xmax-$xmin)}]

       lappend colours [GreyColour $colour $factor]
       set xprev $x
   }

   foreach {xb yb} [lrange $coords 0 end-2] {xe ye} [lrange $coords 2 end] c [lrange $colours 0 end-1] {
       $w create line $xb $yb $xe $ye -fill $c
   }
}


# plotannot.tcl --
#    Facilities for annotating charts
#
# Note:
#    This source file contains such functions as to draw a
#    balloon text in an xy-graph.
#    It is the companion of "plotchart.tcl"
#

#
# Static data
#

# Index, three pairs of scale factors to determine xy-coordinates
set BalloonDir(north-west) {0  0  1 -2 -2  1  0}
set BalloonDir(north)      {1 -1  0  0 -3  1  0}
set BalloonDir(north-east) {2 -1  0  2 -2  0  1}
set BalloonDir(east)       {3  0 -1  3  0  0  1}
set BalloonDir(south-east) {4  0 -1  2  2 -1  0}
set BalloonDir(south)      {5  1  0  0  3 -1  0}
set BalloonDir(south-west) {6  1  0 -2  2  0 -1}
set BalloonDir(west)       {7  0  1 -3  0  0 -1}

set TextDir(centre)     c
set TextDir(center)     c
set TextDir(c)          c
set TextDir(west)       w
set TextDir(w)          w
set TextDir(north-west) nw
set TextDir(nw)         nw
set TextDir(north)      n
set TextDir(n)          n
set TextDir(north-east) ew
set TextDir(ne)         ew
set TextDir(east)       e
set TextDir(e)          e
set TextDir(south-west) nw
set TextDir(sw)         sw
set TextDir(south)      s
set TextDir(s)          s
set TextDir(south-east) ew
set TextDir(east)       e

# DefaultBalloon --
#    Set the default properties of balloon text and other types of annotation
# Arguments:
#    w           Name of the canvas
# Result:
#    None
# Side effects:
#    Stores the default settings
#
proc DefaultBalloon { w } {
    global settings

    foreach {option value} {font       fixed
                            margin     5
                            textcolour black
                            justify    left
                            arrowsize  5
                            background white
                            outline    black
                            rimwidth   1} {
        set settings($w,balloon$option) $value
    }
    foreach {option value} {font       fixed
                            colour     black
                            justify    left} {
        set settings($w,text$option) $value
    }
}

# ConfigBalloon --
#    Configure the properties of balloon text
# Arguments:
#    w           Name of the canvas
#    args        List of arguments
# Result:
#    None
# Side effects:
#    Stores the new settings for the next balloon text
#
proc ConfigBalloon { w args } {
    global settings

    foreach {option value} $args {
        set option [string range $option 1 end]
        switch -- $option {
            "font" -
            "margin" -
            "textcolour" -
            "justify" -
            "arrowsize" -
            "background" -
            "outline" -
            "rimwidth" {
                set settings($w,balloon$option) $value
            }
            "textcolor" {
                set settings($w,balloontextcolour) $value
            }
        }
    }
}

# ConfigPlainText --
#    Configure the properties of plain text
# Arguments:
#    w           Name of the canvas
#    args        List of arguments
# Result:
#    None
# Side effects:
#    Stores the new settings for the next plain text
#
proc ConfigPlainText { w args } {
    global settings

    foreach {option value} $args {
        set option [string range $option 1 end]
        switch -- $option {
            "font" -
            "textcolour" -
            "justify" {
                set settings($w,text$option) $value
            }
            "textcolor" {
                set settings($w,textcolour) $value
            }
            "textfont" {
                # Ugly hack!
                set settings($w,$option) $value
            }
        }
    }
}

# DrawBalloon --
#    Plot a balloon text in a chart
# Arguments:
#    w           Name of the canvas
#    x           X-coordinate of the point the arrow points to
#    y           Y-coordinate of the point the arrow points to
#    text        Text in the balloon
#    dir         Direction of the arrow (north, north-east, ...)
# Result:
#    None
# Side effects:
#    Text and polygon drawn in the chart
#
proc DrawBalloon { w x y text dir } {
    global settings
    global BalloonDir

    #
    # Create the item and then determine the coordinates
    # of the frame around the text
    #
    set item [$w create text 0 0 -text $text -tag BalloonText \
                 -font $settings($w,balloonfont) -fill $settings($w,balloontextcolour) \
                 -justify $settings($w,balloonjustify)]

    if { ![info exists BalloonDir($dir)] } {
        set dir south-east
    }

    foreach {xmin ymin xmax ymax} [$w bbox $item] {break}

    set xmin   [expr {$xmin-$settings($w,balloonmargin)}]
    set xmax   [expr {$xmax+$settings($w,balloonmargin)}]
    set ymin   [expr {$ymin-$settings($w,balloonmargin)}]
    set ymax   [expr {$ymax+$settings($w,balloonmargin)}]

    set xcentr [expr {($xmin+$xmax)/2}]
    set ycentr [expr {($ymin+$ymax)/2}]
    set coords [list $xmin   $ymin   \
                     $xcentr $ymin   \
                     $xmax   $ymin   \
                     $xmax   $ycentr \
                     $xmax   $ymax   \
                     $xcentr $ymax   \
                     $xmin   $ymax   \
                     $xmin   $ycentr ]

    set idx    [lindex $BalloonDir($dir) 0]
    set scales [lrange $BalloonDir($dir) 1 end]

    set factor $settings($w,balloonarrowsize)
    set extraCoords {}

    set xbase  [lindex $coords [expr {2*$idx}]]
    set ybase  [lindex $coords [expr {2*$idx+1}]]

    foreach {xscale yscale} $scales {
        set xnew [expr {$xbase+$xscale*$factor}]
        set ynew [expr {$ybase+$yscale*$factor}]
        lappend extraCoords $xnew $ynew
    }

    #
    # Insert the extra coordinates
    #
    set coords [eval lreplace [list $coords] [expr {2*$idx}] [expr {2*$idx+1}] \
                          $extraCoords]

    set xpoint [lindex $coords [expr {2*$idx+2}]]
    set ypoint [lindex $coords [expr {2*$idx+3}]]

    set poly [$w create polygon $coords -tag BalloonFrame \
                  -fill $settings($w,balloonbackground) \
                  -width $settings($w,balloonrimwidth)  \
                  -outline $settings($w,balloonoutline)]

    #
    # Position the two items
    #
    foreach {xtarget ytarget} [coordsToPixel $w $x $y] {break}
    set dx [expr {$xtarget-$xpoint}]
    set dy [expr {$ytarget-$ypoint}]
    $w move $item  $dx $dy
    $w move $poly  $dx $dy
    $w raise BalloonFrame
    $w raise BalloonText
}

# DrawPlainText --
#    Plot plain text in a chart
# Arguments:
#    w           Name of the canvas
#    x           X-coordinate of the point the text is positioned to
#    y           Y-coordinate of the point the text is positioned to
#    text        Text to be drawn
#    anchor      Anchor position (north, north-east, ..., defaults to centre)
# Result:
#    None
# Side effects:
#    Text drawn in the chart
#
proc DrawPlainText { w x y text {anchor centre} } {
    global settings
    global TextDir

    foreach {xtext ytext} [coordsToPixel $w $x $y] {break}

    if { [info exists TextDir($anchor)] } {
        set anchor $TextDir($anchor)
    } else {
        set anchor c
    }

    $w create text $xtext $ytext -text $text -tag PlainText \
         -font $settings($w,textfont) -fill $settings($w,textcolour) \
         -justify $settings($w,textjustify) -anchor $anchor

    $w raise PlainText
}

# DrawTimeBalloon --
#    Plot a balloon text in a TXPlot
# Arguments:
#    w           Name of the canvas
#    time        Time-coordinate of the point the arrow points to
#    y           Y-coordinate of the point the arrow points to
#    text        Text in the balloon
#    dir         Direction of the arrow (north, north-east, ...)
# Result:
#    None
# Side effects:
#    Text and polygon drawn in the chart
#
proc DrawTimeBalloon { w time y text dir } {

    DrawBalloon $w [clock scan $time] $y $text $dir
}

# DrawTimePlainText --
#    Plot plain text in a TXPlot
# Arguments:
#    w           Name of the canvas
#    time        Time-coordinate of the point the text is positioned to
#    y           Y-coordinate of the point the text is positioned to
#    text        Text to be drawn
#    anchor      Anchor position (north, north-east, ..., defaults to centre)
# Result:
#    None
# Side effects:
#    Text drawn in the chart
#
proc DrawTimePlainText { w time y text {anchor centre} } {

    DrawPlainText $w [clock scan $time] $y $text $anchor
}

# BrightenColour --
#    Compute a brighter colour
# Arguments:
#    color       Original colour
#    intensity   Colour to interpolate with
#    factor      Factor by which to brighten the colour
# Result:
#    New colour
# Note:
#    Adapted from R. Suchenwirths Wiki page on 3D bars
#
proc BrightenColour {color intensity factor} {
    foreach i {r g b} n [winfo rgb . $color] d [winfo rgb . $intensity] f [winfo rgb . white] {
        #checker exclude warnVarRef
        set $i [expr {int(255.*($n+($d-$n)*$factor)/$f)}]
    }
    #checker exclude warnUndefinedVar
    format #%02x%02x%02x $r $g $b
}

# DrawGradientBackground --
#    Add a gradient background to the plot
# Arguments:
#    w           Name of the canvas
#    colour      Main colour
#    dir         Direction of the gradient (left-right, top-down,
#                bottom-up, right-left)
#    intensity   Brighten (white) or darken (black) the colours
#    rect        (Optional) coordinates of the rectangle to be filled
# Result:
#    None
# Side effects:
#    Gradient background drawn in the chart
#
proc DrawGradientBackground { w colour dir intensity {rect {}} } {
    global scaling

    set pxmin $scaling($w,pxmin)
    set pxmax $scaling($w,pxmax)
    set pymin $scaling($w,pymin)
    set pymax $scaling($w,pymax)

    if { $rect != {} } {
        foreach {rxmin rymin rxmax rymax} $rect {break}
    } else {
        set rxmin $pxmin
        set rxmax $pxmax
        set rymin $pymin
        set rymax $pymax
    }

    switch -- $dir {
        "left-right" {
            set dir   h
            set first 0.0
            set last  1.0
            set fac   [expr {($pxmax-$pxmin)/50.0}]
        }
        "right-left" {
            set dir   h
            set first 1.0
            set last  0.0
            set fac   [expr {($pxmax-$pxmin)/50.0}]
        }
        "top-down" {
            set dir   v
            set first 0.0
            set last  1.0
            set fac   [expr {($pymin-$pymax)/50.0}]
        }
        "bottom-up" {
            set dir   v
            set first 1.0
            set last  0.0
            set fac   [expr {($pymin-$pymax)/50.0}]
        }
        default {
            set dir   v
            set first 0.0
            set last  1.0
            set fac   [expr {($pymin-$pymax)/50.0}]
        }
    }

    if { $dir == "h" } {
        set x2 $rxmin
        set y1 $rymin
        set y2 $rymax
    } else {
        set y2 $rymax
        set x1 $rxmin
        set x2 $rxmax
    }

    set n 50
    if { $dir == "h" } {
        set nmax [expr {ceil($n*($rxmax-$rxmin)/double($pxmax-$pxmin))}]
    } else {
        set nmax [expr {ceil($n*($rymin-$rymax)/double($pymin-$pymax))}]
    }
    for { set i 0 } { $i < $nmax } { incr i } {
        set factor [expr {($first*$i+$last*($n-$i-1))/double($n)}]
        set gcolour [BrightenColour $colour $intensity $factor]

        if { $dir == "h" } {
            set x1     $x2
            set x2     [expr {$rxmin+($i+1)*$fac}]
            if { $i == $nmax-1 } {
                set x2 $rxmax
            }
        } else {
            set y1     $y2
            set y2     [expr {$rymax+($i+1)*$fac}]
            if { $i == $nmax-1 } {
                set y2 $rymin
            }
        }

        $w create rectangle $x1 $y1 $x2 $y2 -fill $gcolour -outline $gcolour -tag {data background}
    }

    $w lower data
    $w lower background
}

# DrawImageBackground --
#    Add an image (tilde) to the background to the plot
# Arguments:
#    w           Name of the canvas
#    colour      Main colour
#    image       Name of the image
# Result:
#    None
# Side effects:
#    Image appears in the plot area, tiled if needed
#
proc DrawImageBackground { w image } {
    global scaling

    set pxmin $scaling($w,pxmin)
    set pxmax $scaling($w,pxmax)
    set pymin $scaling($w,pymin)
    set pymax $scaling($w,pymax)

    set iwidth  [image width $image]
    set iheight [image height $image]

    for { set y $pymax } { $y > $pymin } { set y [expr {$y-$iheight}] } {
        for { set x $pxmin } { $x < $pxmax } { incr x $iwidth } {
            $w create image $x $y -image $image -anchor sw -tags {data background}
        }
    }

    $w lower data
    $w lower background
}


# plotaxis.tcl --
#    Facilities to draw simple plots in a dedicated canvas
#
# Note:
#    This source file contains the functions for drawing the axes
#    and the legend. It is the companion of "plotchart.tcl"
#

# FormatNumber --
#    Format a number (either as double or as integer)
# Arguments:
#    format      Format string
#    number      Number to be formatted
# Result:
#    String containing the formatted number
# Note:
#    This procedure tries to format the string as a double first,
#    but to allow formats like %x, it also tries it that way.
#
proc FormatNumber { format number } {

    if { [catch {
        set string [format $format $number]
    } msg1] } {
        if { [catch {
            set string [format $format [expr {int($number)}]]
        } msg2] } {
            set string [format $format $number] ;# To get the original message
        }
    }

    return $string
}

# DrawYaxis --
#    Draw the y-axis
# Arguments:
#    w           Name of the canvas
#    ymin        Minimum y coordinate
#    ymax        Maximum y coordinate
#    ystep       Step size
#    args        Options (currently: -ylabels list)
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawYaxis { w ymin ymax ydelt args} {
    global scaling
    global config

    set scaling($w,ydelt) $ydelt

    $w delete "yaxis && $w"

    set linecolor    $config($w,leftaxis,color)
    set textcolor    $config($w,leftaxis,textcolor)
    set textfont     $config($w,leftaxis,font)
    set ticklength   $config($w,leftaxis,ticklength)
    set thickness    $config($w,leftaxis,thickness)
    set labeloffset  $config($w,leftaxis,labeloffset)
    set offtick      [expr {($ticklength > 0)? $ticklength+$labeloffset : $labeloffset}]

    if { $config($w,leftaxis,showaxle) } {
        $w create line $scaling($w,pxmin) $scaling($w,pymin) \
                       $scaling($w,pxmin) $scaling($w,pymax) \
                       -fill $linecolor -tag [list yaxis $w] -width $thickness
    }

    set format $config($w,leftaxis,format)
    if { [info exists scaling($w,-format,y)] } {
        set format $scaling($w,-format,y)
    }

    if { $ymax > $ymin } {
        set y [expr {$ymin+0.0}]  ;# Make sure we have the number in the right format
        set ym $ymax
    } else {
        set y [expr {$ymax+0.0}]
        set ym $ymin
    }
    set yt [expr {$ymin+0.0}]

    set scaling($w,yaxis) {}

    set ys      {}
    set yts     {}
    set ybackup {}
    set numeric 1

    if { $ydelt eq {} } {

        foreach {arg val} $args {
            switch -exact -- $arg {
                -ylabels {
                    set ys $val
                    set ydbackup [expr {($scaling($w,ymax)-$scaling($w,ymin))/([llength $val]-1.0)}]
                    set yb       $scaling($w,ymin)

                    foreach yval $val {
                        if { [string is double $yval] } {
                            lappend yts [expr {$yval+0.0}]
                        } else {
                            set numeric 0
                            lappend yts $yval
                        }
                        lappend ybackup $yb
                        set     yb      [expr {$yb + $ydbackup}]
                    }

                    set scaling($w,ydelt) $ys
                }
                default {
                    error "Argument $arg not recognized"
                }
            }
        }
    } else {
        set scaling($w,ydelt) $ydelt
        while { $y < $ym+0.0001*abs($ydelt) } {
            lappend ys $y
            lappend yts $yt
            set y  [expr {$y+abs($ydelt)}]
            set yt [expr {$yt+$ydelt}]
            if { abs($y) < 0.5*abs($ydelt) } {
                set yt 0.0
            }
        }
        set dyminor [expr {$ydelt/($config($w,leftaxis,minorticks)+1.0)}]
    }

    foreach y $ys yt $yts yb $ybackup {

        if { $numeric } {
            foreach {xcrd ycrd} [coordsToPixel $w $scaling($w,xmin) $yt] {break}
        } else {
            foreach {xcrd ycrd} [coordsToPixel $w $scaling($w,xmin) $yb] {break}
        }
        set xcrd2 [expr {$xcrd-$ticklength}]
        set xcrd3 [expr {$xcrd-$offtick}]

        if { $ycrd >= $scaling($w,pymin) && $ycrd <= $scaling($w,pymax) } {
            lappend scaling($w,yaxis) $ycrd

            #
            # Use the default format %.12g - this is equivalent to setting
            # tcl_precision to 12 - to solve overly precise labels in Tcl 8.5
            #
            if { [string is double $yt] } {
                set ylabel [format "%.12g" $yt]
                if { $format != "" } {
                    set ylabel [FormatNumber $format $y]
                }
            } else {
                set ylabel $yt
            }
            $w create line $xcrd2 $ycrd $xcrd $ycrd -tag [list yaxis $w] -fill $linecolor

            if { $config($w,leftaxis,shownumbers) } {
                $w create text $xcrd3 $ycrd -text $ylabel -tag [list yaxis $w] -anchor e \
                    -fill $textcolor -font $textfont
            }

            if { $ydelt != {} && $numeric && $yt < $ym } {
                for {set i 1} {$i <= $config($w,leftaxis,minorticks)} {incr i} {
                    set xcrd4  [expr {$xcrd-$ticklength*0.6}]
                    set yminor [expr {$yt  + $i * $dyminor}]
                    foreach {xcrd ycrd4} [coordsToPixel $w $scaling($w,xmin) $yminor] {break}
                    $w create line $xcrd4 $ycrd4 $xcrd $ycrd4 -tag [list yaxis $w] -fill $linecolor
                }
            }
        }
    }
}

# DrawRightaxis --
#    Draw the y-axis on the right-hand side
# Arguments:
#    w           Name of the canvas
#    ymin        Minimum y coordinate
#    ymax        Maximum y coordinate
#    ystep       Step size
#    args        Options (currently: -ylabels list)
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawRightaxis { w ymin ymax ydelt args } {
    global scaling
    global config

    set scaling($w,ydelt) $ydelt

    $w delete "raxis && $w"

    set linecolor    $config($w,rightaxis,color)
    set textcolor    $config($w,rightaxis,textcolor)
    set textfont     $config($w,rightaxis,font)
    set thickness    $config($w,rightaxis,thickness)
    set ticklength   $config($w,rightaxis,ticklength)
    set labeloffset  $config($w,leftaxis,labeloffset)
    set offtick      [expr {($ticklength > 0)? $ticklength+$labeloffset : $labeloffset}]

    if { $config($w,rightaxis,showaxle) } {
        $w create line $scaling($w,pxmax) $scaling($w,pymin) \
                       $scaling($w,pxmax) $scaling($w,pymax) \
                       -fill $linecolor -tag [list raxis $w] -width $thickness
    }

    set format $config($w,rightaxis,format)
    if { [info exists scaling($w,-format,y)] } {
        set format $scaling($w,-format,y)
    }

    if { $ymax > $ymin } {
        set y [expr {$ymin+0.0}]  ;# Make sure we have the number in the right format
        set ym $ymax
    } else {
        set y [expr {$ymax+0.0}]
        set ym $ymin
    }
    set yt      [expr {$ymin+0.0}]

    set scaling($w,yaxis) {}

    set ys       {}
    set yts      {}
    set ybackup  {}
    set numeric  1

    if { $ydelt eq {} } {

        foreach {arg val} $args {
            switch -exact -- $arg {
                -ylabels {
                    set ys $val
                    set ydbackup [expr {($scaling($w,ymax)-$scaling($w,ymin))/([llength $val]-1.0)}]
                    set yb       $scaling($w,ymin)

                    foreach yval $val {
                        if { [string is double $yval] } {
                            lappend yts [expr {$yval+0.0}]
                        } else {
                            set numeric 0
                            lappend yts $yval
                        }
                        lappend ybackup $yb
                        set     yb      [expr {$yb + $ydbackup}]
                    }

                    set scaling($w,ydelt) $ys
                }
                default {
                    error "Argument $arg not recognized"
                }
            }
        }
    } else {
        set scaling($w,ydelt) $ydelt
        while { $y < $ym+0.0001*abs($ydelt) } {
            lappend ys $y
            lappend yts $yt
            set y  [expr {$y+abs($ydelt)}]
            set yt [expr {$yt+$ydelt}]
            if { abs($y) < 0.5*abs($ydelt) } {
                set yt 0.0
            }
        }
        set dyminor [expr {$ydelt/($config($w,rightaxis,minorticks)+1.0)}]
    }


    foreach y $ys yt $yts yb $ybackup {

        if { $numeric } {
            foreach {xcrd ycrd} [coordsToPixel $w $scaling($w,xmax) $yt] {break}
        } else {
            foreach {xcrd ycrd} [coordsToPixel $w $scaling($w,xmax) $yb] {break}
        }
        set xcrd2 [expr {$xcrd+$ticklength}]
        set xcrd3 [expr {$xcrd+$offtick}]

        if { $ycrd >= $scaling($w,pymin) && $ycrd <= $scaling($w,pymax) } {
            lappend scaling($w,yaxis) $ycrd

            #
            # Use the default format %.12g - this is equivalent to setting
            # tcl_precision to 12 - to solve overly precise labels in Tcl 8.5
            #
            if { [string is double $yt] } {
                set ylabel [format "%.12g" $yt]
                if { $format != "" } {
                    set ylabel [FormatNumber $format $y]
                }
            } else {
                set ylabel $yt
            }
            $w create line $xcrd2 $ycrd $xcrd $ycrd -tag [list raxis $w] -fill $linecolor

            if { $config($w,leftaxis,shownumbers) } {
                $w create text $xcrd3 $ycrd -text $ylabel -tag [list raxis $w] -anchor w \
                    -fill $textcolor -font $textfont
            }

            if { $ydelt != {} && $numeric && $yt < $ym } {
                for {set i 1} {$i <= $config($w,rightaxis,minorticks)} {incr i} {
                    set xcrd4  [expr {$xcrd+$ticklength*0.6}]
                    set yminor [expr {$yt  + $i * $dyminor}]
                    foreach {xcrd ycrd4} [coordsToPixel $w $scaling($w,xmax) $yminor] {break}
                    $w create line $xcrd4 $ycrd4 $xcrd $ycrd4 -tag [list raxis $w] -fill $linecolor
                }
            }
        }
    }
}

# DrawLogYaxis --
#    Draw the logarithmic y-axis
# Arguments:
#    w           Name of the canvas
#    ymin        Minimum y coordinate
#    ymax        Maximum y coordinate
#    ystep       Step size
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawLogYaxis { w ymin ymax ydelt } {
    global scaling
    global config

    set scaling($w,ydelt) $ydelt

    $w delete "yaxis && $w"

    set linecolor    $config($w,leftaxis,color)
    set textcolor    $config($w,leftaxis,textcolor)
    set textfont     $config($w,leftaxis,font)
    set thickness    $config($w,leftaxis,thickness)
    set ticklength   $config($w,leftaxis,ticklength)
    set labeloffset  $config($w,leftaxis,labeloffset)
    set offtick      [expr {($ticklength > 0)? $ticklength+$labeloffset : $labeloffset}]

    if { $config($w,leftaxis,showaxle) } {
        $w create line $scaling($w,pxmin) $scaling($w,pymin) \
                       $scaling($w,pxmin) $scaling($w,pymax) \
                       -fill $linecolor -tag [list yaxis $w] -width $thickness
    }

    set format $config($w,leftaxis,format)
    if { [info exists scaling($w,-format,y)] } {
        set format $scaling($w,-format,y)
    }

    set scaling($w,yaxis) {}

    set y       [expr {pow(10.0,floor(log10($ymin)))}]
    set ylogmax [expr {pow(10.0,ceil(log10($ymax)))+0.1}]

    while { $y < $ylogmax } {

        #
        # Labels and tickmarks
        #
        foreach factor {1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0} {
            set yt [expr {$y*$factor}]
            if { $yt < $ymin } continue
            if { $yt > $ymax } break

            foreach {xcrd ycrd} [coordsToPixel $w $scaling($w,xmin) [expr {log10($yt)}]] {break}
            set xcrd2 [expr {$xcrd-$ticklength}]
            set xcrd3 [expr {$xcrd-$offtick}]

            lappend scaling($w,yaxis) $ycrd

            #
            # Use the default format %.12g - this is equivalent to setting
            # tcl_precision to 12 - to solve overly precise labels in Tcl 8.5
            #
            set ylabel [format "%.12g" $y]
            if { $format != "" } {
                set ylabel [FormatNumber $format $y]
            }
            $w create line $xcrd2 $ycrd $xcrd $ycrd -tag yaxis -fill $linecolor
            if { $factor == 1.0 && $config($w,leftaxis,showaxle) } {
                $w create text $xcrd3 $ycrd -text $ylabel -tag [list yaxis $w] -anchor e \
                    -fill $textcolor -font $textfont
            }
        }
        set y [expr {10.0*$y}]
    }

    set scaling($w,ydelt) $ydelt
}

# DrawXaxis --
#    Draw the x-axis
# Arguments:
#    w           Name of the canvas
#    xmin        Minimum x coordinate
#    xmax        Maximum x coordinate
#    xstep       Step size
#    args        Options (currently: -xlabels list)
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawXaxis { w xmin xmax xdelt args } {
    global scaling
    global config

    $w delete "xaxis && $w"

    set linecolor    $config($w,bottomaxis,color)
    set textcolor    $config($w,bottomaxis,textcolor)
    set textfont     $config($w,bottomaxis,font)
    set thickness    $config($w,bottomaxis,thickness)
    set ticklength   $config($w,bottomaxis,ticklength)
    set labeloffset  $config($w,leftaxis,labeloffset)
    set offtick      [expr {($ticklength > 0)? $ticklength+$labeloffset : $labeloffset}]

    if { $config($w,bottomaxis,showaxle) } {
        $w create line $scaling($w,pxmin) $scaling($w,pymax) \
                       $scaling($w,pxmax) $scaling($w,pymax) \
                       -fill $linecolor -tag [list xaxis $w] -width $thickness
    }

    set format $config($w,bottomaxis,format)
    if { [info exists scaling($w,-format,x)] } {
        set format $scaling($w,-format,x)
    }

    if { $xmax > $xmin } {
        set x [expr {$xmin+0.0}]  ;# Make sure we have the number in the right format
        set xm $xmax
    } else {
        set x [expr {$xmax+0.0}]
        set xm $xmin
    }
    set xt [expr {$xmin+0.0}]
    set scaling($w,xaxis) {}

    set xs      {}
    set xts     {}
    set xbackup {}
    set numeric 1

    if { $xdelt eq {} } {
        set numeric 1

        foreach {arg val} $args {
            switch -exact -- $arg {
                -xlabels {
                    set xs       $val
                    set xdbackup [expr {($scaling($w,xmax)-$scaling($w,xmin))/([llength $val]-1.0)}]
                    set xb       $scaling($w,xmin)

                    foreach xval $val {
                        if { [string is double $xval] } {
                            lappend xts [expr {$xval+0.0}]
                        } else {
                            set numeric 0
                            lappend xts $xval
                        }
                        lappend xbackup $xb
                        set     xb      [expr {$xb + $xdbackup}]
                    }

                    set scaling($w,xdelt) $xs

                }
                default {
                    error "Argument $arg not recognized"
                }
            }
        }
    } else {
        set scaling($w,xdelt) $xdelt
        while { $x < $xm+0.5*abs($xdelt) } {
            lappend xs       $x
            lappend xts      $xt
            lappend xbackup  $xt
            set x  [expr {$x+abs($xdelt)}]
            set xt [expr {$xt+$xdelt}]
            if { abs($x) < 0.5*abs($xdelt) } {
                set xt 0.0
            }
        }
        set dxminor [expr {$xdelt/($config($w,bottomaxis,minorticks)+1.0)}]
    }
    foreach x $xs xt $xts xb $xbackup {

        if { $numeric } {
            foreach {xcrd ycrd} [coordsToPixel $w $xt $scaling($w,ymin)] {break}
        } else {
            foreach {xcrd ycrd} [coordsToPixel $w $xb $scaling($w,ymin)] {break}
        }
        set ycrd2 [expr {$ycrd+$ticklength}]
        set ycrd3 [expr {$ycrd+$offtick}]

        if { $xcrd >= $scaling($w,pxmin) && $xcrd <= $scaling($w,pxmax) } {
            lappend scaling($w,xaxis) $xcrd

            #
            # Use the default format %.12g - this is equivalent to setting
            # tcl_precision to 12 - to solve overly precise labels in Tcl 8.5
            #
            if { [string is double $xt] } {
                set xlabel [format "%.12g" $xt]
                if { $format != "" } {
                    set xlabel [FormatNumber $format $xt]
                }
            } else {
                set xlabel $xt
            }

            $w create line $xcrd $ycrd2 $xcrd $ycrd -tag [list xaxis $w] -fill $linecolor

            if { $config($w,bottomaxis,shownumbers) } {
                $w create text $xcrd $ycrd3 -text $xlabel -tag [list xaxis $w] -anchor n \
                     -fill $textcolor -font $textfont
            }

            if { $xdelt != {} && $numeric && $xt < $xm } {
                for {set i 1} {$i <= $config($w,bottomaxis,minorticks)} {incr i} {
                    set ycrd4  [expr {$ycrd+$ticklength*0.6}]
                    set xminor [expr {$xt  + $i * $dxminor}]
                    foreach {xcrd4 ycrd} [coordsToPixel $w $xminor $scaling($w,ymin)] {break}
                    $w create line $xcrd4 $ycrd4 $xcrd4 $ycrd -tag [list xaxis $w] -fill $linecolor
                }
            }
        }
    }
}

# DrawLogXaxis --
#    Draw the logarithmic x-axis
# Arguments:
#    w           Name of the canvas
#    xmin        Minimum x coordinate
#    xmax        Maximum x coordinate
#    xstep       Step size
#    args        Options (currently: -xlabels list)
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawLogXaxis { w xmin xmax xdelt args } {
    global scaling
    global config

    $w delete "xaxis && $w"

    set linecolor    $config($w,bottomaxis,color)
    set textcolor    $config($w,bottomaxis,textcolor)
    set textfont     $config($w,bottomaxis,font)
    set thickness    $config($w,bottomaxis,thickness)
    set ticklength   $config($w,bottomaxis,ticklength)
    set labeloffset  $config($w,leftaxis,labeloffset)
    set offtick      [expr {($ticklength > 0)? $ticklength+$labeloffset : $labeloffset}]

    if { $config($w,bottomaxis,showaxle) } {
        $w create line $scaling($w,pxmin) $scaling($w,pymax) \
                       $scaling($w,pxmax) $scaling($w,pymax) \
                       -fill $linecolor -tag [list xaxis $w] -width $thickness
    }

    set format $config($w,bottomaxis,format)
    if { [info exists scaling($w,-format,x)] } {
        set format $scaling($w,-format,x)
    }

    set scaling($w,xaxis) {}

    set x       [expr {pow(10.0,floor(log10($xmin)))}]
    set xlogmax [expr {pow(10.0,ceil(log10($xmax)))+0.1}]

    while { $x < $xlogmax } {
        #
        # Labels and tickmarks
        #
        foreach factor {1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0} {
            set xt [expr {$x*$factor}]
            if { $xt < $xmin } continue
            if { $xt > $xmax } break

            foreach {xcrd ycrd} [coordsToPixel $w [expr {log10($xt)}] $scaling($w,ymin)] {break}
            set ycrd2 [expr {$ycrd+$ticklength}]
            set ycrd3 [expr {$ycrd+$offtick}]

            if {($xcrd >= $scaling($w,pxmin)) && ($xcrd <= $scaling($w,pxmax))} {
                lappend scaling($w,xaxis) $xcrd

                #
                # Use the default format %.12g - this is equivalent to setting
                # tcl_precision to 12 - to solve overly precise labels in Tcl 8.5
                #
                set xlabel [format "%.12g" $xt]
                if { $format != "" } {
                    set xlabel [FormatNumber $format $xt]
                }
                $w create line $xcrd $ycrd2 $xcrd $ycrd -tag [list xaxis $w] -fill $linecolor
                if { $factor == 1.0 && $config($w,bottomaxis,shownumbers) } {
                    $w create text $xcrd $ycrd3 -text $xlabel -tag [list xaxis $w] -anchor n \
                        -fill $textcolor -font $textfont
                }
            }
        }
        set x [expr {10.0*$x}]
    }

    set scaling($w,xdelt) $xdelt
}

# DrawXtext --
#    Draw text to the x-axis
# Arguments:
#    w           Name of the canvas
#    args        Text to be drawn (more than one argument if rendering in on)
# Result:
#    None
# Side effects:
#    Text drawn in canvas
#
proc DrawXtext { w args } {
    global scaling
    global config

    set textcolor  $config($w,bottomaxis,textcolor)
    set textfont   $config($w,bottomaxis,font)

    set xt [expr {($scaling($w,pxmin)+$scaling($w,pxmax))/2}]
    set yt [expr {$scaling($w,pymax)+$config($w,font,char_height)+4}]

    $w delete "xtext && $w"
    if {$config($w,bottomaxis,render) eq "simple"} {
        $w create text $xt $yt -text [lindex $args 0] -fill $textcolor -anchor n -font $textfont -tags [list xtext $w]
    } elseif {$config($w,bottomaxis,render) eq "text"} {
        RenderText $w $xt $yt -text $args -anchor n -font $textfont -tags [list xtext $w] \
           -fill $textcolor
    }
}

# DrawYtext --
#    Draw text to the y-axis
# Arguments:
#    w           Name of the canvas
#    text        Text to be drawn
# Result:
#    None
# Side effects:
#    Text drawn in canvas
#
proc DrawYtext { w text } {
    global scaling
    global config


    if { [string match "r*" $w] == 0 } {
        set textcolor  $config($w,leftaxis,textcolor)
        set textfont   $config($w,leftaxis,font)
        set xt         $scaling($w,pxmin)
        set anchor     se
    } else {
        set textcolor  $config($w,rightaxis,textcolor)
        set textfont   $config($w,rightaxis,font)
        set xt $scaling($w,pxmax)
        set anchor     sw
    }
    set yt [expr {$scaling($w,pymin)-$config($w,font,char_height)/2}]

    $w delete "ytext && $w"
    $w create text $xt $yt -text $text -fill $textcolor -anchor $anchor -font $textfont -tags [list ytext $w]
}

# DrawVtext --
#    Draw vertical text to the y-axis
# Arguments:
#    w           Name of the canvas
#    text        Text to be drawn
# Result:
#    None
# Side effects:
#    Text drawn in canvas
# Note:
#    This requires Tk 8.6 or later
#
proc DrawVtext { w text } {
    global scaling
    global config

    if { [package vsatisfies [package present Tk] 8.6] } {
        set bbox [$w bbox yaxis]
        set xt [expr {[lindex $bbox 0] - $config($w,leftaxis,vtextoffset)}]
        set yt [expr {($scaling($w,pymin) + $scaling($w,pymax)) / 2}]

        $w delete "vtext && $w"
        $w create text $xt $yt -text $text -fill black -anchor s -angle 90 -tags [list vtext $w] \
            -font $config($w,leftaxis,font) -fill $config($w,leftaxis,textcolor)
    }
}

# DrawPolarAxes --
#    Draw thw two polar axes
# Arguments:
#    w           Name of the canvas
#    rad_max     Maximum radius
#    rad_step    Step in radius
# Result:
#    None
# Side effects:
#    Axes drawn in canvas
#
proc DrawPolarAxes { w rad_max rad_step } {
    global config

    set linecolor  $config($w,axis,color)
    set textcolor  $config($w,axis,textcolor)
    set textfont   $config($w,axis,font)
    set thickness  $config($w,axis,thickness)
    set bgcolor    $config($w,background,innercolor)

    #
    # Draw the spikes
    #
    set angle 0.0

    foreach {xcentre ycentre} [polarToPixel $w 0.0 0.0] {break}

    while { $angle < 360.0 } {
        foreach {xcrd ycrd} [polarToPixel $w $rad_max $angle] {break}
        foreach {xtxt ytxt} [polarToPixel $w [expr {1.05*$rad_max}] $angle] {break}
        $w create line $xcentre $ycentre $xcrd $ycrd -fill $linecolor -width $thickness
        if { $xcrd > $xcentre } {
            set dir w
        } else {
            set dir e
        }
        $w create text $xtxt $ytxt -text $angle -anchor $dir -fill $textcolor -font $textfont -tags [list polar $w]

        set angle [expr {$angle+30}]
    }

    #
    # Draw the concentric circles
    #
    set rad $rad_step

    while { $rad < $rad_max+0.5*$rad_step } {
        foreach {xright ytxt}    [polarToPixel $w $rad    0.0] {break}
        foreach {xleft  ycrd}    [polarToPixel $w $rad  180.0] {break}
        foreach {xcrd   ytop}    [polarToPixel $w $rad   90.0] {break}
        foreach {xcrd   ybottom} [polarToPixel $w $rad  270.0] {break}

        set oval [$w create oval $xleft $ytop $xright $ybottom -outline $linecolor -width $thickness -fill {} \
                     -tags [list polar $w]]
        $w lower $oval

        $w create text $xright [expr {$ytxt+3}] -text $rad -anchor n -fill $textcolor -font $textfont -tags [list polar $w]

        set rad [expr {$rad+$rad_step}]
    }
}

# DrawXlabels --
#    Draw the labels to an x-axis (barchart)
# Arguments:
#    w           Name of the canvas
#    xlabels     List of labels
#    noseries    Number of series or "stacked"
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawXlabels { w xlabels noseries } {
    global scaling
    global config

    set linecolor  $config($w,bottomaxis,color)
    set textcolor  $config($w,bottomaxis,textcolor)
    set textfont   $config($w,bottomaxis,font)
    set thickness  $config($w,bottomaxis,thickness)

    $w delete "xaxis && $w"

    $w create line $scaling($w,pxmin) $scaling($w,pymax) \
                   $scaling($w,pxmax) $scaling($w,pymax) \
                   -fill $linecolor -width $thickness -tag [list xaxis $w]

    if { $noseries eq "stacked" } {
        set x 1.0
    } else {
        set x 1.0
        #set x [expr {0.5 + int($noseries)/(2.0*$noseries)}]
    }
    set scaling($w,ybase) {}
    foreach label $xlabels {
        foreach {xcrd ycrd} [coordsToPixel $w $x $scaling($w,ymin)] {break}
        set ycrd [expr {$ycrd+2}]
        $w create text $xcrd $ycrd -text $label -tag [list xaxis $w] -anchor n \
            -fill $textcolor -font $textfont
        set x [expr {$x+1.0}]

        lappend scaling($w,ybase) 0.0
    }

    if { $noseries != "stacked" } {
        set scaling($w,stacked)  0
        set scaling($w,xshift)   [expr {$config($w,bar,barwidth)/$noseries}]
        set scaling($w,barwidth) [expr {$config($w,bar,barwidth)/$noseries}]
        set scaling($w,xbase)    [expr {1.0 - $config($w,bar,barwidth)/2.0}]
    } else {
        set scaling($w,stacked)  1
        set scaling($w,xshift)   0.0
        set scaling($w,barwidth) $config($w,bar,barwidth)
        set scaling($w,xbase)    [expr {1.0 - $config($w,bar,barwidth)/2.0}]
    }
}

# DrawYlabels --
#    Draw the labels to a y-axis (barchart)
# Arguments:
#    w           Name of the canvas
#    ylabels     List of labels
#    noseries    Number of series or "stacked"
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawYlabels { w ylabels noseries } {
    global scaling
    global config

    set linecolor  $config($w,leftaxis,color)
    set textcolor  $config($w,leftaxis,textcolor)
    set textfont   $config($w,leftaxis,font)
    set thickness  $config($w,leftaxis,thickness)

    $w delete "yaxis && $w"

    $w create line $scaling($w,pxmin) $scaling($w,pymin) \
                   $scaling($w,pxmin) $scaling($w,pymax) \
                   -fill $linecolor -width $thickness -tag [list yaxis $w]

    if { $noseries != "stacked" } {
        set y 1.0
        #set y [expr {0.5 + int($noseries)/(2.0*$noseries)}]
    }  else {
        set y 1.0
    }
    set scaling($w,xbase) {}
    foreach label $ylabels {
        foreach {xcrd ycrd} [coordsToPixel $w $scaling($w,xmin) $y] {break}
        set xcrd [expr {$xcrd-2}]
        $w create text $xcrd $ycrd -text $label -tag [list yaxis $w] -anchor e \
            -fill $textcolor -font $textfont
        set y [expr {$y+1.0}]

        lappend scaling($w,xbase) 0.0
    }

    if { $noseries != "stacked" } {
        set scaling($w,stacked)  0
        set scaling($w,yshift)   [expr {$config($w,bar,barwidth)/$noseries}]
        set scaling($w,barwidth) [expr {$config($w,bar,barwidth)/$noseries}]
        set scaling($w,ybase)    [expr {1.0 - $config($w,bar,barwidth)/2.0}]
    } else {
        set scaling($w,stacked)  1
        set scaling($w,yshift)   0.0
        set scaling($w,barwidth) $config($w,bar,barwidth)
        set scaling($w,ybase)    [expr {1.0 - $config($w,bar,barwidth)/2.0}]
    }
}

# XConfig --
#    Configure the x-axis for an XY plot
# Arguments:
#    w           Name of the canvas
#    args        Option and value pairs
# Result:
#    None
#
proc XConfig { w args } {
    AxisConfig xyplot $w x DrawXaxis $args
}

# YConfig --
#    Configure the y-axis for an XY plot
# Arguments:
#    w           Name of the canvas
#    args        Option and value pairs
# Result:
#    None
#
proc YConfig { w args } {
    if { ! [string match "r*" $w] } {
        AxisConfig xyplot $w y DrawYaxis $args
    } else {
        AxisConfig xyplot $w y DrawRightaxis $args
    }
}

# LogXConfig, ... --
#    Configure the x-axis for an logX-Y, X-logY or logX-logY plot
# Arguments:
#    w           Name of the canvas
#    args        Option and value pairs
# Result:
#    None
#
proc XConfigLogXY { w args } {
    AxisConfig logxyplot $w x DrawLogXaxis $args
}

proc XConfigXLogY { w args } {
    AxisConfig xlogyplot $w x DrawXaxis $args
}

proc XConfigLogXLogY { w args } {
    AxisConfig logxlogyplot $w x DrawLogXaxis $args
}

# LogYConfig --
#    Configure the y-axis for an X-logY, X-logY or logX-logY plot
# Arguments:
#    w           Name of the canvas
#    args        Option and value pairs
# Result:
#    None
#
proc YConfigLogXY { w args } {
    if { ! [string match "r*" $w] } {
        AxisConfig logxyplot $w y DrawYaxis $args
    } else {
        #
        # TODO: this is not supported yet
        #
        AxisConfig xyplot $w y DrawRightaxis $args
    }
}

proc YConfigXLogY { w args } {
    if { ! [string match "r*" $w] } {
        AxisConfig xlogyplot $w y DrawLogYaxis $args
    } else {
        #
        # TODO: this is not supported yet
        #
        AxisConfig xyplot $w y DrawRightaxis $args
    }
}

proc YConfigLogXLogY { w args } {
    if { ! [string match "r*" $w] } {
        AxisConfig logxlogyplot $w y DrawLogYaxis $args
    } else {
        #
        # TODO: this is not supported yet
        #
        AxisConfig xyplot $w y DrawRightaxis $args
    }
}

# AxisConfig --
#    Configure an axis and redraw it if necessary
# Arguments:
#    plottype       Type of plot
#    w              Name of the canvas
#    orient         Orientation of the axis
#    drawmethod     Drawing method
#    option_values  Option/value pairs
# Result:
#    None
#
# Note:
#    Merge the old configuration system with the new
#
proc AxisConfig { plottype w orient drawmethod option_values } {
    global config
    global scaling
    global axis_options
    global axis_option_clear
    global axis_option_values
    global axis_option_config

    set clear_data 0

    foreach {option value} $option_values {
        set idx [lsearch $axis_options $option]
        if { $idx < 0 } {
            return -code error "Unknown or invalid option: $option (value: $value)"
        } else {
            set clear_data [lindex  $axis_option_clear  $idx]
            set values     [lindex  $axis_option_values [expr {2*$idx+1}]]
            set isconfig   [lindex  $axis_option_config $idx]
            if { $values != "..." } {
                if { [lsearch $values $value] < 0 } {
                    return -code error "Unknown or invalid value: $value for option $option - $values"
                }
            }
            if { $isconfig } {
                if { $orient == "x" } {
                    set axis bottomaxis
                }
                if { $orient == "y" } {
                    set axis leftaxis
                }
                set config($w,$axis,[string range $option 1 end]) $value
            } else {
                set scaling($w,$option,$orient) $value
            }
            if { $option == "-scale" } {
                set min  ${orient}min
                set max  ${orient}max
                set delt ${orient}delt
                foreach [list $min $max $delt] $value {break}
                #checker exclude warnVarRef
                set scaling($w,$min)  [set $min]
                #checker exclude warnVarRef
                set scaling($w,$max)  [set $max]
                #checker exclude warnVarRef
                set scaling($w,$delt) [set $delt]
            }
        }
    }

    if { $clear_data }  {
        $w delete data
    }

    set xmin $scaling($w,xmin)
    set xmax $scaling($w,xmax)
    set ymin $scaling($w,ymin)
    set ymax $scaling($w,ymax)

    switch -- $plottype {
        "logxyplot" {
            set xmin [expr {pow(10.0,$scaling($w,xmin))}]
            set xmax [expr {pow(10.0,$scaling($w,xmax))}]
        }
        "xlogyplot" {
            set ymin [expr {pow(10.0,$scaling($w,ymin))}]
            set ymax [expr {pow(10.0,$scaling($w,ymax))}]
        }
        "logxlogyplot" {
            set xmin [expr {pow(10.0,$scaling($w,xmin))}]
            set xmax [expr {pow(10.0,$scaling($w,xmax))}]
            set ymin [expr {pow(10.0,$scaling($w,ymin))}]
            set ymax [expr {pow(10.0,$scaling($w,ymax))}]
        }
    }

    set originalSystem $scaling($w,coordSystem)
    set scaling($w,coordSystem) 0


    if { $orient == "x" } {
        if { [llength $scaling($w,xdelt)] == 1 } {
            #$drawmethod $w $scaling($w,xmin) $scaling($w,xmax) $scaling($w,xdelt)
            $drawmethod $w $xmin $xmax $scaling($w,xdelt)
        } else {
            #$drawmethod $w $scaling($w,xmin) $scaling($w,xmax) {} -xlabels $scaling($w,xdelt)
            $drawmethod $w $xmin $xmax {} -xlabels $scaling($w,xdelt)
        }
    }
    if { $orient == "y" } {
        if { [llength $scaling($w,ydelt)] == 1 } {
            #$drawmethod $w $scaling($w,ymin) $scaling($w,ymax) $scaling($w,ydelt)
            $drawmethod $w $ymin $ymax $scaling($w,ydelt)
        } else {
            #$drawmethod $w $scaling($w,ymin) $scaling($w,ymax) {} -ylabels $scaling($w,ydelt)
            $drawmethod $w $ymin $ymax {} -ylabels $scaling($w,ydelt)
        }
    }
    if { $orient == "z" } {
        $drawmethod $w $scaling($w,zmin) $scaling($w,zmax) $scaling($w,zdelt)
    }

    set scaling($w,coordSystem) $originalSystem
}

# DrawXTicklines --
#    Draw the ticklines for the x-axis
# Arguments:
#    w           Name of the canvas
#    colour      Colour of the ticklines
#    dash        Dash pattern
# Result:
#    None
#
proc DrawXTicklines { w {colour black} {dash lines}} {
    DrawTicklines $w x $colour $dash
}

# DrawYTicklines --
#    Draw the ticklines for the y-axis
# Arguments:
#    w           Name of the canvas
#    colour      Colour of the ticklines
#    dash        Dash pattern
# Result:
#    None
#
proc DrawYTicklines { w {colour black} {dash lines}} {
    DrawTicklines $w y $colour $dash
}

# DrawTicklines --
#    Draw the ticklines
# Arguments:
#    w           Name of the canvas
#    axis        Which axis (x or y)
#    colour      Colour of the ticklines
#    dash        Dash pattern
# Result:
#    None
#
proc DrawTicklines { w axis colour dash } {
    global scaling
    global pattern

    if { ! [info exists pattern($dash)] } {
        set dash "lines"
    }

    if { $axis == "x" } {
        #
        # Cater for both regular x-axes and time-axes
        #
        if { [info exists scaling($w,xaxis)] } {
            set botaxis xaxis
        } else {
            set botaxis taxis
        }
        $w delete [list xtickline && $w]
        if { $colour != {} } {
            foreach x $scaling($w,$botaxis) {
                $w create line $x $scaling($w,pymin) \
                               $x $scaling($w,pymax) \
                               -fill $colour -tag [list xtickline $w] \
                               -dash $pattern($dash)
            }
        }
    } else {
        $w delete [list ytickline && $w]
        if { $colour != {} } {
            foreach y $scaling($w,yaxis) {
                $w create line $scaling($w,pxmin) $y \
                               $scaling($w,pxmax) $y \
                               -fill $colour -tag [list ytickline $w] \
                               -dash $pattern($dash)
            }
        }
    }
    $w raise [list xaxis && $w]
    $w raise [list yaxis && $w]
    $w raise [list raxis && $w]
}

# DefaultLegend --
#    Set all legend options to default
# Arguments:
#    w              Name of the canvas
# Result:
#    None
#
proc DefaultLegend { w } {
    global legend
    global config

    set legend($w,background) $config($w,legend,background)
    set legend($w,border)     $config($w,legend,border)
    set legend($w,canvas)     $w
    set legend($w,position)   $config($w,legend,position)
    set legend($w,series)     ""
    set legend($w,text)       ""
    set legend($w,move)       0
    set legend($w,spacing)    10

    $w bind legendobj <ButtonPress-1>   [list LegendAnchor $w %x %y]
    $w bind legendobj <Motion>          [list LegendMove   $w %x %y]
    $w bind legendobj <ButtonRelease-1> [list LegendRelease $w]
}

# LegendConfigure --
#    Configure the legend
# Arguments:
#    w              Name of the canvas
#    args           Key-value pairs
# Result:
#    None
#
proc LegendConfigure { w args } {
    global legend

    foreach {option value} $args {
        switch -- $option {
            "-background" {
                 set legend($w,background) $value
            }
            "-border" {
                 set legend($w,border) $value
            }
            "-canvas" {
                 set legend($w,canvas) $value
            }
            "-position" {
                 if { [lsearch {top-left top-right bottom-left bottom-right} $value] >= 0 } {
                     set legend($w,position) $value
                 } else {
                     return -code error "Unknown or invalid position: $value"
                 }
            }
            "-font" {
                set legend($w,font) $value
            }
            "-legendtype" {
                set legend($w,legendtype) $value
            }
            "-spacing" {
                set legend($w,spacing) $value
            }
            default {
                return -code error "Unknown or invalid option: $option (value: $value)"
            }
        }
    }
}

# DrawLegend --
#    Draw or extend the legend - add the item and draw
# Arguments:
#    w              Name of the canvas
#    series         For which series?
#    text           Text to be shown
#    spacing        (Optionally) spacing between entries
# Result:
#    None
#
proc DrawLegend { w series text {spacing {}}} {
    global legend

    if { [string match r* $w] } {
        set w [string range $w 1 end]
    }

    # Append only if new item - not in list already
    if { [lsearch -exact $legend($w,series) $series] < 0 } {
        lappend legend($w,series) $series
        lappend legend($w,text)   $text
    }

    ActuallyDrawLegend $w $spacing
}

# RemoveFromLegend --
#    Remove an item from the legend and redraw it
# Arguments:
#    w              Name of the canvas
#    series         For which series?
# Result:
#    None
#
proc RemoveFromLegend { w series } {
    global legend
    global scaling

    if { [string match r* $w] } {
        set w [string range $w 1 end]
    }

    #
    # Remove item from list
    #
    set indx [lsearch -exact $legend($w,series) $series]
    set legend($w,series) [lreplace $legend($w,series) $indx $indx]
    set legend($w,text)   [lreplace $legend($w,text) $indx $indx]

    ActuallyDrawLegend $w
}

# ActuallyDrawLegend --
#    Actually draw the legend
# Arguments:
#    w              Name of the canvas
#    spacing        (Optionally) spacing between entries
# Result:
#    None
#
proc ActuallyDrawLegend { w {spacing {}}} {
    global legend
    global scaling
    global data_series

    if { [string match r* $w] } {
        set w [string range $w 1 end]
    }

    set legendw               $legend($w,canvas)

    $legendw delete "legend   && $w"
    $legendw delete "legendbg && $w"

    set y 0
    foreach series $legend($w,series) text $legend($w,text) {

        set colour "black"
        if { [info exists data_series($w,$series,-colour)] } {
            set colour $data_series($w,$series,-colour)
        }
        set type "line"
        if { [info exists data_series($w,$series,-type)] } {
            set type $data_series($w,$series,-type)
        }
        if { [info exists data_series($w,legendtype)] } {
            set type $data_series($w,legendtype)
        }
        if {[info exists legend($w,legendtype)]} {
            set type $legend($w,legendtype)
        }
        set width 1
        if { [info exists data_series($w,$series,-width)] } {
            set width $data_series($w,$series,-width)
        }
        set font TkTextFont
        if {[info exists legend($w,font)]} {
            set font $legend($w,font)
        }
        if {[info exists legend($w,spacing)] && $spacing == {}} {
            set spacing $legend($w,spacing)
        }
        #
        # Store this setting
        #
        if { $spacing != {} } {
            set legend($w,spacing) $spacing
        }

        # TODO: line or rectangle!

        if { $type != "rectangle" } {
            if { $type == "line" || $type == "both" } {
                $legendw create line 0 $y 15 $y -fill $colour -tag [list legend legendobj $w] -width $width
            }

            if { $type == "symbol" || $type == "both" } {
                set symbol "dot"
                if { [info exists data_series($w,$series,-symbol)] } {
                    set symbol $data_series($w,$series,-symbol)
                }
                DrawSymbolPixel $legendw $series 7 $y $symbol $colour [list legend legendobj legend_$series $w]
            }
        } else {
            $legendw create rectangle 0 [expr {$y-3}] 15 [expr {$y+3}] \
                -fill $colour -tag [list legend legendobj legend_$series $w]
        }

        $legendw create text 25 $y -text $text -anchor w -tag [list legend legendobj legend_$series $w] -font $font

        set y [expr {$y + $spacing}]   ;# TODO: size of font!
    }

    #
    # Now the frame and the background
    #
    foreach {xl yt xr yb} [$legendw bbox "legend && $w"] {break}

    set xl [expr {$xl-2}]
    set xr [expr {$xr+2}]
    set yt [expr {$yt-2}]
    set yb [expr {$yb+2}]

    $legendw create rectangle $xl $yt $xr $yb -fill $legend($w,background) \
        -outline $legend($w,border) -tag [list legendbg legendobj $w]

    $legendw raise legend

    if { $w == $legendw } {
        switch -- $legend($w,position) {
            "top-left" {
                 set dx [expr { 10+$scaling($w,pxmin)-$xl}]
                 set dy [expr { 10+$scaling($w,pymin)-$yt}]
            }
            "top-right" {
                 set dx [expr {-10+$scaling($w,pxmax)-$xr}]
                 set dy [expr { 10+$scaling($w,pymin)-$yt}]
            }
            "bottom-left" {
                 set dx [expr { 10+$scaling($w,pxmin)-$xl}]
                 set dy [expr {-10+$scaling($w,pymax)-$yb}]
            }
            "bottom-right" {
                 set dx [expr {-10+$scaling($w,pxmax)-$xr}]
                 set dy [expr {-10+$scaling($w,pymax)-$yb}]
            }
        }
    } else {
        set dx 10
        set dy 10
    }

    $legendw move "legend   && $w" $dx $dy
    $legendw move "legendbg && $w" $dx $dy
}

# LegendAnchor --
#    Record the coordinates of the button press -
#    for moving the legend
# Arguments:
#    w           Name of the canvas
#    x           X-coordinate
#    y           Y-coordinate
# Result:
#    None
# Side effects:
#    X and Y stored
#
proc LegendAnchor { w x y } {
    global legend

    set legend($w,move)    1
    set legend($w,xbutton) $x
    set legend($w,ybutton) $y
}

# LegendRelease --
#    Release the legend - it no longer moves
# Arguments:
#    w           Name of the canvas
# Result:
#    None
#
proc LegendRelease { w } {
    global legend

    set legend($w,move)    0
}

# LegendMove --
#    Move the legend objects
# Arguments:
#    w           Name of the canvas
#    x           X-coordinate
#    y           Y-coordinate
# Result:
#    None
# Side effects:
#    Legend moved
#
proc LegendMove { w x y } {
    global legend

    if { $legend($w,move) } {
        set dx [expr {$x - $legend($w,xbutton)}]
        set dy [expr {$y - $legend($w,ybutton)}]

        $w move legendobj $dx $dy

        set legend($w,xbutton) $x
        set legend($w,ybutton) $y
    }
}

# DrawTimeaxis --
#    Draw the date/time-axis
# Arguments:
#    w           Name of the canvas
#    tmin        Minimum date/time
#    tmax        Maximum date/time
#    tstep       Step size in days
# Result:
#    None
# Side effects:
#    Axis drawn in canvas
#
proc DrawTimeaxis { w tmin tmax tdelt } {
    global scaling
    global config

    set linecolor  $config($w,bottomaxis,color)
    set textcolor  $config($w,bottomaxis,textcolor)
    set textfont   $config($w,bottomaxis,font)
    set thickness  $config($w,bottomaxis,thickness)
    set ticklength $config($w,bottomaxis,ticklength)
    set offtick    [expr {($ticklength > 0)? $ticklength+2 : 2}]


    set scaling($w,tdelt) $tdelt

    $w delete taxis

    $w create line $scaling($w,pxmin) $scaling($w,pymax) \
                   $scaling($w,pxmax) $scaling($w,pymax) \
                   -fill $linecolor -width $thickness -tag taxis

    set format $config($w,bottomaxis,format)
    if { [info exists scaling($w,-format,x)] } {
        set format $scaling($w,-format,x)
    }

    set ttmin  [clock scan $tmin]
    set ttmax  [clock scan $tmax]
    set t      [expr {int($ttmin)}]
    set ttdelt [expr {$tdelt*86400.0}]

    set scaling($w,taxis) {}

    while { $t < $ttmax+0.5*$ttdelt } {

        foreach {xcrd ycrd} [coordsToPixel $w $t $scaling($w,ymin)] {break}
        set ycrd2 [expr {$ycrd+$ticklength}]
        set ycrd3 [expr {$ycrd+$offtick}]

        lappend scaling($w,taxis) $xcrd

        if { $format != "" } {
            set tlabel [clock format $t -format $format]
        } else {
            set tlabel [clock format $t -format "%Y-%m-%d"]
        }
        $w create line $xcrd $ycrd2 $xcrd $ycrd -tag taxis -fill $linecolor
        $w create text $xcrd $ycrd3 -text $tlabel -tag taxis -anchor n \
            -fill $textcolor -font $textfont
        set t [expr {int($t+$ttdelt)}]
    }

    set scaling($w,tdelt) $tdelt
}

# RescalePlot --
#    Partly redraw the XY plot to allow for new axes
# Arguments:
#    w           Name of the canvas
#    xscale      New minimum, maximum and step for x-axis
#    yscale      New minimum, maximum and step for y-axis
# Result:
#    None
# Side effects:
#    Axes redrawn in canvas, data scaled and moved
# Note:
#    Symbols will be scaled as well!
#
proc RescalePlot { w xscale yscale } {
    global scaling

   foreach {xmin xmax xdelt} $xscale {break}
   foreach {ymin ymax ydelt} $yscale {break}

   if { $xdelt == 0.0 || $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   if { ($xmax-$xmin)*$xdelt < 0.0 } {
      set xdelt [expr {-$xdelt}]
   }
   if { ($ymax-$ymin)*$ydelt < 0.0 } {
      set ydelt [expr {-$ydelt}]
   }

   $w delete xaxis
   $w delete yaxis

   #
   # Zoom in to the new scaling: move and scale the existing data
   #

   foreach {xb  yb}  [coordsToPixel $w  $scaling($w,xmin) $scaling($w,ymin)] {break} ;# Extreme pixels
   foreach {xe  ye}  [coordsToPixel $w  $scaling($w,xmax) $scaling($w,ymax)] {break} ;# Extreme pixels
   foreach {xnb ynb} [coordsToPixel $w  $xmin $ymin] {break} ;# Current pixels of new rectangle
   foreach {xne yne} [coordsToPixel $w  $xmax $ymax] {break}

   set fx [expr {($xe-$xb)/double($xne-$xnb)}]
   set fy [expr {($ye-$yb)/double($yne-$ynb)}]

   $w scale data $xnb $ynb $fx $fy
   $w move  data [expr {$xb-$xnb}] [expr {$yb-$ynb}]

   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   DrawYaxis        $w $ymin  $ymax  $ydelt
   DrawXaxis        $w $xmin  $xmax  $xdelt
}

# DrawRoseAxes --
#    Draw the axes to support a wind rose
# Arguments:
#    w           Name of the canvas
#    rad_max     Maximum radius
#    rad_step    Step in radius
# Result:
#    None
# Side effects:
#    Axes drawn in canvas
#
proc DrawRoseAxes { w rad_max rad_step } {

    #
    # Draw the spikes
    #
    set angle 0.0

    foreach {xcentre ycentre} [polarToPixel $w 0.0 0.0] {break}

    foreach {angle text dir} {
         90  North s
        180  West  e
        270  South n
          0  East  w } {
        foreach {xcrd ycrd} [polarToPixel $w $rad_max $angle] {break}
        foreach {xtxt ytxt} [polarToPixel $w [expr {1.05*$rad_max}] $angle] {break}
        $w create line $xcentre $ycentre $xcrd $ycrd
        $w create text $xtxt    $ytxt    -text $text -anchor $dir
    }

    #
    # Draw the concentric circles
    #
    set rad $rad_step

    while { $rad < $rad_max+0.5*$rad_step } {
        foreach {xtxt   ytxt}    [polarToPixel $w $rad   45.0] {break}
        foreach {xright ycrd}    [polarToPixel $w $rad    0.0] {break}
        foreach {xleft  ycrd}    [polarToPixel $w $rad  180.0] {break}
        foreach {xcrd   ytop}    [polarToPixel $w $rad   90.0] {break}
        foreach {xcrd   ybottom} [polarToPixel $w $rad  270.0] {break}

        $w create oval $xleft $ytop $xright $ybottom

        $w create text $xtxt [expr {$ytxt+3}] -text $rad -anchor s

        set rad [expr {$rad+$rad_step}]
    }
}


# plotbind.tcl --
#     Facilities for interaction with the plot, via event bindings
#
# Note:
#     This source contains private functions only.
#     It accompanies "plotchart.tcl"
#

# BindPlot --
#     Bind an event to the entire plot area
#
# Arguments:
#     w               Widget
#     event           Type of event
#     cmd             Command to execute
#
# Result:
#     None
#
proc BindPlot {w event cmd} {
    global scaling

    if { $scaling($w,eventobj) == "" } {

        set pxmin $scaling($w,pxmin)
        set pxmax $scaling($w,pxmax)
        set pymin $scaling($w,pymin)
        set pymax $scaling($w,pymax)

        set scaling($w,eventobj) [$w create rectangle $pxmin $pymin $pxmax $pymax -fill {} -outline {}]
    }
    $w lower $scaling($w,eventobj)

    $w bind $scaling($w,eventobj) $event [list BindCmd %x %y $w $cmd]

}

# BindLast --
#     Bind an event to the last data point of a data series
#
# Arguments:
#     w               Widget
#     series          Data series in question
#     event           Type of event
#     cmd             Command to execute
#
# Result:
#     None
#
proc BindLast {w series event cmd} {
    global data_series

    foreach {x y} [coordsToPixel $w $data_series($w,$series,x) $data_series($w,$series,y)] {break}

    set pxmin [expr {$x-5}]
    set pxmax [expr {$x+5}]
    set pymin [expr {$y-5}]
    set pymax [expr {$y+5}]

    set object [$w create rectangle $pxmin $pymin $pxmax $pymax -fill {} -outline {}]

    $w bind $object $event \
        [list BindCmd $x $y $w $cmd]
}

# BindCmd --
#     Call the command that is bound to the event
#
# Arguments:
#     xcoord          X coordinate of event
#     ycoord          Y coordinate of event
#     w               Canvas widget
#     cmd             Command to execute
#
# Result:
#     None
#
proc BindCmd {xcoord ycoord w cmd} {
    global scaling

    foreach {x y} [pixelToCoords $w $xcoord $ycoord] {break}

    eval [lindex $cmd 0] $x $y [lrange $cmd 1 end]

}

# PieExplodeSegment --
#     Move the indicated segment
#
# Arguments:
#     w               Widget
#     segment         Segment to move
#     button          Whether it came from a button event or not
#
# Result:
#     None
#
# Note:
#     If the segment is "auto", then we accept button clicks
#
proc PieExplodeSegment {w segment {button 0}} {
    global scaling

    if { $button && $scaling($w,auto) == 0 } {
        return
    }

    if { $segment == "auto" } {
        set scaling($w,auto) 1
        return
    } else {
        if { $segment < 0 || $segment >= [llength $scaling($w,angles)] } {
            return
        }
    }

    if { $scaling($w,exploded) != -1 } {
        $w move segment_$scaling($w,exploded) [expr {-$scaling($w,xexploded)}] [expr {-$scaling($w,yexploded)}]
    }

    if { $segment == $scaling($w,exploded) } {
        set scaling($w,exploded) -1
    } else {
        set angle_bgn [lindex $scaling($w,angles) $segment]
        set angle_ext [lindex $scaling($w,extent) $segment]

        set angle     [expr {3.1415926*($angle_bgn+$angle_ext/2.0)/180.0}]
        set dx        [expr { 15 * cos($angle)}]
        set dy        [expr {-15 * sin($angle)}]

        set scaling($w,exploded)  $segment
        set scaling($w,xexploded) $dx
        set scaling($w,yexploded) $dy
        $w move segment_$segment $dx $dy
    }
}

if {0} {

-- this represents an old idea. Keeping it around for the moment --

# BindVar --
#     Bind a variable to a mouse event
#
# Arguments:
#     w               Widget
#     event           Type of event
#     varname         Name of a global variable
#     text            Text containing %x and %y to set the variable to
#
# Result:
#     None
#
# Note:
#     This procedure makes it easy to build a label widget showing
#     the current position of the mouse in the plot's coordinate
#     system for instance.
#
proc BindVar {w event varname text} {

    BindCmd $w $event [list SetText $w "%x %y" $varname \
        [string map {% @} $text]]

}

# BindCmd --
#     Bind a command to a mouse event
#
# Arguments:
#     w               Widget
#     event           Type of event
#     cmd             Command to be run
#
# Result:
#     None
#
# Note:
#     This procedure makes it easy to define interactive plots
#     But it defines bindings for the whole canvas window, not the
#     individual items. -- TODO --
#
proc BindCmd {w event cmd} {
    switch -- $event {
        "mouse"  { set b "<Motion>" }
        "button" { set b "<ButtonPress-1>" }
        default  { return -code error "Unknown event type $event" }
    }

    bind $w $b $cmd
}

# SetText --
#     Substitute the coordinates in the given text
#
# Arguments:
#     w               Widget
#     coords          Current coordinates
#     varname         Name of a global variable
#     text            Text containing %x and %y to set the variable to
#
# Result:
#     None
#
# Side effects:
#     The text is assigned to the variable after making the
#     various substitutions
#
proc SetText {w coords varname text} {
    upvar #0 $varname V

    foreach {x y} [pixelToCoords $w [lindex $coords 0] [lindex $coords 1]] {break}

    set V [string map [list @x $x @y $y] $text]
}

--- end of old code ---
}


# plotbusiness.tcl --
#    Facilities aimed at business type charts
#
# Note:
#    This source file contains the private functions for various
#    business type charts.
#    It is the companion of "plotchart.tcl"
#

# Config3DBar --
#    Configuration options for the 3D barchart
# Arguments:
#    w           Name of the canvas
#    args        List of arguments
# Result:
#    None
# Side effects:
#    Items that are already visible will be changed to the new look
#
proc Config3DBar { w args } {
    global settings

    foreach {option value} $args {
        set option [string range $option 1 end]
        set settings($w,$option) $value

        switch -- $option {
            "usebackground" {
                if { $value } {
                    $w itemconfigure background -fill grey65 -outline black
                } else {
                    $w itemconfigure background -fill {} -outline {}
                }
            }
            "useticklines" {
                if { $value } {
                    $w itemconfigure ticklines -fill black
                } else {
                    $w itemconfigure ticklines -fill {}
                }
            }
            "showvalues" {
                if { $value } {
                    $w itemconfigure values -fill $settings($w,valuecolour)
                } else {
                    $w itemconfigure values -fill {}
                }
            }
            "valuecolour" - "valuecolor" {
                set settings($w,valuecolour) $value
                set settings($w,valuecolor)  $value
                $w itemconfigure values -fill $settings($w,valuecolour)
            }
            "valuefont" {
                set settings($w,valuefont) $value
                $w itemconfigure labels -font $settings($w,valuefont)
            }
            "labelcolour" - "labelcolor" {
                set settings($w,labelcolour) $value
                set settings($w,labelcolor)  $value
                $w itemconfigure labels -fill $settings($w,labelcolour)
            }
            "labelfont" {
                set settings($w,labelfont) $value
                $w itemconfigure labels -font $settings($w,labelfont)
            }
        }
    }
}

# Draw3DBarchart --
#    Draw the basic elements of the 3D barchart
# Arguments:
#    w           Name of the canvas
#    yscale      Minimum, maximum and step for the y-axis
#    nobars      Number of bars
# Result:
#    None
# Side effects:
#    Default settings are introduced
#
proc Draw3DBarchart { w yscale nobars } {
    global settings
    global scaling

    #
    # Default settings
    #
    set settings($w,labelfont)     "fixed"
    set settings($w,valuefont)     "fixed"
    set settings($w,labelcolour)   "black"
    set settings($w,valuecolour)   "black"
    set settings($w,usebackground) 0
    set settings($w,useticklines)  0
    set settings($w,showvalues)    1

    #
    # Horizontal positioning parameters
    #
    set scaling($w,xbase)    0.0
    set scaling($w,xshift)   0.2
    set scaling($w,barwidth) 0.6

    #
    # Shift the vertical axis a bit
    #
    $w move yaxis -10 0
    #
    # Draw the platform and the walls
    #
    set x1 $scaling($w,pxmin)
    set x2 $scaling($w,pxmax)
    foreach {dummy y1} [coordsToPixel $w $scaling($w,xmin) 0.0] {break}

    set x1 [expr {$x1-10}]
    set x2 [expr {$x2+10}]
    set y1 [expr {$y1+10}]

    set y2 [expr {$y1-30}]
    set x3 [expr {$x1+30}]
    set y3 [expr {$y1-30}]
    set x4 [expr {$x2-30}]
    set y4 $y1

    $w create polygon $x1 $y1 $x3 $y3 $x2 $y2 $x4 $y4 -fill gray65 -tag platform \
	-outline black

    set xw1 $x1
    foreach {dummy yw1} [coordsToPixel $w 0.0 $scaling($w,ymin)] {break}
    set xw2 $x1
    foreach {dummy yw2} [coordsToPixel $w 0.0 $scaling($w,ymax)] {break}

    set xw3 $x3
    set yw3 [expr {$yw2-30}]
    set xw4 $x3
    set yw4 [expr {$yw1-30}]

    $w create polygon $xw1 $yw1 $xw2 $yw2 $xw3 $yw3 $xw4 $yw4 \
        -outline black -fill gray65 -tag background

    set xw5 $x2
    $w create polygon $xw3 $yw3 $xw5 $yw3 $xw5 $yw4 $xw3 $yw4 \
        -outline black -fill gray65 -tag background

    #
    # Draw the ticlines (NOTE: Something is wrong here!)
    #
    #   foreach {ymin ymax ystep} $yscale {break}
    #   if { $ymin > $ymax } {
    #       foreach {ymax ymin ystep} $yscale {break}
    #       set ystep [expr {abs($ystep)}]
    #   }
    #   set yv $ymin
    #   while { $yv < ($ymax-0.5*$ystep) } {
    #       foreach {dummy pyv} [coordsToPixel $w $scaling($w,xmin) $yv] {break}
    #       set pyv1 [expr {$pyv-5}]
    #       set pyv2 [expr {$pyv-35}]
    #       $w create line $xw1 $pyv1 $xw3 $pyv2 $xw5 $pyv2 -fill black -tag ticklines
    #       set yv [expr {$yv+$ystep}]
    #   }

    Config3DBar $w -usebackground 0 -useticklines 0
}

# Draw3DBar --
#    Draw a 3D bar in a barchart
# Arguments:
#    w           Name of the canvas
#    label       Label for the bar
#    yvalue      The height of the bar
#    fill        The colour of the bar
# Result:
#    None
# Side effects:
#    The bar is drawn, the display order is adjusted
#
proc Draw3DBar { w label yvalue fill } {
    global settings
    global scaling

    set xv1 [expr {$scaling($w,xbase)+$scaling($w,xshift)}]
    set xv2 [expr {$xv1+$scaling($w,barwidth)}]

    foreach {x0 y0} [coordsToPixel $w $xv1 0.0]     {break}
    foreach {x1 y1} [coordsToPixel $w $xv2 $yvalue] {break}

    if { $yvalue < 0.0 } {
        foreach {y0 y1} [list $y1 $y0] {break}
        set tag d
    } else {
        set tag u
    }

    set d [expr {($x1-$x0)/3}]
    set x2 [expr {$x0+$d+1}]
    set x3 [expr {$x1+$d}]
    set y2 [expr {$y0-$d+1}]
    set y3 [expr {$y1-$d-1}]
    set y4 [expr {$y1-$d-1}]
    $w create rect $x0 $y0 $x1 $y1 -fill $fill -tag $tag
    $w create poly $x0 $y1 $x2 $y4 $x3 $y4 $x1 $y1 -fill [DimColour $fill 0.8] -outline black -tag u
    $w create poly $x1 $y1 $x3 $y3 $x3 $y2 $x1 $y0 -fill [DimColour $fill 0.6] -outline black -tag $tag

    #
    # Add the text
    #
    if { $settings($w,showvalues) } {
        $w create text [expr {($x0+$x3)/2}] [expr {$y3-5}] -text $yvalue \
            -font $settings($w,valuefont) -fill $settings($w,valuecolour) \
            -anchor s
    }
    $w create text [expr {($x0+$x3)/2}] [expr {$y0+8}] -text $label \
        -font $settings($w,labelfont) -fill $settings($w,labelcolour) \
        -anchor n

    #
    # Reorder the various bits
    #
    $w lower u
    $w lower platform
    $w lower d
    $w lower ticklines
    $w lower background

    #
    # Move to the next bar
    #
    set scaling($w,xbase) [expr {$scaling($w,xbase)+1.0}]
}

# DimColour --
#    Compute a dimmer colour
# Arguments:
#    color       Original colour
#    factor      Factor by which to reduce the colour
# Result:
#    New colour
# Note:
#    Shamelessly copied from R. Suchenwirths Wiki page on 3D bars
#
proc DimColour {color factor} {
    foreach i {r g b} n [winfo rgb . $color] d [winfo rgb . white] {
	#checker exclude warnVarRef
	set $i [expr {int(255.*$n/$d*$factor)}]
    }
    #checker exclude warnUndefinedVar
    format #%02x%02x%02x $r $g $b
}

# GreyColour --
#    Compute a greyer colour
# Arguments:
#    color       Original colour
#    factor      Factor by which to mix in grey
# Result:
#    New colour
# Note:
#    Shamelessly adapted from R. Suchenwirths Wiki page on 3D bars
#
proc GreyColour {color factor} {
    foreach i {r g b} n [winfo rgb . $color] d [winfo rgb . white] e [winfo rgb . lightgrey] {
	#checker exclude warnVarRef
	set $i [expr {int(255.*($n*$factor+$e*(1.0-$factor))/$d)}]
    }
    #checker exclude warnUndefinedVar
    format #%02x%02x%02x $r $g $b
}

# Draw3DLine --
#    Plot a ribbon of z-data as a function of y
# Arguments:
#    w           Name of the canvas
#    data        List of coordinate pairs y, z
#    colour      Colour to use
# Result:
#    None
# Side effect:
#    The plot of the data
#
proc Draw3DLine { w data colour } {
    global data_series
    global scaling

    set bright $colour
    set dim    [DimColour $colour 0.6]

    #
    # Draw the ribbon as a series of quadrangles
    #
    set xe $data_series($w,xbase)
    set xb [expr {$xe-$data_series($w,xwidth)}]

    set data_series($w,xbase) [expr {$xe-$data_series($w,xstep)}]

    foreach {yb zb} [lrange $data 0 end-2] {ye ze} [lrange $data 2 end] {

        foreach {px11 py11} [coords3DToPixel $w $xb $yb $zb] {break}
        foreach {px12 py12} [coords3DToPixel $w $xe $yb $zb] {break}
        foreach {px21 py21} [coords3DToPixel $w $xb $ye $ze] {break}
        foreach {px22 py22} [coords3DToPixel $w $xe $ye $ze] {break}

        #
        # Use the angle of the line to determine if the top or the
        # bottom side is visible
        #
        if { $px21 == $px11 ||
             ($py21-$py11)/($px21-$px11) < ($py12-$py11)/($px12-$px11) } {
            set colour $dim
        } else {
            set colour $bright
        }

        $w create polygon $px11 $py11 $px21 $py21 $px22 $py22 \
	    $px12 $py12 $px11 $py11 \
	    -fill $colour -outline black
    }
}

# Draw3DArea --
#    Plot a ribbon of z-data as a function of y with a "facade"
# Arguments:
#    w           Name of the canvas
#    data        List of coordinate pairs y, z
#    colour      Colour to use
# Result:
#    None
# Side effect:
#    The plot of the data
#
proc Draw3DArea { w data colour } {
    global data_series
    global scaling

    set bright $colour
    set dimmer [DimColour $colour 0.8]
    set dim    [DimColour $colour 0.6]

    #
    # Draw the ribbon as a series of quadrangles
    #
    set xe $data_series($w,xbase)
    set xb [expr {$xe-$data_series($w,xwidth)}]

    set data_series($w,xbase) [expr {$xe-$data_series($w,xstep)}]

    set facade {}

    foreach {yb zb} [lrange $data 0 end-2] {ye ze} [lrange $data 2 end] {

        foreach {px11 py11} [coords3DToPixel $w $xb $yb $zb] {break}
        foreach {px12 py12} [coords3DToPixel $w $xe $yb $zb] {break}
        foreach {px21 py21} [coords3DToPixel $w $xb $ye $ze] {break}
        foreach {px22 py22} [coords3DToPixel $w $xe $ye $ze] {break}

        $w create polygon $px11 $py11 $px21 $py21 $px22 $py22 \
	    $px12 $py12 $px11 $py11 \
	    -fill $dimmer -outline black

        lappend facade $px11 $py11
    }

    #
    # Add the last point
    #
    lappend facade $px21 $py21

    #
    # Add the polygon at the right
    #
    set zmin $scaling($w,zmin)
    foreach {px2z py2z} [coords3DToPixel $w $xe $ye $zmin] {break}
    foreach {px1z py1z} [coords3DToPixel $w $xb $ye $zmin] {break}

    $w create polygon $px21 $py21 $px22 $py22 \
	$px2z $py2z $px1z $py1z \
	-fill $dim -outline black

    foreach {pxb pyb} [coords3DToPixel $w $xb $ye $zmin] {break}

    set yb [lindex $data 0]
    foreach {pxe pye} [coords3DToPixel $w $xb $yb $zmin] {break}

    lappend facade $px21 $py21 $pxb $pyb $pxe $pye

    $w create polygon $facade -fill $colour -outline black
}


#
# plotchart.tcl --
#    Facilities to draw simple plots in a dedicated canvas
#
# Note:
#    This source file contains the public functions.
#    The private functions are contained in the files "sourced"
#    at the end.
#
package require Tcl 8.4
package require Tk

# setZoomPan --
#    Set up the bindings for zooming and panning
# Arguments:
#    w           Name of the canvas window
# Result:
#    None
# Side effect:
#    Bindings set up
#
proc setZoomPan { w } {
   set sqrt2  [expr {sqrt(2.0)}]
   set sqrt05 [expr {sqrt(0.5)}]

   bind $w <Control-Button-1> [list ScaleItems $w %x %y $sqrt2]
   bind $w <Control-Prior>    [list ScaleItems $w %x %y $sqrt2]
   bind $w <Control-Button-2> [list ScaleItems $w %x %y $sqrt05]
   bind $w <Control-Button-3> [list ScaleItems $w %x %y $sqrt05]
   bind $w <Control-Next>     [list ScaleItems $w %x %y $sqrt05]
   bind $w <Control-Up>       [list MoveItems  $w   0 -40]
   bind $w <Control-Down>     [list MoveItems  $w   0  40]
   bind $w <Control-Left>     [list MoveItems  $w -40   0]
   bind $w <Control-Right>    [list MoveItems  $w  40   0]
   focus $w
}

# viewPort --
#    Set the pixel extremes for the graph
# Arguments:
#    w           Name of the canvas window
#    pxmin       Minimum X-coordinate
#    pymin       Minimum Y-coordinate
#    pxmax       Maximum X-coordinate
#    pymax       Maximum Y-coordinate
# Result:
#    None
# Side effect:
#    Array scaling filled
#
proc viewPort { w pxmin pymin pxmax pymax } {
   global scaling

if {0} {
   # Problematic for xyplot package when zooming in!
   if { $pxmin >= $pxmax || $pymin >= $pymax } {
      return -code error "Inconsistent bounds for viewport - increase canvas size or decrease margins"
   }
}

   set scaling($w,pxmin)    $pxmin
   set scaling($w,pymin)    $pymin
   set scaling($w,pxmax)    $pxmax
   set scaling($w,pymax)    $pymax
   set scaling($w,new)      1
}

# worldCoordinates --
#    Set the extremes for the world coordinates
# Arguments:
#    w           Name of the canvas window
#    xmin        Minimum X-coordinate
#    ymin        Minimum Y-coordinate
#    xmax        Maximum X-coordinate
#    ymax        Maximum Y-coordinate
# Result:
#    None
# Side effect:
#    Array scaling filled
#
proc worldCoordinates { w xmin ymin xmax ymax } {
   global scaling

   if { $xmin == $xmax || $ymin == $ymax } {
      return -code error "Minimum and maximum must differ for world coordinates"
   }

   set scaling($w,xmin)    [expr {double($xmin)}]
   set scaling($w,ymin)    [expr {double($ymin)}]
   set scaling($w,xmax)    [expr {double($xmax)}]
   set scaling($w,ymax)    [expr {double($ymax)}]

   set scaling($w,new)     1
}

# polarCoordinates --
#    Set the extremes for the polar coordinates
# Arguments:
#    w           Name of the canvas window
#    radmax      Maximum radius
# Result:
#    None
# Side effect:
#    Array scaling filled
#
proc polarCoordinates { w radmax } {
   global scaling

   if { $radmax <= 0.0 } {
      return -code error "Maximum radius must be positive"
   }

   set scaling($w,xmin)    [expr {-double($radmax)}]
   set scaling($w,ymin)    [expr {-double($radmax)}]
   set scaling($w,xmax)    [expr {double($radmax)}]
   set scaling($w,ymax)    [expr {double($radmax)}]

   set scaling($w,new)     1
}

# world3DCoordinates --
#    Set the extremes for the world coordinates in 3D plots
# Arguments:
#    w           Name of the canvas window
#    xmin        Minimum X-coordinate
#    ymin        Minimum Y-coordinate
#    zmin        Minimum Z-coordinate
#    xmax        Maximum X-coordinate
#    ymax        Maximum Y-coordinate
#    zmax        Maximum Z-coordinate
# Result:
#    None
# Side effect:
#    Array scaling filled
#
proc world3DCoordinates { w xmin ymin zmin xmax ymax zmax } {
   global scaling

   if { $xmin == $xmax || $ymin == $ymax || $zmin == $zmax } {
      return -code error "Minimum and maximum must differ for world coordinates"
   }

   set scaling($w,xmin)    [expr {double($xmin)}]
   set scaling($w,ymin)    [expr {double($ymin)}]
   set scaling($w,zmin)    [expr {double($zmin)}]
   set scaling($w,xmax)    [expr {double($xmax)}]
   set scaling($w,ymax)    [expr {double($ymax)}]
   set scaling($w,zmax)    [expr {double($zmax)}]

   set scaling($w,new)     1
}

# coordsToPixel --
#    Convert world coordinates to pixel coordinates
# Arguments:
#    w           Name of the canvas
#    xcrd        X-coordinate
#    ycrd        Y-coordinate
# Result:
#    List of two elements, x- and y-coordinates in pixels
#
proc coordsToPixel { w xcrd ycrd } {
   global scaling
   global torad

   if { $scaling($w,new) == 1 } {
      set scaling($w,new)     0
      set width               [expr {$scaling($w,pxmax)-$scaling($w,pxmin)}]
      set height              [expr {$scaling($w,pymax)-$scaling($w,pymin)}]

      set dx                  [expr {$scaling($w,xmax)-$scaling($w,xmin)}]
      set dy                  [expr {$scaling($w,ymax)-$scaling($w,ymin)}]
      set scaling($w,xfactor) [expr {$width/$dx}]
      set scaling($w,yfactor) [expr {$height/$dy}]
   }

   if { $scaling($w,coordSystem) != 0 } {
       switch -- $scaling($w,coordSystem) {
           1 {
               # log X versus Y
               set xcrd [expr {log10($xcrd)}]
           }
           2 {
               # X versus log Y
               set ycrd [expr {log10($ycrd)}]
           }
           3 {
               # log X versus log Y
               set xcrd [expr {log10($xcrd)}]
               set ycrd [expr {log10($ycrd)}]
           }
           4 {
               # radius versus angle
               set rad  $xcrd
               set phi  [expr {$ycrd*$torad}]
               set xcrd [expr {$rad * cos($phi)}]
               set ycrd [expr {$rad * sin($phi)}]
           }
       }
   }

   set xpix [expr {$scaling($w,pxmin)+($xcrd-$scaling($w,xmin))*$scaling($w,xfactor)}]
   set ypix [expr {$scaling($w,pymin)+($scaling($w,ymax)-$ycrd)*$scaling($w,yfactor)}]
   return [list $xpix $ypix]
}

# coords3DToPixel --
#    Convert world coordinates to pixel coordinates (3D plots)
# Arguments:
#    w           Name of the canvas
#    xcrd        X-coordinate
#    ycrd        Y-coordinate
#    zcrd        Z-coordinate
# Result:
#    List of two elements, x- and y-coordinates in pixels
#
proc coords3DToPixel { w xcrd ycrd zcrd } {
   global scaling

   if { $scaling($w,new) == 1 } {
      set scaling($w,new)      0
      set width                [expr {$scaling($w,pxmax)-$scaling($w,pxmin)}]
      set height               [expr {$scaling($w,pymax)-$scaling($w,pymin)}]

      set dx                   [expr {$scaling($w,xmax)-$scaling($w,xmin)}]
      set dy                   [expr {$scaling($w,ymax)-$scaling($w,ymin)}]
      set dz                   [expr {$scaling($w,zmax)-$scaling($w,zmin)}]
      set scaling($w,xyfactor) [expr {$scaling($w,yfract)*$width/$dx}]
      set scaling($w,xzfactor) [expr {$scaling($w,zfract)*$height/$dx}]
      set scaling($w,yfactor)  [expr {$width/$dy}]
      set scaling($w,zfactor)  [expr {$height/$dz}]
   }

   #
   # The values for xcrd = xmax
   #
   set xpix [expr {$scaling($w,pxmin)+($ycrd-$scaling($w,ymin))*$scaling($w,yfactor)}]
   set ypix [expr {$scaling($w,pymin)+($scaling($w,zmax)-$zcrd)*$scaling($w,zfactor)}]

   #
   # Add the shift due to xcrd-xmax
   #
   set xpix [expr {$xpix + $scaling($w,xyfactor)*($xcrd-$scaling($w,xmax))}]
   set ypix [expr {$ypix - $scaling($w,xzfactor)*($xcrd-$scaling($w,xmax))}]

   return [list $xpix $ypix]
}

# pixelToCoords --
#    Convert pixel coordinates to world coordinates
# Arguments:
#    w           Name of the canvas
#    xpix        X-coordinate (pixel)
#    ypix        Y-coordinate (pixel)
# Result:
#    List of two elements, x- and y-coordinates in world coordinate system
#
proc pixelToCoords { w xpix ypix } {
   global scaling

   if { $scaling($w,new) == 1 } {
      set scaling($w,new)     0
      set width               [expr {$scaling($w,pxmax)-$scaling($w,pxmin)}]
      set height              [expr {$scaling($w,pymax)-$scaling($w,pymin)}]

      set dx                  [expr {$scaling($w,xmax)-$scaling($w,xmin)}]
      set dy                  [expr {$scaling($w,ymax)-$scaling($w,ymin)}]
      set scaling($w,xfactor) [expr {$width/$dx}]
      set scaling($w,yfactor) [expr {$height/$dy}]
   }

   set xcrd [expr {$scaling($w,xmin)+($xpix-$scaling($w,pxmin))/$scaling($w,xfactor)}]
   set ycrd [expr {$scaling($w,ymax)-($ypix-$scaling($w,pymin))/$scaling($w,yfactor)}]
   return [list $xcrd $ycrd]
}

# pixelToIndex --
#    Convert pixel coordinates to elements list index
# Arguments:
#    w           Name of the canvas
#    xpix        X-coordinate (pixel)
#    ypix        Y-coordinate (pixel)
# Result:
#    Elements list index
#
proc pixelToIndex { w xpix ypix } {
   global scaling
   global torad

   set idx -1
   set radius [expr {($scaling(${w},pxmax) - $scaling(${w},pxmin)) / 2}]
   set xrel [expr {${xpix} - $scaling(${w},pxmin) - ${radius}}]
   set yrel [expr {-${ypix} + $scaling(${w},pymin) + ${radius}}]
   if {[expr {pow(${radius},2) < (pow(${xrel},2) + pow(${yrel},2))}]} {
       # do nothing out of pie chart
   } elseif {[info exists scaling(${w},angles)]} {
       set xy_angle [expr {(360 + round(atan2(${yrel},${xrel})/${torad})) % 360}]
       foreach angle $scaling(${w},angles) {
       if {${xy_angle} <= ${angle}} {
           break
       }
       incr idx
       }
   }
   return ${idx}
}

# polarToPixel --
#    Convert polar coordinates to pixel coordinates
# Arguments:
#    w           Name of the canvas
#    rad         Radius of the point
#    phi         Angle of the point (degrees)
# Result:
#    List of two elements, x- and y-coordinates in pixels
#
proc polarToPixel { w rad phi } {
   global torad

   set xcrd [expr {$rad*cos($phi*$torad)}]
   set ycrd [expr {$rad*sin($phi*$torad)}]

   coordsToPixel $w $xcrd $ycrd
}

# clearcanvas --
#    Remove all data concerning this canvas
# Arguments:
#    w           Name of the canvas
# Result:
#    None
#
proc clearcanvas { w } {
   global scaling
   global config
   global data_series

   array unset scaling $w,*
   array unset config $w,*
   array unset data_series $w,*

   $w delete all
}

# createXYPlot --
#    Create a command for drawing an XY plot
# Arguments:
#    w           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (initial)
#    yscale      Minimum, maximum and step for y-axis
#    args        Options (currently: "-xlabels list" and "-ylabels list"
#                "-box list" and "-axesbox list")
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the XY plot.
#    The plot will be drawn with axes
#
proc createXYPlot { w xscale yscale args} {

    return [CreateXYPlotImpl xyplot $w $xscale $yscale $args]

}

# CreateXYPlotImpl --
#    Actually create a command for drawing an XY plot or a stripchart
# Arguments:
#    prefix      Prefix for the command
#    c           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (initial)
#    yscale      Minimum, maximum and step for y-axis
#    argv        Options (currently: "-xlabels list" and "-ylabels list")
# Result:
#    Name of a new command
#
proc CreateXYPlotImpl {prefix c xscale yscale argv} {
   global scaling
   global data_series

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "${prefix}_$w"
   interp alias {} $newchart {} PlotHandler $prefix $w
   CopyConfig $prefix $w
   set scaling($w,eventobj) ""

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $argv] {break}
   array set options $argv
   array unset options -box
   array unset options -axesbox

   set scaling($w,coordSystem) 0

   foreach {xmin xmax xdelt} $xscale {break}
   foreach {ymin ymax ydelt} $yscale {break}

   if { $xdelt == 0.0 || $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   if { $xdelt ne {} && ($xmax-$xmin)*$xdelt < 0.0 } {
      set xdelt [expr {-$xdelt}]
   }
   if { $ydelt ne {} && ($ymax-$ymin)*$ydelt < 0.0 } {
      set ydelt [expr {-$ydelt}]
   }

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   if { $xdelt eq {} } {
       foreach {arg val} [array get options] {
           switch -exact -- $arg {
               -xlabels {
                   DrawXaxis $w $xmin  $xmax  $xdelt $arg $val
               }
               -ylabels {
                   # Ignore
               }
               default {
                   error "Argument $arg not recognized"
               }
           }
       }
   } else {
       DrawXaxis   $w $xmin  $xmax  $xdelt
   }
   if { $ydelt eq {} } {
       foreach {arg val} [array get options] {
           switch -exact -- $arg {
               -ylabels {
                   DrawYaxis $w $ymin  $ymax  $ydelt $arg $val
               }
               -xlabels {
                   # Ignore
               }
               default {
                   error "Argument $arg not recognized"
               }
           }
       }
   } else {
       DrawYaxis        $w $ymin  $ymax  $ydelt
   }
   DrawMask         $w
   DefaultLegend    $w
   DefaultBalloon   $w

   $newchart dataconfig labeldot -colour red -type symbol -symbol dot

   return $newchart
}

# createStripchart --
#    Create a command for drawing a strip chart
# Arguments:
#    w           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (initial)
#    yscale      Minimum, maximum and step for y-axis
#    args        Options (currently: "-box list" and "-axesbox list")
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the stripchart.
#    The stripchart will be drawn with axes
#
proc createStripchart { w xscale yscale args } {

   return [CreateXYPlotImpl stripchart $w $xscale $yscale $args]
}

# createIsometricPlot --
#    Create a command for drawing an "isometric" plot
# Arguments:
#    c           Name of the canvas
#    xscale      Minimum and maximum for x-axis
#    yscale      Minimum and maximum for y-axis
#    stepsize    Step size for numbers on the axes or "noaxes"
#    args        Options (currently: "-box list" and "-axesbox list")
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the plot
#    The plot will be drawn with or without axes
#
proc createIsometricPlot { c xscale yscale stepsize args } {
   global scaling
   global data_series

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "isometric_$w"
   interp alias {} $newchart {} PlotHandler isometric $w
   CopyConfig isometric $w

   if { $stepsize != "noaxes" } {
      foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}
   } else {
      set pxmin 0
      set pymin 0
      #set pxmax [$w cget -width]
      #set pymax [$w cget -height]
      set pxmax [WidthCanvas $w]
      set pymax [HeightCanvas $w]
   }

   set scaling($w,coordSystem) 0

   foreach {xmin xmax xdelt} $xscale {break}
   foreach {ymin ymax ydelt} $yscale {break}

   if { $xmin == $xmax || $ymin == $ymax } {
      return -code error "Extremes for axes must be different"
   }

   viewPort         $w $pxmin $pymin $pxmax $pymax
   ScaleIsometric   $w $xmin  $ymin  $xmax  $ymax

   if { $stepsize != "noaxes" } {
      DrawYaxis        $w $ymin  $ymax  $stepsize
      DrawXaxis        $w $xmin  $xmax  $stepsize
      DrawMask         $w
   }
   DefaultLegend  $w
   DefaultBalloon $w

   return $newchart
}

# createXLogYPlot --
#    Create a command for drawing an XY plot (with a vertical logarithmic axis)
# Arguments:
#    c           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (initial)
#    yscale      Minimum, maximum and step for y-axis (step is ignored!)
#    args        Options (currently: "-box list" and "-axesbox list")
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the XY plot.
#    The plot will be drawn with axes
#
proc createXLogYPlot { c xscale yscale args } {
   global scaling
   global data_series

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "xlogyplot_$w"
   interp alias {} $newchart {} PlotHandler xlogyplot $w
   CopyConfig xlogyplot $w

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}

   set scaling($w,coordSystem) 0 ;# Temporarily only - to avoid complications with the axes

   foreach {xmin xmax xdelt} $xscale {break}
   foreach {ymin ymax ydelt} $yscale {break}

   if { $xdelt == 0.0 || $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   if { $ymin <= 0.0 || $ymax <= 0.0 } {
      return -code error "Minimum and maximum for y-axis must be positive"
   }

   #
   # TODO: reversed log plot
   #

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  [expr {log10($ymin)}]  $xmax [expr {log10($ymax)}]

   DrawLogYaxis     $w $ymin  $ymax  $ydelt
   DrawXaxis        $w $xmin  $xmax  $xdelt
   DrawMask         $w
   DefaultLegend    $w
   DefaultBalloon   $w

   set scaling($w,coordSystem) 2

   $newchart dataconfig labeldot -colour red -type symbol -symbol dot

   return $newchart
}

# createLogXYPlot --
#    Create a command for drawing an XY plot (with a horizontal logarithmic axis)
# Arguments:
#    c           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (step is ignored!)
#    yscale      Minimum, maximum and step for y-axis (initial)
#    args        Options (currently: "-box list" and "-axesbox list")
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the XY plot.
#    The plot will be drawn with axes
#
proc createLogXYPlot { c xscale yscale args } {
   global scaling
   global data_series

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "logxyplot_$w"
   interp alias {} $newchart {} PlotHandler logxyplot $w
   CopyConfig logxyplot $w

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}

   set scaling($w,coordSystem) 0 ;# Temporarily only - to avoid complications with the axes

   foreach {xmin xmax xdelt} $xscale {break}
   foreach {ymin ymax ydelt} $yscale {break}

   if { $xmin <= 0.0 || $xmax <= 0.0 } {
      return -code error "Minimum and maximum for x-axis must be positive"
   }

   if { $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   #
   # TODO: reversed log plot
   #

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w [expr {log10($xmin)}] $ymin [expr {log10($xmax)}] $ymax
   DrawYaxis        $w $ymin  $ymax  $ydelt
   DrawLogXaxis     $w $xmin  $xmax  $xdelt
   DrawMask         $w
   DefaultLegend    $w
   DefaultBalloon   $w

   set scaling($w,coordSystem) 1

   $newchart dataconfig labeldot -colour red -type symbol -symbol dot

   return $newchart
}

# createLogXLogYPlot --
#    Create a command for drawing an XY plot (with a both logarithmic axis)
# Arguments:
#    c           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (step is ignored!)
#    yscale      Minimum, maximum and step for y-axis (step is ignored!)
#    args        Options (currently: "-box list" and "-axesbox list")
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the XY plot.
#    The plot will be drawn with axes
#
proc createLogXLogYPlot { c xscale yscale args } {
   global scaling

   global data_series

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "logxlogyplot_$w"
   interp alias {} $newchart {} PlotHandler logxlogyplot $w
   CopyConfig logxlogyplot $w

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}

   set scaling($w,coordSystem) 0 ;# Temporarily only - to avoid complications with the axes

   foreach {xmin xmax xdelt} $xscale {break}
   foreach {ymin ymax ydelt} $yscale {break}

   if { $xmin <= 0.0 || $xmax <= 0.0 } {
      return -code error "Minimum and maximum for x-axis must be positive"
   }

   if { $ymin <= 0.0 || $ymax <= 0.0 } {
      return -code error "Minimum and maximum for y-axis must be positive"
   }

   #
   # TODO: reversed log plot
   #

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w [expr {log10($xmin)}] [expr {log10($ymin)}] [expr {log10($xmax)}] [expr {log10($ymax)}]
   DrawLogYaxis     $w $ymin  $ymax  $ydelt
   DrawLogXaxis     $w $xmin  $xmax  $xdelt
   DrawMask         $w
   DefaultLegend    $w
   DefaultBalloon   $w

   set scaling($w,coordSystem) 3

   $newchart dataconfig labeldot -colour red -type symbol -symbol dot

   return $newchart
}

# createHistogram --
#    Create a command for drawing a histogram
# Arguments:
#    c           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (initial)
#    yscale      Minimum, maximum and step for y-axis
#    args        Options (currently: "-box list" and "-axesbox list")
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the histogram.
#    The plot will be drawn with axes
#    This is almost the same code as for an XY plot
#
proc createHistogram { c xscale yscale args } {
   global data_series
   global scaling

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "histogram_$w"
   interp alias {} $newchart {} PlotHandler histogram $w
   CopyConfig histogram $w

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}

   set scaling($w,coordSystem) 0

   foreach {xmin xmax xdelt} $xscale {break}
   foreach {ymin ymax ydelt} $yscale {break}

   if { $xdelt == 0.0 || $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   if { ($xmax-$xmin)*$xdelt < 0.0 } {
      set xdelt [expr {-$xdelt}]
   }
   if { ($ymax-$ymin)*$ydelt < 0.0 } {
      set ydelt [expr {-$ydelt}]
   }

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   DrawYaxis        $w $ymin  $ymax  $ydelt
   DrawXaxis        $w $xmin  $xmax  $xdelt
   DrawMask         $w
   DefaultLegend    $w
   DefaultBalloon   $w

   return $newchart
}

# createPiechart --
#    Create a command for drawing a pie chart
# Arguments:
#    c           Name of the canvas
#    args        Additional arguments for placement and size of plot
#                   -box, -reference, -units
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the pie chart.
#
proc createPiechart { c args} {
   global data_series
   global scaling

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "piechart_$w"
   interp alias {} $newchart {} PlotHandler piechart $w
   CopyConfig piechart $w

   foreach {pxmin pymin pxmax pymax} [MarginsCircle $w {*}$args] {break}

   viewPort $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w -1 -1 1 1

   SetColours $w blue lightblue green yellow orange red magenta brown
   DefaultLegend  $w
   DefaultBalloon $w

   set scaling($w,auto)      0
   set scaling($w,exploded) -1

   return $newchart
}

# createSpiralPie --
#    Create a command for drawing a "spiral pie" chart
# Arguments:
#    c           Name of the canvas
#    args        Additional arguments for placement and size of plot
#                   -box, -reference, -units
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the spiral pie chart.
#
proc createSpiralPie { c args} {
   global data_series
   global scaling

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "spiralpie_$w"
   interp alias {} $newchart {} PlotHandler spiralpie $w
   CopyConfig spiralpie $w

   foreach {pxmin pymin pxmax pymax} [MarginsCircle $w {*}$args] {break}

   viewPort $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w -1 -1 1 1

   SetColours $w blue lightblue green yellow orange red magenta brown
   DefaultLegend  $w
   DefaultBalloon $w

   set scaling($w,auto)      0

   return $newchart
}

# createPolarplot --
#    Create a command for drawing a polar plot
# Arguments:
#    c             Name of the canvas
#    radius_data   Maximum radius and step
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the polar plot
#    Possible additional arguments (optional): nautical/mathematical
#    step in phi
#
proc createPolarplot { c radius_data args } {
   global scaling
   global data_series

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "polarplot_$w"
   interp alias {} $newchart {} PlotHandler polarplot $w
   CopyConfig polarplot $w

   set rad_max   [lindex $radius_data 0]
   set rad_step  [lindex $radius_data 1]

   if { $rad_step <= 0.0 } {
      return -code error "Step size can not be zero or negative"
   }
   if { $rad_max <= 0.0 } {
      return -code error "Maximum radius can not be zero or negative"
   }

   foreach {pxmin pymin pxmax pymax} [MarginsCircle $w {*}$args] {break}

   set scaling($w,coordSystem) 0

   viewPort         $w $pxmin     $pymin     $pxmax   $pymax
   polarCoordinates $w $rad_max
   DrawPolarAxes    $w $rad_max   $rad_step
   DefaultLegend    $w
   DefaultBalloon   $w

   set scaling($w,coordSystem) 4

   $newchart dataconfig labeldot -colour red -type symbol -symbol dot

   return $newchart
}

# createBarchart --
#    Create a command for drawing a barchart with vertical bars
# Arguments:
#    c           Name of the canvas
#    xlabels     List of labels for x-axis
#    yscale      Minimum, maximum and step for y-axis
#    noseries    Number of series or the keyword "stacked"
#    args        (Optional) one or more options wrt the layout
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the barchart.
#
proc createBarchart { c xlabels yscale noseries args } {
    global data_series
    global settings
    global config
    global scaling

    set w [NewPlotInCanvas $c]
    interp alias {} $w {} $c

    ClearPlot $w

    set newchart "barchart_$w"
    interp alias {} $newchart {} PlotHandler vertbars $w
    CopyConfig vertbars $w

    set settings($w,showvalues)   0
    set settings($w,valuefont)    ""
    set settings($w,valuecolour)  black
    set settings($w,valueformat)  %s

    foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}

    set scaling($w,coordSystem) 0

    if { $noseries eq "stacked" } {
        set xmin [expr {1.0 - $config($w,bar,barwidth)/2.0 - $config($w,bar,innermargin)}]
        set xmax [expr {[llength $xlabels] + $config($w,bar,barwidth)/2.0 + $config($w,bar,innermargin)}]
    } else {
        set xmin [expr {1.0 - $config($w,bar,barwidth)/2.0 - $config($w,bar,innermargin)}]
        set xmax [expr {[llength $xlabels] + $config($w,bar,barwidth)/2.0 + $config($w,bar,innermargin)}]
    }

    foreach {ymin ymax ydelt} $yscale {break}

    if { $ydelt == 0.0 } {
        return -code error "Step size can not be zero"
    }

    if { ($ymax-$ymin)*$ydelt < 0.0 } {
        set ydelt [expr {-$ydelt}]
    }

    viewPort         $w $pxmin $pymin $pxmax $pymax
    worldCoordinates $w $xmin  $ymin  $xmax  $ymax

    DrawYaxis        $w $ymin  $ymax  $ydelt
    DrawXlabels      $w $xlabels $noseries
    DrawMask         $w
    DefaultLegend    $w
    set data_series($w,legendtype) "rectangle"
    DefaultBalloon   $w

    SetColours $w blue lightblue green yellow orange red magenta brown

    return $newchart
}

# createHorizontalBarchart --
#    Create a command for drawing a barchart with horizontal bars
# Arguments:
#    c           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis
#    ylabels     List of labels for y-axis
#    noseries    Number of series or the keyword "stacked"
#    args        (Optional) one or more options wrt the layout
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the barchart.
#
proc createHorizontalBarchart { c xscale ylabels noseries args } {
    global data_series
    global config
    global settings
    global scaling

    set w [NewPlotInCanvas $c]
    interp alias {} $w {} $c

    ClearPlot $w

    set newchart "hbarchart_$w"
    interp alias {} $newchart {} PlotHandler horizbars $w
    CopyConfig horizbars $w

    set settings($w,showvalues)   0
    set settings($w,valuefont)    ""
    set settings($w,valuecolour)  black
    set settings($w,valueformat)  %s

    set font      $config($w,leftaxis,font)
    set xspacemax 0
    foreach ylabel $ylabels {
        set xspace [font measure $font $ylabel]
        if { $xspace > $xspacemax } {
            set xspacemax $xspace
        }
    }
    set config($w,margin,left) [expr {$xspacemax+5}] ;# Slightly more space required!

    foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}

    set scaling($w,coordSystem) 0

    if { $noseries eq "stacked" } {
        set ymin [expr {1.0 - $config($w,bar,barwidth)/2.0 - $config($w,bar,innermargin)}]
        set ymax [expr {[llength $ylabels] + $config($w,bar,barwidth)/2.0 + $config($w,bar,innermargin)}]
    } else {
        set ymin [expr {1.0 - $config($w,bar,barwidth)/2.0 - $config($w,bar,innermargin)}]
        set ymax [expr {[llength $ylabels] + $config($w,bar,barwidth)/2.0 + $config($w,bar,innermargin)}]
    }

    foreach {xmin xmax xdelt} $xscale {break}

    if { $xdelt == 0.0 } {
        return -code error "Step size can not be zero"
    }

    if { ($xmax-$xmin)*$xdelt < 0.0 } {
        set xdelt [expr {-$xdelt}]
    }

    viewPort         $w $pxmin $pymin $pxmax $pymax
    worldCoordinates $w $xmin  $ymin  $xmax  $ymax

    DrawXaxis        $w $xmin  $xmax  $xdelt
    DrawYlabels      $w $ylabels $noseries
    DrawMask         $w
    DefaultLegend    $w
    set data_series($w,legendtype) "rectangle"
    DefaultBalloon   $w

    SetColours $w blue lightblue green yellow orange red magenta brown

    return $newchart
}

# createBoxplot --
#    Create a command for drawing a plot with box-and-whiskers
# Arguments:
#    w           Name of the canvas
#    xdata       Minimum, maximum and step for x-axis OR list of labels for x-axis
#                (depending on the value of 'orientation')
#    ydata       Minimum, maximum and step for y-axis OR list of labels for y-axis
#    orientation 'horizontal' boxes with xscale and ylabels (the default)
#                or 'vertical' boxes with xlabels and yscale
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the boxplot.
#
proc createBoxplot { w xdata ydata {orientation horizontal}} {
   global data_series
   global config
   global settings
   global scaling

   ClearPlot $w

   set newchart "boxplot_$w"
   interp alias {} $newchart {} PlotHandler boxplot $w
   CopyConfig boxplot $w

   if {$orientation eq "horizontal"} {
      set font $config($w,leftaxis,font)
      set xspacemax 0
      foreach ylabel $ydata {
         set xspace [font measure $font $ylabel]
         if { $xspace > $xspacemax } {
             set xspacemax $xspace
         }
      }
      set config($w,margin,left) [expr {$xspacemax+5}] ;# Slightly more space required!
   } elseif {$orientation eq "vertical"} {
      # nothing here, just for completeness ...
   } else {
      return -code error "no such orientation '$orientation'. Must be 'horizontal' or 'vertical'"
   }
   set settings($w,orientation) $orientation

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w {}] {break}

   set scaling($w,coordSystem) 0

   if {$orientation eq "horizontal"} {
      set ymin [expr {1.0 - $config($w,bar,barwidth)/2.0 - $config($w,bar,innermargin)}]
      set ymax [expr {[llength $ydata] + $config($w,bar,barwidth)/2.0 + $config($w,bar,innermargin)}]
      foreach {xmin xmax xdelt} $xdata {break}
      if { $xdelt == 0.0 } {
         return -code error "Step size can not be zero"
      }
      if { ($xmax-$xmin)*$xdelt < 0.0 } {
         set xdelt [expr {-$xdelt}]
      }
   } else {
      set xmin [expr {1.0 - $config($w,bar,barwidth)/2.0 - $config($w,bar,innermargin)}]
      set xmax [expr {[llength $xdata] + $config($w,bar,barwidth)/2.0 + $config($w,bar,innermargin)}]
      foreach {ymin ymax ydelt} $ydata {break}
      if { $ydelt == 0.0 } {
         return -code error "Step size can not be zero"
      }
      if { ($ymax-$ymin)*$ydelt < 0.0 } {
         set ydelt [expr {-$ydelt}]
      }
   }

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   if {$orientation eq "horizontal"} {
      DrawXaxis        $w $xmin  $xmax  $xdelt
      DrawYlabels      $w $ydata 1
   } else {
      DrawYaxis        $w $ymin  $ymax  $ydelt
      DrawXlabels      $w $xdata 1
   }
   DrawMask         $w
   DefaultLegend    $w
   set data_series($w,legendtype) "rectangle"
   DefaultBalloon   $w

   if {$orientation eq "horizontal"} {
      set config($w,axisnames) $ydata
   } else {
      set config($w,axisnames) $xdata
   }

   return $newchart
}

# createTimechart --
#    Create a command for drawing a simple timechart
# Arguments:
#    w           Name of the canvas
#    time_begin  Start time (in the form of a date/time)
#    time_end    End time (in the form of a date/time)
#    args        Number of items to be shown (determines spacing)
#                or one or more options (-barheight pixels, -ylabelwidth pixels)
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the timechart.
#
proc createTimechart { w time_begin time_end args} {
   global data_series
   global scaling

   ClearPlot $w

   set newchart "timechart_$w"
   interp alias {} $newchart {} PlotHandler timechart $w
   CopyConfig timechart $w

   #
   # Handle the arguments
   #
   set barheight    0
   set noitems      [lindex $args 0]
   set ylabelwidth  8

   if { [string is integer -strict $noitems] } {
       set args [lrange $args 1 end]
   }
   foreach {keyword value} $args {
       switch -- $keyword {
           "-barheight" {
                set barheight $value
           }
           "-ylabelwidth" {
                set ylabelwidth [expr {$value/10.0}] ;# Pixels to characters
           }
           default {
                # Ignore
           }
       }
   }

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args 3 $ylabelwidth] {break}

   set scaling($w,coordSystem) 0

   if { $barheight != 0 } {
       set noitems [expr {($pxmax-$pxmin)/double($barheight)}]
   }
   set scaling($w,barheight) $barheight

   set ymin  0.0
   set ymax  $noitems

   set xmin  [expr {1.0*[clock scan $time_begin]}]
   set xmax  [expr {1.0*[clock scan $time_end]}]

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   set scaling($w,current) $ymax
   set scaling($w,dy)      -0.7

   DrawScrollMask $w
   set scaling($w,curpos)  0
   set scaling($w,curhpos) 0

   return $newchart
}

# createGanttchart --
#    Create a command for drawing a Gantt (planning) chart
# Arguments:
#    w           Name of the canvas
#    time_begin  Start time (in the form of a date/time)
#    time_end    End time (in the form of a date/time)
#    args        (First integer) Number of items to be shown (determines spacing)
#                (Second integer) Estimated maximum length of text (default: 20)
#                Or keyword-value pairs
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the Gantt chart.
#    Most commands taken from time charts.
#
proc createGanttchart { w time_begin time_end args} {

   global data_series
   global scaling

   ClearPlot $w

   set newchart "ganttchart_$w"
   interp alias {} $newchart {} PlotHandler ganttchart $w
   CopyConfig ganttchart $w

   #
   # Handle the arguments
   #
   set barheight    0
   set noitems      [lindex $args 0]

   if { [string is integer -strict $noitems] } {
       set args        [lrange $args 1 end]
       set ylabelwidth [lindex $args 0]
       if { [string is integer -strict $ylabelwidth] } {
           set args [lrange $args 1 end]
       } else {
           set ylabelwidth 20
       }
   } else {
       set ylabelwidth 20
   }

   foreach {keyword value} $args {
       switch -- $keyword {
           "-barheight" {
                set barheight $value
           }
           "-ylabelwidth" {
                set ylabelwidth [expr {$value/10.0}] ;# Pixels to characters
           }
           default {
                # Ignore
           }
       }
   }

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args 3 $ylabelwidth] {break}

   set scaling($w,coordSystem) 0

   if { $barheight != 0 } {
       set noitems [expr {($pxmax-$pxmin)/double($barheight)}]
   }
   set scaling($w,barheight) $barheight

   set ymin  0.0
   set ymax  $noitems

   set xmin  [expr {1.0*[clock scan $time_begin]}]
   set xmax  [expr {1.0*[clock scan $time_end]}]

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   set scaling($w,current) $ymax
   set scaling($w,dy)      -0.7

   #
   # Draw the backgrounds (both in the text part and the
   # graphical part; the text part has the "special" tag
   # "Edit" to enable a GUI to change things)
   #
   set yend 0.0
   for { set i 0 } { $i < $noitems } { incr i } {
       set ybegin $yend
       set yend   [expr {$ybegin+1.0}]
       foreach {x1 y1} [coordsToPixel $w $xmin $ybegin] {break}
       foreach {x2 y2} [coordsToPixel $w $xmax $yend  ] {break}

       if { $i%2 == 0 } {
           set tag odd
       } else {
           set tag even
       }
       $w create rectangle 0   $y1 $x1 $y2 -fill white \
           -tag {Edit vertscroll lowest} -outline white
       $w create rectangle $x1 $y1 $x2 $y2 -fill white \
           -tag [list $tag vertscroll lowest] -outline white
   }

   #
   # Default colours and fonts
   #
   GanttColor $w description black
   GanttColor $w completed   lightblue
   GanttColor $w left        white
   GanttColor $w odd         white
   GanttColor $w even        lightgrey
   GanttColor $w summary     black
   GanttColor $w summarybar  black
   GanttFont  $w description "times 10"
   GanttFont  $w summary     "times 10 bold"
   GanttFont  $w scale       "times 7"
   DefaultBalloon $w

   DrawScrollMask $w
   set scaling($w,curpos)  0
   set scaling($w,curhpos) 0

   return $newchart
}

# create3DPlot --
#    Create a simple 3D plot
# Arguments:
#    w           Name of the canvas
#    xscale      Minimum, maximum and step for x-axis (initial)
#    yscale      Minimum, maximum and step for y-axis
#    zscale      Minimum, maximum and step for z-axis
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the 3D plot
#
proc create3DPlot { w xscale yscale zscale } {
   global data_series
   global scaling

   ClearPlot $w

   set newchart "3dplot_$w"
   interp alias {} $newchart {} PlotHandler 3dplot $w
   CopyConfig 3dplot $w

   foreach {pxmin pymin pxmax pymax} [Margins3DPlot $w] {break}

   set scaling($w,coordSystem) 0

   foreach {xmin xmax xstep} $xscale {break}
   foreach {ymin ymax ystep} $yscale {break}
   foreach {zmin zmax zstep} $zscale {break}

   viewPort           $w $pxmin $pymin $pxmax $pymax
   world3DCoordinates $w $xmin  $ymin  $zmin  $xmax  $ymax $zmax

   Draw3DAxes         $w $xmin  $ymin  $zmin  $xmax  $ymax $zmax \
                         $xstep $ystep $zstep
   DefaultLegend      $w
   DefaultBalloon     $w

   SetColours $w grey black

   return $newchart
}

# create3DRibbonPlot --
#    Create a simple 3D plot that allows for ribbons
# Arguments:
#    w           Name of the canvas
#    yscale      Minimum, maximum and step for y-axis
#    zscale      Minimum, maximum and step for z-axis
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the 3D plot
#
proc create3DRibbonPlot { w yscale zscale } {
   global data_series
   global scaling

   ClearPlot $w

   set newchart "3dribbonplot_$w"
   interp alias {} $newchart {} PlotHandler 3dribbonplot $w
   CopyConfig 3dplot $w

   foreach {pxmin pymin pxmax pymax} [Margins3DPlot $w] {break}

   set scaling($w,coordSystem) 0

   foreach {xmin xmax xstep} {0.0 1.0 0.0} {break}
   foreach {ymin ymax ystep} $yscale {break}
   foreach {zmin zmax zstep} $zscale {break}

   viewPort           $w $pxmin $pymin $pxmax $pymax
   world3DCoordinates $w $xmin  $ymin  $zmin  $xmax  $ymax $zmax

   Draw3DAxes         $w $xmin  $ymin  $zmin  $xmin  $ymax $zmax \
                         $xstep $ystep $zstep
   DefaultLegend      $w
   DefaultBalloon     $w

   SetColours $w grey black

   return $newchart
}

# create3DBarchart --
#    Create a command for drawing a barchart with vertical 3D bars
# Arguments:
#    w           Name of the canvas
#    yscale      Minimum, maximum and step for y-axis
#    nobars      Number of bars to be drawn
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the barchart.
#
proc create3DBarchart { w yscale nobars } {
   global data_series
   global scaling

   ClearPlot $w

   set newchart "3dbarchart_$w"
   interp alias {} $newchart {} PlotHandler 3dbars $w
   CopyConfig 3dbars $w

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w {} 4] {break}

   set scaling($w,coordSystem) 0

   set xmin  0.0
   set xmax  [expr {$nobars + 0.1}]

   foreach {ymin ymax ydelt} $yscale {break}

   if { $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   if { ($ymax-$ymin)*$ydelt < 0.0 } {
      set ydelt [expr {-$ydelt}]
   }

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   DrawYaxis        $w $ymin  $ymax  $ydelt
  #DrawMask         $w -- none!
   Draw3DBarchart   $w $yscale $nobars
   DefaultLegend    $w
   DefaultBalloon   $w

   return $newchart
}

# createRadialchart --
#    Create a command for drawing a radial chart
# Arguments:
#    w           Name of the canvas
#    names       Names of the spokes
#    scale       Scale factor for the data
#    style       (Optional) style of the chart (lines, cumulative or filled)
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the radial chart.
#
proc createRadialchart { w names scale {style lines} } {
   global settings
   global data_series
   global scaling

   ClearPlot $w

   set newchart "radialchart_$w"
   interp alias {} $newchart {} PlotHandler radialchart $w
   CopyConfig radialchart $w

   foreach {pxmin pymin pxmax pymax} [MarginsCircle $w] {break}

   set scaling($w,coordSystem) 0

   viewPort $w $pxmin $pymin $pxmax $pymax
   $w create oval $pxmin $pymin $pxmax $pymax

   set settings($w,scale)  [expr {double($scale)}]
   set settings($w,style)  $style
   set settings($w,number) [llength $names]

   DrawRadialSpokes $w $names
   DefaultLegend  $w
   DefaultBalloon $w

   return $newchart
}

# createTXPlot --
#    Create a command for drawing a TX plot (x versus date/time)
# Arguments:
#    w           Name of the canvas
#    tscale      Minimum, maximum and step for date/time-axis (initial)
#                (values must be valid dates and the step is in days)
#    xscale      Minimum, maximum and step for vertical axis
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the TX plot.
#    The plot will be drawn with axes
#
proc createTXPlot { w tscale xscale } {
   global data_series
   global scaling

   ClearPlot $w

   set newchart "txplot_$w"
   interp alias {} $newchart {} PlotHandler txplot $w
   CopyConfig txplot $w

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w {}] {break}

   set scaling($w,coordSystem) 0

   foreach {tmin tmax tdelt} $tscale {break}

   set xmin  [clock scan $tmin]
   set xmax  [clock scan $tmax]
   set xdelt [expr {86400*$tdelt}]

   foreach {ymin ymax ydelt} $xscale {break}

   if { $xdelt == 0.0 || $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   if { ($xmax-$xmin)*$xdelt < 0.0 } {
      set xdelt [expr {-$xdelt}]
   }
   if { ($ymax-$ymin)*$ydelt < 0.0 } {
      set ydelt [expr {-$ydelt}]
   }

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   DrawYaxis        $w $ymin  $ymax  $ydelt
   DrawTimeaxis     $w $tmin  $tmax  $tdelt
   DrawMask         $w
   DefaultLegend    $w
   DefaultBalloon   $w

   return $newchart
}

# createRightAxis --
#    Create a command for drawing a plot with a right axis
# Arguments:
#    w           Name of the canvas
#    yscale      Minimum, maximum and step for vertical axis
#    args        Options (for now: -ylabels)
# Result:
#    Name of a new command
# Note:
#    This command requires that another plot command has been
#    created prior to this one. Some of the properties from that
#    command serve for this one too.
#
proc createRightAxis { w yscale args } {
   global data_series
   global scaling
   global config

   if { [string match ".*" $w] } {
       set w "00$w"
   }
   if { [regexp {[a-z]+_([0-9][0-9]\..*)} $w ==> wc] } {
       set w $wc
   }

   set newchart "right_$w"

   #
   # Check if there is an appropriate plot already defined - there
   # should be only one!
   #
   if { [llength [info command "*_$w" ]] == 0 } {
       return -code error "There should be a plot with a left axis already defined"
   }
   if { [llength [info command "*_$w" ]] >= 2 } {
       if { [llength [info command "right_$w"]] == 0 } {
           return -code error "There should be only one plot command for this widget ($w)"
       } else {
           catch {
               interp alias {} $newchart {}
           }
       }
   }

   foreach s [array names data_series "r$w,*"] {
      unset data_series($s)
   }

   set type [lindex [interp alias {} [info command "*_$w"]] 1]

   interp alias {} $newchart {} PlotHandler $type r$w
   interp alias {} r$w       {} $w
   CopyConfig $type r$w

   set config(r$w,font,char_width)  $config($w,font,char_width)
   set config(r$w,font,char_height) $config($w,font,char_height)

   set xmin $scaling($w,xmin)
   set xmax $scaling($w,xmax)

   set pxmin $scaling($w,pxmin)
   set pxmax $scaling($w,pxmax)
   set pymin $scaling($w,pymin)
   set pymax $scaling($w,pymax)

   foreach {ymin ymax ydelt} $yscale {break}

   set scaling(r$w,coordSystem) 0
   set scaling(r$w,reference)   $scaling($w,reference)

   if { $ydelt == 0.0 } {
      return -code error "Step size can not be zero"
   }

   if { $ydelt ne {} && ($ymax-$ymin)*$ydelt < 0.0 } {
      set ydelt [expr {-$ydelt}]
   }

   viewPort         r$w $pxmin $pymin $pxmax $pymax
   worldCoordinates r$w $xmin  $ymin  $xmax  $ymax

   if { $ydelt eq {} } {
       foreach {arg val} $args {
           switch -exact -- $arg {
               -ylabels {
                   DrawRightaxis r$w $ymin  $ymax  $ydelt $arg $val
               }
               -xlabels {
                   # Ignore
               }
               default {
                   error "Argument $arg not recognized"
               }
           }
       }
   } else {
       DrawRightaxis r$w $ymin $ymax $ydelt
   }

   #DefaultLegend    r$w
   #DefaultBalloon   r$w

   return $newchart
}

# create3DRibbonChart --
#    Create a chart that can display 3D lines and areas
# Arguments:
#    w           Name of the canvas
#    names       Labels along the x-axis
#    yscale      Minimum, maximum and step for y-axis
#    zscale      Minimum, maximum and step for z-axis
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the 3D chart
#
proc create3DRibbonChart { w names yscale zscale } {
   global data_series
   global scaling

   ClearPlot $w

   set newchart "3dribbon_$w"
   interp alias {} $newchart {} PlotHandler 3dribbon $w
   CopyConfig 3dribbon $w

   foreach {pxmin pymin pxmax pymax} [Margins3DPlot $w] {break}

   set scaling($w,coordSystem) 0

   foreach {xmin xmax xstep} {0.0 1.0 0.0} {break}
   foreach {ymin ymax ystep} $yscale {break}
   foreach {zmin zmax zstep} $zscale {break}

   set xstep [expr {1.0/[llength $names]}]
   set data_series($w,xbase)  [expr {1.0-0.15*$xstep}]
   set data_series($w,xstep)  $xstep
   set data_series($w,xwidth) [expr {0.7*$xstep}]

   viewPort           $w $pxmin $pymin $pxmax $pymax
   world3DCoordinates $w $xmin  $ymin  $zmin  $xmax  $ymax $zmax

   Draw3DAxes         $w $xmin  $ymin  $zmin  $xmax  $ymax $zmax \
                         $xstep $ystep $zstep $names
   DefaultLegend      $w
   DefaultBalloon     $w

   SetColours $w grey black

   return $newchart
}

# createWindRose --
#     Create a new command for plotting a windrose
#
# Arguments:
#    w             Name of the canvas
#    radius_data   Maximum radius and step
#    sectors       Number of sectors (default: 16)
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the windrose
#    Possible additional arguments (optional): nautical/mathematical
#    step in phi
#
proc createWindRose { w radius_data {sectors 16}} {
    global data_series
    global scaling

    ClearPlot $w

    set newchart "windrose_$w"
    interp alias {} $newchart {} PlotHandler windrose $w
    CopyConfig windrose $w

    set rad_max   [lindex $radius_data 0]
    set rad_step  [lindex $radius_data 1]

    if { $rad_step <= 0.0 } {
        return -code error "Step size can not be zero or negative"
    }
    if { $rad_max <= 0.0 } {
        return -code error "Maximum radius can not be zero or negative"
    }

    foreach {pxmin pymin pxmax pymax} [MarginsCircle $w] {break}

    set scaling($w,coordSystem) 0

    viewPort         $w $pxmin     $pymin     $pxmax   $pymax
    polarCoordinates $w $rad_max
    DrawRoseAxes     $w $rad_max   $rad_step


    set data_series($w,radius) {}
    for { set i 0 } { $i < $sectors } { incr i } {
        lappend data_series($w,cumulative_radius) 0.0
    }

    set data_series($w,start_angle)     [expr {90.0 - 360.0/(4.0*$sectors)}]
    set data_series($w,d_angle)         [expr {360.0/(2.0*$sectors)}]
    set data_series($w,increment_angle) [expr {360.0/$sectors}]
    set data_series($w,count_data)      0


    return $newchart
}

# createTargetDiagram --
#    Create a command for drawing a target diagram
# Arguments:
#    w           Name of the canvas
#    bounds      List of radii to indicate bounds for the skill
#    scale       Scale of the axes - defaults to 1
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the XY plot.
#    The plot will be drawn with axes
#
proc createTargetDiagram { w bounds {scale 1.0}} {
    global scaling
    global data_series
    global config

    ClearPlot $w

    set newchart "targetdiagram_$w"
    interp alias {} $newchart {} PlotHandler targetdiagram $w
    CopyConfig targetdiagram $w

    foreach {pxmin pymin pxmax pymax} [MarginsSquare $w] {break}

    set scaling($w,coordSystem) 0

    set extremes [determineScale [expr {-$scale}] $scale]
    foreach {xmin xmax xdelt} $extremes {break}
    foreach {ymin ymax ydelt} $extremes {break}

    if { $xdelt == 0.0 || $ydelt == 0.0 } {
        return -code error "Step size can not be zero"
    }

    if { $xdelt ne {} && ($xmax-$xmin)*$xdelt < 0.0 } {
        set xdelt [expr {-$xdelt}]
    }
    if { ($ymax-$ymin)*$ydelt < 0.0 } {
        set ydelt [expr {-$ydelt}]
    }

    viewPort         $w $pxmin $pymin $pxmax $pymax
    worldCoordinates $w $xmin  $ymin  $xmax  $ymax

    DrawYaxis        $w $ymin  $ymax  $ydelt
    DrawXaxis        $w $xmin  $xmax  $xdelt

    DrawMask         $w
    DefaultLegend    $w
    DefaultBalloon   $w

    foreach {pxcent pycent} [coordsToPixel $w 0.0 0.0] {break}

    $w create line $pxmin  $pycent $pxmax  $pycent -fill $config($w,limits,color) -tag limits
    $w create line $pxcent $pymin  $pxcent $pymax  -fill $config($w,limits,color) -tag limits

    foreach r $bounds {
        foreach {pxmin pymin} [coordsToPixel $w [expr {-$r}] [expr {-$r}]] {break}
        foreach {pxmax pymax} [coordsToPixel $w $r $r] {break}

        $w create oval $pxmin $pymin $pxmax $pymax -outline $config($w,limits,color) -tag limits
    }


    return $newchart
}

# createPerformanceProfile --
#    Create a command for drawing a performance profile
# Arguments:
#    w           Name of the canvas
#    scale       Maximum value for the x-axis
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the XY plot.
#    The plot will be drawn with axes
#
proc createPerformanceProfile { w scale } {
   global scaling
   global data_series

   ClearPlot $w

   set newchart "performance_$w"
   interp alias {} $newchart {} PlotHandler performance $w
   CopyConfig performance $w
   set scaling($w,eventobj) ""

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w {}] {break}

   set scaling($w,coordSystem) 0

   foreach {xmin xmax xdelt} [determineScale 1.0 $scale] {break}
   foreach {ymin ymax ydelt} {0.0 1.1 0.25} {break}

   viewPort         $w $pxmin $pymin $pxmax $pymax
   worldCoordinates $w $xmin  $ymin  $xmax  $ymax

   DrawYaxis        $w $ymin  $ymax  $ydelt
   DrawXaxis        $w $xmin  $xmax  $xdelt

   DrawMask         $w
   DefaultLegend    $w
   LegendConfigure  $w -position bottom-right
   DefaultBalloon   $w


   return $newchart
}

# createTableChart --
#    Create a command for drawing a table
# Arguments:
#    c           Name of the canvas
#    columns     Names of the columns to be displayed
#    args        Optional list of column widths and/or -box list
#                to position the table
# Result:
#    Name of a new command
# Note:
#    By default the entire canvas will be dedicated to the table
#
proc createTableChart { c columns args } {
   global scaling
   global data_series

   set w [NewPlotInCanvas $c]
   interp alias {} $w {} $c

   ClearPlot $w

   set newchart "table_$w"
   interp alias {} $newchart {} PlotHandler table $w
   CopyConfig table $w

   if { [llength $args] == 0 } {
       set widths {}
   } elseif { [string index [lindex $args 0] 0] != "-" } {
       set widths [lindex $args 0]
       set args   [lrange $args 1 end]
   } else {
       set widths {}
   }

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w $args] {break}

   set scaling($w,coordSystem) 0

   set scaling($w,leftside)  {}
   set scaling($w,rightside) {}
   set scaling($w,pymin)     $pymin

   set left $pxmin

   if { [llength $widths] <= 1 } {
       if { [llength $widths] == 0 } {
           set column_width [expr {($pxmax-$pxmin)/[llength $columns]}]
       } else {
           set column_width $widths
       }
       foreach c $columns {
           lappend scaling($w,leftside) $left
           set right [expr {$left + $column_width}]
           lappend scaling($w,rightside) $right
           set left  [expr {$left + $column_width}]
       }
   } else {
       if { [llength $widths] < [llength $columns] } {
           return -code error "Number of widths should be at least the number of columns"
       }

       foreach width $widths {
           lappend scaling($w,leftside) $left
           set right [expr {$left + $width}]
           lappend scaling($w,rightside) $right
           set left  [expr {$left + $width}]
       }
   }

   set scaling($w,formatcommand) DefaultFormat
   set scaling($w,topside)       $pymin
   set scaling($w,toptable)      $pymin
   set scaling($w,row)           0

   set scaling($w,cell,-background) ""
   set scaling($w,cell,-color)      black

   DrawTableFrame $w
   DrawRow        $w $columns header

   return $newchart
}

# createTitleBar --
#    Create a command for drawing a title over the full width of the canvas
# Arguments:
#    w           Name of the canvas
#    height      Height of the title bar
# Result:
#    Name of a new command
#
proc createTitleBar { w height } {
   global scaling
   global data_series

   ClearPlot $w

   set newchart "title_$w"
   interp alias {} $newchart {} PlotHandler title $w
   CopyConfig title $w

   foreach {pxmin pymin pxmax pymax} [MarginsRectangle $w {}] {break}

   # TODO!

   return $newchart
}


# plotconfig.tcl --
#     Facilities for configuring the various procedures of Plotchart
#


# plotstyle --
#     Plotting style mechanism (this proc needs to be first in this file, since
#                               the namespace eval uses this proc)
#
# Arguments:
#     cmd         subcommand to the plotstyle command
#                 Can be configure|current|load|merge|names ('merge' not implemented yet)
#     stylename   symbolic name of the style (defaults to 'default')
#     args        additional optional arguments (only used in 'configure' subcommand)
#
# Result:
#     The name of the current style (for subcommand 'current'),
#     a list of available styles (for subcommand 'names'),
#     else the empty string
#
# Side effects:
#     Styles are created, loaded, or modified
#
proc plotstyle {cmd {stylename default} args} {
    global style
    global config

    switch $cmd {
        configure {
            #
            # 'plotstyle configure stylename type component property value ?type component property value ...?'
            #
            # register the 'default' style:
            set newStyle false
            if { [lsearch -exact $config(styles) $stylename] < 0 } {
                # this is a new style -> register it:
                lappend config(styles) $stylename
                set newStyle true
            }
            foreach {type component property value} $args {
                set style($stylename,$type,$component,$property) $value
                if { $newStyle } {
                    # also save the item as default, so it can be restored via plotconfig:
                    set style($stylename,$type,$component,$property,default) $value
                }
            }
            if { $config(currentstyle) eq $stylename } {
                # load the modified style items:
                foreach {type component property value} $args {
                    set config($type,$component,$property) $value
                }
            }
        }
        current {
            #
            # 'plotstyle current'
            #
            return $config(currentstyle)
        }
        load {
            #
            # 'plotstyle load stylename'
            #
            if { [lsearch -exact $config(styles) $stylename] < 0 } {
                return -code error "no such plotting style '$stylename'"
            }
            foreach {item value} [array get style $stylename,*] {
                set item [string map [list $stylename, {}] $item]
                set config($item) $value
            }
            set config(currentstyle) $stylename
        }
        merge {
            #
            # 'plotstyle merge stylename otherstylename pattern ?otherstylename pattern ...?'
            #

        }
        names {
            #
            # 'plotstyle names'
            #
            return $config(styles)
        }
    }
}

    # FontMetrics --
    #     Determine the font metrics
    #
    # Arguments:
    #     w         Canvas to be used
    #
    # Result:
    #     List of character width and height
    #
    proc FontMetrics {w} {
        set item        [$w create text 0 0 -text "M"]
        set bbox        [$w bbox $item]
        set char_width  [expr {[lindex $bbox 2] - [lindex $bbox 0]}]
        set char_height [expr {[lindex $bbox 3] - [lindex $bbox 1]}]
        if { $char_width  <  8 } { set char_width   8 }
        if { $char_height < 14 } { set char_height 14 }
        $w delete $item

        return [list $char_width $char_height]
    }

    #
    # List of styles
    #
    set config(styles) [list]

    #
    # The currently selected style
    #
    set config(currentstyle) {}

    #
    # Define implemented chart types
    #
    set config(charttypes) {
        xyplot xlogyplot logxyplot logxlogyplot
        piechart spiralpie polarplot
        histogram horizbars vertbars ganttchart
        timechart stripchart isometric 3dplot 3dbars
        radialchart txplot 3dribbon boxplot windrose
        targetdiagram performance table
    }

    # define implemented components for each chart type:
    foreach {type components} {
        xyplot        {title margin text legend leftaxis rightaxis bottomaxis background mask}
        xlogyplot     {title margin text legend leftaxis           bottomaxis background mask}
        logxyplot     {title margin text legend leftaxis           bottomaxis background mask}
        logxlogyplot  {title margin text legend leftaxis           bottomaxis background mask}
        piechart      {title margin text legend                               background      labels slice}
        spiralpie     {title margin text legend                               background      labels slice}
        polarplot     {title margin text legend axis                          background}
        histogram     {title margin text legend leftaxis rightaxis bottomaxis background mask}
        horizbars     {title margin text legend leftaxis           bottomaxis background mask bar object}
        vertbars      {title margin text legend leftaxis           bottomaxis background mask bar}
        ganttchart    {title margin text legend axis                          background}
        timechart     {title margin text legend leftaxis           bottomaxis background}
        stripchart    {title margin text legend leftaxis           bottomaxis background mask}
        isometric     {title margin text legend leftaxis           bottomaxis background mask}
        3dplot        {title margin text legend xaxis yaxis zaxis             background}
        3dbars        {title margin text legend leftaxis           bottomaxis background}
        radialchart   {title margin text legend leftaxis           bottomaxis background}
        txplot        {title margin text legend leftaxis rightaxis bottomaxis background mask}
        3dribbon      {title margin text legend leftaxis           bottomaxis background}
        boxplot       {title margin text legend leftaxis           bottomaxis background mask bar}
        windrose      {title margin text legend axis                          background}
        targetdiagram {title margin text legend leftaxis           bottomaxis background mask limits}
        performance   {title margin text legend leftaxis           bottomaxis background mask limits}
        table         {title margin background header oddrow evenrow cell frame}
    } {
        set config($type,components) $components
    }

    # define implemented properties for each component:
    # (the '-' means that the component inherits the properties of the previous component on the list)
    foreach {component properties} {
        leftaxis   {color thickness font format ticklength textcolor labeloffset minorticks shownumbers showaxle render vtextoffset}
        axis       {color thickness font format ticklength textcolor labeloffset minorticks shownumbers showaxle render}
        rightaxis  -
        topaxis    -
        bottomaxis -
        xaxis      -
        yaxis      -
        zaxis      -
        margin     {left right top bottom}
        title      {textcolor font anchor background}
        text        -
        labels     {textcolor font placement sorted shownumbers format formatright}
        background {outercolor innercolor}
        legend     {background border position}
        limits     {color}
        bar        {barwidth innermargin outline}
        mask       {draw}
        header     {background font color height anchor}
        oddrow     {background font color height anchor}
        evenrow    {background font color height anchor}
        cell       {background font color anchor leftspace rightspace topspace}
        frame      {color outerwidth innerwidth}
        slice      {outlinewidth outline startangle direction}
        object     {transposecoordinates}
    } {
        if { $properties eq "-" } {
            set properties $lastProperties
        }
        set config($component,properties) $properties
        set lastProperties $properties
    }

    # get some font properties:
    canvas .invisibleCanvas
    set invisibleLabel [.invisibleCanvas create text 0 0 -text "M"]

    foreach {char_width char_height} [FontMetrics .invisibleCanvas] {break}
    set config(font,char_width)  $char_width
    set config(font,char_height) $char_height

    # values for the 'default' style:
    set _color       "black"
    set _font        [.invisibleCanvas itemcget $invisibleLabel -font]
    set _thickness   1
    set _format      ""
    set _ticklength  3
    set _minorticks  0
    set _textcolor   "black"
    set _anchor      n
    set _labeloffset 2
    set _left        [expr {$char_width  * 8}]
    set _right       [expr {$char_width  * 4}]
    set _top         [expr {$char_height * 2}]
    set _bottom      [expr {$char_height * 2 + 2}]
    set _bgcolor     "white"
    set _outercolor  "white"
    set _innercolor  "white"  ;# Not implemented yet: "$w lower data" gets in the way
    set _background  "white"
    set _border      "black"
    set _position    "top-right"
    set _barwidth    0.8
    set _innermargin 0.2
    set _outline     black
    set _outlinewidth 1
    set _vtextoffset 2
    set _draw        1
    set _shownumbers 1
    set _showaxle    1
    set _leftspace   5
    set _rightspace  5
    set _topspace    5
    set _height      [expr {$char_height + 2*$_topspace}]
    set _anchor      center
    set _outerwidth  2
    set _innerwidth  1
    set _startangle  0
    set _direction   +
    set _placement   out    ;# piechart label placement: 'out' or 'in'
    set _render      simple ;# rendering of text: 'simple' or 'text'
    set _sorted      0      ;# piechart and spiral pie
   #set _shownumbers 0      ;# piechart and spiral pie      - conflict with axes - see below
   #set _format      "%s (%g)"  ;# piechart and spiral pie
    set _formatright ""         ;# piechart and spiral pie
    set _transposecoordinates 0 ;# horizontal barchart


    destroy .invisibleCanvas

    #
    # Define the 'default' style
    #
    foreach type $config(charttypes) {
        foreach component $config($type,components) {
            foreach property $config($component,properties) {
                plotstyle configure "default" $type $component $property [set _$property]
            }
        }
        #
        # Default colour for title bar: same as outercolour
        #
        plotstyle configure "default" $type title background ""
    }
    #
    # Specific defaults
    #
    plotstyle configure "default" targetdiagram limits color "gray"
    plotstyle configure "default" table margin left 30 right 30
    plotstyle configure "default" piechart  labels shownumbers 0
    plotstyle configure "default" piechart  labels format      "%s (%g)"
    plotstyle configure "default" spiralpie labels shownumbers 0
    plotstyle configure "default" spiralpie labels format      "%s (%g)"
    plotstyle configure "default" polarplot axis   color       "gray"

    #
    # load the style
    #
    plotstyle load default

# plotconfig --
#     Set or query general configuration options of Plotchart
#
# Arguments:
#     charttype         Type of plot or chart or empty (optional)
#     component         Component of the type of plot or chart or empty (optional)
#     property          Property of the component or empty (optional)
#     value             New value of the property if given (optional)
#                       (if "default", default is restored)
#
# Result:
#     No arguments: list of supported chart types
#     Only chart type given: list of components for that type
#     Chart type and component given: list of properties for that component
#     Chart type, component and property given: current value
#     If a new value is given, nothing
#
# Note:
#     The command contains a lot of functionality, but its structure is
#     fairly simple. No property has an empty string as a sensible value.
#
proc plotconfig {{charttype {}} {component {}} {property {}} args} {
    global config
    global style

    if { $charttype == {} } {
        return $config(charttypes)
    } else {
        if { [lsearch $config(charttypes) $charttype] < 0 } {
            return -code error "Unknown chart type - $charttype"
        }
    }

    if { $component == {} } {
        return $config($charttype,components)
    } else {
        if { [lsearch $config($charttype,components) $component] < 0 } {
            return -code error "Unknown component '$component' for this chart type - $charttype"
        }
    }

    if { $property == {} } {
        return $config($component,properties)
    } else {
        if { [lsearch $config($component,properties) $property] < 0 } {
            return -code error "Unknown property '$property' for this component '$component' (chart: $charttype)"
        }
    }

    if { $args eq {} } {
        return $config($charttype,$component,$property)
    } else {
        set args [linsert $args 0 $property]
        foreach {property value} $args {
            if { $value == "default" } {
                set config($charttype,$component,$property) \
                $style($config(currentstyle),$charttype,$component,$property)
            } else {
                if { $value == "none" } {
                    set value ""
                }
                set config($charttype,$component,$property) $value
            }
        }
    }
}

# CopyConfig --
#     Copy the configuration options to a particular plot/chart
#
# Arguments:
#     charttype         Type of plot or chart
#     chart             Widget of the actual chart
#
# Result:
#     None
#
# Side effects:
#     The configuration options are available for the particular plot or
#     chart and can be modified specifically for that plot or chart.
#
proc CopyConfig {charttype chart} {
    global config

    foreach {prop value} [array get config $charttype,*] {
        set chprop [string map [list $charttype, $chart,] $prop]
        set config($chprop) $value
    }
}

# plotmethod --
#     Register a new plotting method
#
# Arguments:
#     charttype         Type of plot or chart
#     methodname        Name of the method
#     plotproc          Plotting procedure that implements the method
#
# Result:
#     None
#
# Side effects:
#     Registers the plotting procedure under the method name,
#     so that for that type of plot/chart you can now use:
#
#         $p methodname ...
#
#     and the plotting procedure is invoked.
#
#     The plotting procedure must have the following interface:
#
#         proc plotproc {plot widget ...} {...}
#
#     The first argument is the identification of the plot
#     (the $p in the above example), the second is the name
#     of the widget. This way you can use canvas subcommands
#     via $widget and Plotchart's existing commands via $plot.
#
proc plotmethod {charttype methodname plotproc} {

    global methodProc

    set fullname [uplevel 1 [list namespace which $plotproc]]

    if { $fullname != "" } {
        set methodProc($charttype,$methodname) [list $fullname $charttype]
    } else {
        return -code error "No such command or procedure: $plotproc"
    }
}


# plotcontour.tcl --
#     Contour plotting test program for the Plotchart package
#
#  Author: Mark Stucky
#
#  The basic idea behind the method used for contouring within this sample
#  is primarily based on :
#
#    (1) "Contour Plots of Large Data Sets" by Chris Johnston
#        Computer Language, May 1986
#
#  a somewhat similar method was also described in
#
#    (2) "A Contouring Subroutine" by Paul D. Bourke
#        BYTE, June 1987
#        http://astronomy.swin.edu.au/~pbourke/projection/conrec/
#
#  In (1) it is assumed that you have a N x M grid of data that you need
#  to process.  In order to generate a contour, each cell of the grid
#  is handled without regard to it's neighbors.  This is unlike many other
#  contouring algorithms that follow the current contour line into
#  neighboring cells in an attempt to produce "smoother" contours.
#
#  In general the method described is:
#
#     1) for each four cornered cell of the grid,
#        calculate the center of the cell (average of the four corners)
#
#           data(i  ,j)   : Point (1)
#           data(i+1,j)   : Point (2)
#           data(i+1,j+1) : Point (3)
#           data(i  ,j+1) : Point (4)
#           center        : Point (5)
#
#               (4)-------------(3)
#                | \           / |
#                |  \         /  |
#                |   \       /   |
#                |    \     /    |
#                |     \   /     |
#                |      (5)      |
#                |     /   \     |
#                |    /     \    |
#                |   /       \   |
#           ^    |  /         \  |
#           |    | /           \ |
#           J   (1)-------------(2)
#
#                I ->
#
#        This divides the cell into four triangles.
#
#     2) Each of the five points in the cell can be assigned a sign (+ or -)
#        depending upon whether the point is above (+) the current contour
#        or below (-).
#
#        A contour will cross an edge whenever the points on the boundary of
#        the edge are of an opposite sign.
#
#        A few examples :
#
#           (-)     (-)        (-)  |  (+)       (-)     (-)        (+)  |  (-)
#                                    \                _                   \
#                                     \              /  \                  \
#               (-)  -             (-) |          _ /(+) |           -  (+)  -
#                  /                  /                 /              \
#                 /                 /                  /                \
#           (-)  |  (+)        (-)  |  (+)       (+)  |  (-)        (-)  |  (+)
#
#
#        (Hopefully the "rough" character diagrams above give you the
#        general idea)
#
#        It turns out that there are 32 possibles combinations of + and -
#        and therefore 32 basic paths through the cell.  And if you swap
#        the (+) and (-) in the diagram above, the "same" basic path is
#        generated:
#
#           (+)     (+)        (+)  |  (-)       (+)     (+)        (-)  |  (+)
#                                    \                _                   \
#                                     \              /  \                  \
#               (+)  -             (+) |          _ /(-) |           -  (-)  -
#                  /                  /                 /              \
#                 /                 /                  /                \
#           (+)  |  (-)        (+)  |  (-)       (-)  |  (+)        (+)  |  (-)
#
#
#        So, it turns out that there are 16 basic paths through the cell.
#
###############################################################################
#
#  The original article/code worked on all four triangles together and
#  generated one of the 16 paths.
#
#  For this version of the code, I split the cell into the four triangles
#  and handle each triangle individually.
#
#  Doing it this way is slower than the above method for calculating the
#  contour lines.  But since it "simplifies" the code when doing "color filled"
#  contours, I opted for the longer calculation times.
#
#
# AM:
# Introduce the following methods in createXYPlot:
# - grid            Draw the grid (x,y needed)
# - contourlines    Draw isolines (x,y,z needed)
# - contourfill     Draw shades (x,y,z needed)
# - contourbox      Draw uniformly coloured cells (x,y,z needed)
#
# This needs still to be done:
# - colourmap       Set colours to be used (possibly interpolated)
#
# Note:
# To get the RGB values of a named colour:
# winfo rgb . color (divide by 256)
#
# The problem:
# What interface do we use?
#
# Changes:
# - Capitalised several proc names (to indicate they are private to
#   the Plotchart package)
# - Changed the data structure from an array to a list of lists.
#   This means:
#   - No confusion about the start of indices
#   - Lists can be passed as ordinary arguments
#   - In principle they are faster, but that does not really
#     matter here
# To do:
# - Absorb all global arrays into the Plotchart system of private data
# - Get rid of the bug in the shades algorithm ;)
#

# DrawGrid --
#     Draw the grid as contained in the lists of coordinates
# Arguments:
#     w           Canvas to draw in
#     x           X-coordinates of grid points (list of lists)
#     y           Y-coordinates of grid points (list of lists)
# Result:
#     None
# Side effect:
#     Grid drawn as lines between the vertices
# Note:
#     STILL TO DO
#     A cell is only drawn if there are four well-defined
#     corners. If the x or y coordinate is missing, the cell is
#     skipped.
#
proc DrawGrid {w x y} {

    set maxrow [llength $x]
    set maxcol [llength [lindex $x 0]]

    for {set i 0} {$i < $maxrow} {incr i} {
        set xylist {}
        for {set j 0} {$j < $maxcol} {incr j} {
            lappend xylist [lindex $x $i $j] [lindex $y $i $j]
        }
        C_line $w $xylist black
    }

    for {set j 0} {$j < $maxcol} {incr j} {
        set xylist {}
        for {set i 0} {$i < $maxrow} {incr i} {
            lappend xylist [lindex $x $i $j] [lindex $y $i $j]
        }
        C_line $w $xylist black
    }
}

# DrawIsolines --
#     Draw isolines in the given grid
# Arguments:
#     canv        Canvas to draw in
#     x           X-coordinates of grid points (list of lists)
#     y           Y-coordinates of grid points (list of lists)
#     f           Values of the parameter on the grid cell corners
#     cont        List of contour classes (or empty to indicate
#                 automatic scaling
# Result:
#     None
# Side effect:
#     Isolines drawn
# Note:
#     A cell is only drawn if there are four well-defined
#     corners. If the x or y coordinate is missing or the value is
#     missing, the cell is skipped.
#
proc DrawIsolines {canv x y f {cont {}} } {
    global contour_options

    set contour_options(simple_box_contour) 0
    set contour_options(filled_contour) 0

#   DrawContour $canv $x $y $f 0.0 100.0 20.0
    DrawContour $canv $x $y $f $cont
}

# DrawShades --
#     Draw filled contours in the given grid
# Arguments:
#     canv        Canvas to draw in
#     x           X-coordinates of grid points (list of lists)
#     y           Y-coordinates of grid points (list of lists)
#     f           Values of the parameter on the grid cell corners
#     cont        List of contour classes (or empty to indicate
#                 automatic scaling
# Result:
#     None
# Side effect:
#     Shades (filled contours) drawn
# Note:
#     A cell is only drawn if there are four well-defined
#     corners. If the x or y coordinate is missing or the value is
#     missing, the cell is skipped.
#
proc DrawShades {canv x y f {cont {}} } {
    global contour_options

    set contour_options(simple_box_contour) 0
    set contour_options(filled_contour) 1

#   DrawContour $canv $x $y $f 0.0 100.0 20.0
    DrawContour $canv $x $y $f $cont
}

# DrawBox --
#     Draw filled cells in the given grid (colour chosen according
#     to the _average_ of the four corner values)
# Arguments:
#     canv        Canvas to draw in
#     x           X-coordinates of grid points (list of lists)
#     y           Y-coordinates of grid points (list of lists)
#     f           Values of the parameter on the grid cell corners
#     cont        List of contour classes (or empty to indicate
#                 automatic scaling
# Result:
#     None
# Side effect:
#     Filled cells (quadrangles) drawn
# Note:
#     A cell is only drawn if there are four well-defined
#     corners. If the x or y coordinate is missing or the value is
#     missing, the cell is skipped.
#
proc DrawBox {canv x y f {cont {}} } {
    global contour_options

    set contour_options(simple_box_contour) 1
    set contour_options(filled_contour) 0

#   DrawContour $canv $x $y $f 0.0 100.0 20.0
    DrawContour $canv $x $y $f $cont
}

# Draw3DFunctionContour --
#    Plot a function of x and y with a color filled contour
# Arguments:
#    w           Name of the canvas
#    function    Name of a procedure implementing the function
#    cont        contour levels
# Result:
#    None
# Side effect:
#    The plot of the function - given the grid
#
proc Draw3DFunctionContour { w function {cont {}} } {
    global scaling
    global contour_options

    set contour_options(simple_box_contour) 0
    set contour_options(filled_contour) 1
    set noTrans 0

    setColormapColors  [llength $cont]

    set nxcells $scaling($w,nxcells)
    set nycells $scaling($w,nycells)
    set xmin    $scaling($w,xmin)
    set xmax    $scaling($w,xmax)
    set ymin    $scaling($w,ymin)
    set ymax    $scaling($w,ymax)
    set dx      [expr {($xmax-$xmin)/double($nxcells)}]
    set dy      [expr {($ymax-$ymin)/double($nycells)}]

    foreach {fill border} $scaling($w,colours) {break}

    #
    # Draw the quadrangles making up the plot in the right order:
    # first y from minimum to maximum
    # then x from maximum to minimum
    #
    for { set j 0 } { $j < $nycells } { incr j } {
        set y1 [expr {$ymin + $dy*$j}]
        set y2 [expr {$y1   + $dy}]
        for { set i $nxcells } { $i > 0 } { incr i -1 } {
            set x2 [expr {$xmin + $dx*$i}]
            set x1 [expr {$x2   - $dx}]

            set z11 [$function $x1 $y1]
            set z12 [$function $x1 $y2]
            set z21 [$function $x2 $y1]
            set z22 [$function $x2 $y2]

            foreach {px11 py11} [coords3DToPixel $w $x1 $y1 $z11] {break}
            foreach {px12 py12} [coords3DToPixel $w $x1 $y2 $z12] {break}
            foreach {px21 py21} [coords3DToPixel $w $x2 $y1 $z21] {break}
            foreach {px22 py22} [coords3DToPixel $w $x2 $y2 $z22] {break}

            set xb [list $px11 $px21 $px22 $px12]
            set yb [list $py11 $py21 $py22 $py12]
            set fb [list $z11  $z21  $z22  $z12 ]

            Box_contour $w $xb $yb $fb $cont $noTrans

            $w create line $px11 $py11 $px21 $py21 $px22 $py22 \
                           $px12 $py12 $px11 $py11 \
                           -fill $border
      }
   }
}

# DrawContour --
#     Routine that loops over the grid and delegates the actual drawing
# Arguments:
#     canv        Canvas to draw in
#     x           X-coordinates of grid points (list of lists)
#     y           Y-coordinates of grid points (list of lists)
#     f           Values of the parameter on the grid cell corners
#     cont        List of contour classes (or empty to indicate
#                 automatic scaling)
# Result:
#     None
# Side effect:
#     Isolines, shades or boxes drawn
# Note:
#     A cell is only drawn if there are four well-defined
#     corners. If the x or y coordinate is missing or the value is
#     missing, the cell is skipped.
#
proc DrawContour {canv x y f cont} {
    global contour_options
    global colorMap

    #
    # Construct the class-colour list
    #
    set cont [MakeContourClasses $f $cont [expr {1-$contour_options(filled_contour)}]]

    set fmin  [lindex $cont 0 0]
    set fmax  [lindex $cont end 0]
    set ncont [llength $cont]

    # Now that we know how many entries (ncont), create
    # the colormap colors
    #
    # I moved this into MakeContourClasses...
    #    setColormapColors  $ncont

    set maxrow [llength $x]
    set maxcol [llength [lindex $x 0]]

    for {set i 0} {$i < $maxrow-1} {incr i} {
        set i1 [expr {$i + 1}]
        for {set j 0} {$j < $maxcol-1} {incr j} {
            set j1 [expr {$j + 1}]

            set x1 [lindex $x $i1 $j]
            set x2 [lindex $x $i $j]
            set x3 [lindex $x $i $j1]
            set x4 [lindex $x $i1 $j1]

            set y1 [lindex $y $i1 $j]
            set y2 [lindex $y $i $j]
            set y3 [lindex $y $i $j1]
            set y4 [lindex $y $i1 $j1]

            set f1 [lindex $f $i1 $j]
            set f2 [lindex $f $i $j]
            set f3 [lindex $f $i $j1]
            set f4 [lindex $f $i1 $j1]

            set xb [list $x1 $x2 $x3 $x4]
            set yb [list $y1 $y2 $y3 $y4]
            set fb [list $f1 $f2 $f3 $f4]

            if { [lsearch $fb {}] >= 0 ||
                 [lsearch $xb {}] >= 0 ||
                 [lsearch $yb {}] >= 0    } {
                continue
            }

            Box_contour $canv $xb $yb $fb $cont
        }
    }
}

# Box_contour --
#     Draw a filled box
# Arguments:
#     canv        Canvas to draw in
#     xb          X-coordinates of the four corners
#     yb          Y-coordinates of the four corners
#     fb          Values of the parameter on the four corners
#     cont        List of contour classes and colours
# Result:
#     None
# Side effect:
#     Box drawn for a single cell
#
proc Box_contour {canv xb yb fb cont {doTrans 1}} {
    global colorMap
    global contour_options

    foreach {x1 x2 x3 x4} $xb {}
    foreach {y1 y2 y3 y4} $yb {}
    foreach {f1 f2 f3 f4} $fb {}

    set xc [expr {($x1 + $x2 + $x3 + $x4) * 0.25}]
    set yc [expr {($y1 + $y2 + $y3 + $y4) * 0.25}]
    set fc [expr {($f1 + $f2 + $f3 + $f4) * 0.25}]

    if {$contour_options(simple_box_contour)} {

        set fmin  [lindex $cont 0]
        set fmax  [lindex $cont end]
        set ncont [llength $cont]

        set ic 0
        for {set i 0} {$i < $ncont} {incr i} {
            set ff [lindex $cont $i 0]
            if {$ff <= $fc} {
                set ic $i
            }
        }

        set xylist [list $x1 $y1 $x2 $y2 $x3 $y3 $x4 $y4]

        # canvasPlot::polygon $win $xylist -fill $cont($ic,color)
        ###        C_polygon $canv $xylist $cont($ic,color)
        C_polygon $canv $xylist [lindex $cont $ic 1]

    } else {

#debug#        puts "Tri_contour 1)"
        Tri_contour $canv $x1 $y1 $f1 $x2 $y2 $f2 $xc $yc $fc $cont $doTrans

#debug#        puts "Tri_contour 2)"
        Tri_contour $canv $x2 $y2 $f2 $x3 $y3 $f3 $xc $yc $fc $cont $doTrans

#debug#        puts "Tri_contour 3)"
        Tri_contour $canv $x3 $y3 $f3 $x4 $y4 $f4 $xc $yc $fc $cont $doTrans

#debug#        puts "Tri_contour 4)"
        Tri_contour $canv $x4 $y4 $f4 $x1 $y1 $f1 $xc $yc $fc $cont $doTrans

    }

}

# Tri_contour --
#     Draw isolines or shades in a triangle
# Arguments:
#     canv        Canvas to draw in
#     x1,x2,x3    X-coordinate  of the three corners
#     y1,y2,y3    Y-coordinates of the three corners
#     f1,f2,f3    Values of the parameter on the three corners
#     cont        List of contour classes and colours
# Result:
#     None
# Side effect:
#     Isolines/shades drawn for a single triangle
#
proc Tri_contour { canv x1 y1 f1 x2 y2 f2 x3 y3 f3 cont {doTrans 1} } {
    global contour_options
    global colorMap

    set ncont [llength $cont]


    # Find the min/max function values for this triangle
    #
    set tfmin  [min $f1 $f2 $f3]
    set tfmax  [max $f1 $f2 $f3]

    # Based on the above min/max, figure out which
    # contour levels/colors that bracket this interval
    #
    set imin 0
    set imax 0   ;#mbs#
    for {set i 0} {$i < $ncont} {incr i} {
        set ff [lindex $cont $i]           ; ### set ff $cont($i,fval)
        if {$ff <= $tfmin} {
            set imin $i
            set imax $i
        }
        if { $ff <= $tfmax} {
            set imax $i
        }
    }

    set vertlist {}

    # Loop over all contour levels of interest for this triangle
    #
    for {set ic $imin} {$ic <= $imax} {incr ic} {

        # Get the value for this contour level
        #
        set ff [lindex $cont $ic 0]         ;###  set ff $cont($ic,fval)

        set xylist   {}
        set pxylist  {}

        # Classify the triangle based on whether the functional values, f1,f2,f3
        # are above (+), below (-), or equal (=) to the current contour level ff
        #
        set s1 [setFLevel $f1 $ff]
        set s2 [setFLevel $f2 $ff]
        set s3 [setFLevel $f3 $ff]

        set class "$s1$s2$s3"

        # Describe class here...

        # ( - - - )   : Case A,
        # ( - - = )   : Case B, color a point, do nothing
        # ( - - + )   : Case C, contour between {23}-{31}
        # ( - = - )   : Case D, color a point, do nothing
        # ( - = = )   : Case E, contour line between 2-3
        # ( - = + )   : Case F, contour between 2-{31}
        # ( - + - )   : Case G, contour between {12}-{23}
        # ( - + = )   : Case H, contour between {12}-3
        # ( - + + )   : Case I, contour between {12}-{31}
        # ( = - - )   : Case J, color a point, do nothing
        # ( = - = )   : Case K, contour line between 1-3
        # ( = - + )   : Case L, contour between 1-{23}
        # ( = = - )   : Case M, contour line between 1-2
        # ( = = = )   : Case N, fill full triangle, return
        # ( = = + )   : Case M,
        # ( = + - )   : Case L,
        # ( = + = )   : Case K,
        # ( = + + )   : Case J,
        # ( + - - )   : Case I,
        # ( + - = )   : Case H,
        # ( + - + )   : Case G,
        # ( + = - )   : Case F,
        # ( + = = )   : Case E,
        # ( + = + )   : Case D,
        # ( + + - )   : Case C,
        # ( + + = )   : Case B,
        # ( + + + )   : Case A,


        switch -- $class {

            "---" {
                ############### Case A ###############

#debug#                puts "class A = $class , $ic , $ff"
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                return
            }

            "+++" {
#debug#                puts "class A = $class , $ic , $ff"
                if {$contour_options(filled_contour)} {
                    if {$ic == $imax} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }
            }

            "===" {
                ############### Case N ###############

#debug#                puts "class N = $class , $ic , $ff"
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                return
            }

            "--=" {
                ############### Case B ###############

#debug#                puts "class B = $class , $ic , $ff"
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                return
            }

            "++=" {
#debug#                puts "class B= $class , $ic , $ff , do nothing unless ic == imax"
                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }
            }

            "-=-" {
                ############### Case D ###############

#debug#                puts "class D = $class , $ic , $ff"
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                return
            }

            "+=+" {
#debug#                puts "class D = $class , $ic , $ff , do nothing unless ic == imax"
                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }
            }

            "=--" {
                ############### Case J ###############

#debug#                puts "class J = $class , $ic , $ff"
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                return
            }

            "=++" {
#debug#                puts "class J = $class , $ic , $ff , do nothing unless ic == imax"
                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }
            }

            "=-=" {
                ############### Case K ###############

#debug#                puts "class K = $class , $ic , $ff"
                set xylist [list $x1 $y1 $x3 $y3]
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                return

            }

            "=+=" {
#debug#                puts "class K = $class , $ic , $ff"
                set xylist [list $x1 $y1 $x3 $y3]
                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                    C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                } else {
                    C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                }
            }

            "-==" {
                ############### Case E ###############

#debug#                puts "class E = $class , $ic , $ff"
                set xylist [list $x2 $y2 $x3 $y3]
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                return
            }

            "+==" {
#debug#                puts "class E = $class , $ic , $ff"
                set xylist [list $x2 $y2 $x3 $y3]
                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                    C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                } else {
                    C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                }
            }

            "==-" {
                ############### Case M ###############

#debug#                puts "class M = $class , $ic , $ff"
                set xylist [list $x1 $y1 $x2 $y2]
                if {$contour_options(filled_contour)} {
                    set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                return
            }

            "==+" {
#debug#                puts "class M = $class , $ic , $ff"
                set xylist [list $x1 $y1 $x2 $y2]
                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                    C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                } else {
                    C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                }

            }

            "-=+" {
                ############### Case F ###############

#debug#                puts "class F = $class , $ic , $ff"
                set xylist [list $x2 $y2]
                set xyf2  [fintpl $x3 $y3 $f3 $x1 $y1 $f1 $ff]
                foreach {xx yy} $xyf2 {}
                lappend xylist $xx $yy

                if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x1 $y1
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                set x1 $xx; set y1 $yy; set f1 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "+=-" {
#debug#                puts "class F = $class , $ic , $ff"
                set xylist [list $x2 $y2]
                set xyf2  [fintpl $x3 $y3 $f3 $x1 $y1 $f1 $ff]
                foreach {xx yy} $xyf2 {}
                lappend xylist $xx $yy

                if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x3 $y3
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                set x3 $xx; set y3 $yy; set f3 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "-+=" {
                ############### Case H ###############

#debug#                puts "class H = $class , $ic , $ff"
                set xylist [fintpl $x1 $y1 $f1 $x2 $y2 $f2 $ff]
                foreach {xx yy} $xylist {}
                lappend xylist $x3 $y3

                if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x1 $y1
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                set x1 $xx; set y1 $yy; set f1 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "+-=" {
#debug#                puts "class H = $class , $ic , $ff"
                set xylist [fintpl $x1 $y1 $f1 $x2 $y2 $f2 $ff]
                foreach {xx yy} $xylist {}
                lappend xylist $x3 $y3
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x2 $y2
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                set x2 $xx; set y2 $yy; set f2 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "=-+" {
                ############### Case L ###############

#debug#                puts "class L = $class , $ic , $ff"
                set xylist [fintpl $x2 $y2 $f2 $x3 $y3 $f3 $ff]
                foreach {xx yy} $xylist {}
                lappend xylist $x1 $y1
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x2 $y2
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                set x2 $xx; set y2 $yy; set f2 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "=+-" {
#debug#                puts "class L = $class , $ic , $ff"
                set xylist [fintpl $x2 $y2 $f2 $x3 $y3 $f3 $ff]
                foreach {xx yy} $xylist {}
                lappend xylist $x1 $y1
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x3 $y3
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans

                set x3 $xx; set y3 $yy; set f3 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "--+" {
                ############### Case C ###############

#debug#                puts "class C = $class , $ic , $ff"
                set xyf1  [fintpl $x2 $y2 $f2 $x3 $y3 $f3 $ff]
                set xyf2  [fintpl $x3 $y3 $f3 $x1 $y1 $f1 $ff]
                set xylist $xyf1
                foreach {xx1 yy1} $xyf1 {}
                foreach {xx2 yy2} $xyf2 {}
                lappend xylist $xx2 $yy2
                if {$contour_options(filled_contour)} {
                    set pxylist $xylist
                    lappend pxylist $x1 $y1 $x2 $y2
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                    if {$ic == $imax} {
                        set pxylist $xylist
                        lappend pxylist $x3 $y3
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                    }
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                set oldlist {}
                set x1 $xx1; set y1 $yy1; set f1 $ff
                set x2 $xx2; set y2 $yy2; set f2 $ff
                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }
            }

            "++-" {
#debug#                puts "class C = $class , $ic , $ff"
                set xyf1  [fintpl $x2 $y2 $f2 $x3 $y3 $f3 $ff]
                set xyf2  [fintpl $x3 $y3 $f3 $x1 $y1 $f1 $ff]
                set xylist $xyf1
                foreach {xx1 yy1} $xyf1 {}
                foreach {xx2 yy2} $xyf2 {}
                lappend xylist $xx2 $yy2
                if {$contour_options(filled_contour)} {
                    set pxylist $xylist
                    lappend pxylist $x3 $y3
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x1 $y1 $x2 $y2
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                    }

                } else {

#debug#                    puts "call Tri_contour : 1) $class"
#debug#                    puts "   : $xx1 $yy1 $ff $xx2 $yy2 $ff $x1 $y1 $f1"
                    Tri_contour $canv $xx1 $yy1 $ff $xx2 $yy2 $ff $x1 $y1 $f1 $cont $doTrans

#debug#                    puts "call Tri_contour : 2) $class"
#debug#                    puts "   : $xx1 $yy1 $ff $x1 $y1 $f1 $x2 $y2 $f2"
                    Tri_contour $canv $xx1 $yy1 $ff $x1 $y1 $f1 $x2 $y2 $f2 $cont $doTrans

                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                return

            }

            "-+-" {
                ############### Case G ###############

#debug#                puts "class G = $class , $ic , $ff"
                set xyf1  [fintpl $x1 $y1 $f1 $x2 $y2 $f2 $ff]
                set xyf2  [fintpl $x2 $y2 $f2 $x3 $y3 $f3 $ff]
                set xylist $xyf1
                foreach {xx1 yy1} $xyf1 {}
                foreach {xx2 yy2} $xyf2 {}
                lappend xylist $xx2 $yy2
                if {$contour_options(filled_contour)} {
                    set pxylist $xylist
                    lappend pxylist $x3 $y3 $x1 $y1
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                    if {$ic == $imax} {
                        set pxylist $xylist
                        lappend pxylist $x2 $y2
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                    }
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                set oldlist {}
                set x1 $xx1; set y1 $yy1; set f1 $ff
                set x3 $xx2; set y3 $yy2; set f3 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "+-+" {
#debug#                puts "class G = $class , $ic , $ff"
                set xyf1  [fintpl $x1 $y1 $f1 $x2 $y2 $f2 $ff]
                set xyf2  [fintpl $x2 $y2 $f2 $x3 $y3 $f3 $ff]
                foreach {xx1 yy1} $xyf1 {}
                foreach {xx2 yy2} $xyf2 {}
                set xylist $xyf1
                lappend xylist $xx2 $yy2
                if {$contour_options(filled_contour)} {
                    set pxylist $xylist
                    lappend pxylist $x2 $y2
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x3 $y3 $x1 $y1
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                    }

                } else {

#debug#                    puts "call Tri_contour : 1) $class"
#debug#                    puts "   : $xx1 $yy1 $ff $xx2 $yy2 $ff $x3 $y3 $f3"
                    Tri_contour $canv $xx1 $yy1 $ff $xx2 $yy2 $ff $x3 $y3 $f3 $cont $doTrans

#debug#                    puts "call Tri_contour : 2) $class"
#debug#                    puts "   : $xx1 $yy1 $ff $x3 $y3 $f3 $x1 $y1 $f1"
                    Tri_contour $canv $xx1 $yy1 $ff $x3 $y3 $f3 $x1 $y1 $f1 $cont $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                return

            }

            "+--" {
                ############### Case I ###############

#debug#                puts "class I = $class , $ic , $ff"
                set xyf1  [fintpl $x1 $y1 $f1 $x2 $y2 $f2 $ff]
                set xyf2  [fintpl $x3 $y3 $f3 $x1 $y1 $f1 $ff]
                set xylist $xyf1
                foreach {xx1 yy1} $xyf1 {}
                foreach {xx2 yy2} $xyf2 {}
                lappend xylist $xx2 $yy2
                if {$contour_options(filled_contour)} {
                    set pxylist $xylist
                    lappend pxylist $x3 $y3 $x2 $y2
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                    if {$ic == $imax} {
                        set pxylist $xylist
                        lappend pxylist $x1 $y1
                        C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                    }
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                set oldlist {}
                set x2 $xx1; set y2 $yy1; set f2 $ff
                set x3 $xx2; set y3 $yy2; set f3 $ff

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist [list $x1 $y1 $x2 $y2 $x3 $y3]
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                        return
                    }
                }

            }

            "-++" {
#debug#                puts "class I = $class , $ic , $ff"
                set xyf1  [fintpl $x1 $y1 $f1 $x2 $y2 $f2 $ff]
                set xyf2  [fintpl $x3 $y3 $f3 $x1 $y1 $f1 $ff]
                foreach {xx1 yy1} $xyf1 {}
                foreach {xx2 yy2} $xyf2 {}
                set xylist $xyf1
                lappend xylist $xx2 $yy2
                if {$contour_options(filled_contour)} {
                    set pxylist $xylist
                    lappend pxylist $x1 $y1
                    C_polygon $canv $pxylist [lindex $colorMap $ic] $doTrans
                }

                if {$ic == $imax} {
                    if {$contour_options(filled_contour)} {
                        set pxylist $xylist
                        lappend pxylist $x3 $y3 $x2 $y2
                        set ictmp [expr {$ic + 1}]
                        C_polygon $canv $pxylist [lindex $colorMap $ictmp] $doTrans
                    }

                } else {

#debug#                    puts "call Tri_contour : 1) $class"
#debug#                    puts "   : $xx1 $yy1 $ff $xx2 $yy2 $ff $x3 $y3 $f3"
                    Tri_contour $canv $xx1 $yy1 $ff $xx2 $yy2 $ff $x3 $y3 $f3 $cont $doTrans

#debug#                    puts "call Tri_contour : 2) $class"
#debug#                    puts "   : $xx1 $yy1 $ff $x3 $y3 $f3 $x2 $y2 $f2"
                    Tri_contour $canv $xx1 $yy1 $ff $x3 $y3 $f3 $x2 $y2 $f2 $cont $doTrans
                }
                C_line $canv $xylist [lindex $colorMap $ic] $doTrans
                return

            }

        }

    }
}

# setFLevel --
#     Auxiliary function: used to classify one functional value to another
# Arguments:
#     f1          Second break point and value
#     f2          Value to find
# Result:
#     +    f1 > f2
#     =    f1 = f2
#     -    f1 < f2
#
proc setFLevel {f1 f2} {
    if {$f1 > $f2} {
        return "+"
    } else {
        if {$f1 < $f2} {
            return "-"
        } else {
            return "="
        }
    }
}

# fintpl --
#     Auxiliary function: inverse interpolation
# Arguments:
#     x1,y1,f1    First break point and value
#     x2,y2,f2    Second break point and value
#     ff          Value to find
# Result:
#     x,y coordinates of point with that value
#
proc fintpl {x1 y1 f1 x2 y2 f2 ff} {

    if {[expr {$f2 - $f1}] != 0.0} {
        set xx  [expr {$x1 + (($ff - $f1)*($x2 - $x1)/($f2 - $f1))}]
        set yy  [expr {$y1 + (($ff - $f1)*($y2 - $y1)/($f2 - $f1))}]
    } else {

        # If the logic was handled correctly above, this point
        # should never be reached.
        #
        # puts "FINTPL : f1 == f2 : x1,y1 : $x1 , $y1 : x2,y2 : $x2 , $y2"
        set xx $x1
        set yy $y1
    }

    set xmin [min $x1 $x2]
    set xmax [max $x1 $x2]
    set ymin [min $y1 $y2]
    set ymax [max $y1 $y2]

    if {$xx < $xmin} { set xx $xmin }
    if {$xx > $xmax} { set xx $xmax }
    if {$yy < $ymin} { set yy $ymin }
    if {$yy > $ymax} { set yy $ymax }

    return [list $xx $yy]
}

# min --
#     Auxiliary function: find the minimum of the arguments
# Arguments:
#     val         First value
#     args        All others
# Result:
#     Minimum over the arguments
#
proc min { val args } {
    set min $val
    foreach val $args {
        if { $val < $min } {
            set min $val
        }
    }
    return $min
}

# max --
#     Auxiliary function: find the maximum of the arguments
# Arguments:
#     val         First value
#     args        All others
# Result:
#     Maximum over the arguments
#
proc max { val args } {
    set max $val
    foreach val $args {
        if { $val > $max } {
            set max $val
        }
    }
    return $max
}

# C_line --
#     Draw a line
# Arguments:
#     canv        Canvas to draw in
#     xylist      List of raw coordinates
#     color       Chosen colour
#     args        Any additional arguments (for line style and such)
# Result:
#     None
#
proc C_line {canv xylist color {doTrans 1} } {

    if {$doTrans} {
        set wxylist {}
        foreach {xx yy} $xylist {
            foreach {pxcrd pycrd} [coordsToPixel $canv $xx $yy] {break}
            lappend wxylist $pxcrd $pycrd
        }
        eval "$canv create line $wxylist -fill $color"

    } else {
        $canv create line $xylist -fill $color
    }
}

# C_polygon --
#     Draw a polygon
# Arguments:
#     canv        Canvas to draw in
#     xylist      List of raw coordinates
#     color       Chosen colour
#     args        Any additional arguments (for line style and such)
# Result:
#     None
#
proc C_polygon {canv xylist color {doTrans 1}} {

    if {$doTrans} {
        set wxylist {}
        foreach {xx yy} $xylist {
            foreach {pxcrd pycrd} [coordsToPixel $canv $xx $yy] {break}
            lappend wxylist $pxcrd $pycrd
        }
        eval "$canv create polygon $wxylist -fill $color"

    } else {
        $canv create polygon $xylist -fill $color
    }
}

# MakeContourClasses --
#     Return contour classes and colours
# Arguments:
#     values      List of values
#     classes     Given list of classes or class/colours
#     offset      Correction for calculating colours
# Result:
#     List of pairs of class limits and colours
# Note:
#     This should become more sophisticated!
#
proc MakeContourClasses {values classes offset} {
    global contour_options
    global colorMap

    if { [llength $classes] == 0 } {
        set min {}
        set max {}
        foreach row $values {
            foreach v $row {
                if { $v == {} } {continue}

                if { $min == {} || $min > $v } {
                    set min $v
                }

                if { $max == {} || $max < $v } {
                    set max $v
                }
            }
        }

        foreach {xmin xmax xstep} [determineScale $min $max] {break}

        #
        # The contour classes must encompass all values
        # There might be a problem with border cases
        #
        set classes {}
        set x $xmin

        while { $x < $xmax+0.5*$xstep } {
            #mbs# lappend classes [list $x]
            set  x [expr {$x+$xstep}]
            lappend classes [list $x]
        }

        # Now that we know how many entries (ncont), create
        # the colormap colors
        #
        setColormapColors  [expr {[llength $classes] + 1}]

    } elseif { [llength [lindex $classes 0]] == 1 } {
        #mbs#  Changed the above line from " == 2 " to " == 1 "
        setColormapColors  [llength $classes] $offset
        return $classes
    }

    #
    # Add the colours
    #
#####    set cont {}
#####    set c 0
#####
#####    foreach x $classes {
#####        set col [lindex $contour_options(colourmap) $c]
#####        if { $col == {} } {
#####            set c 0
#####            set col [lindex $contour_options(colourmap) $c]
#####        }
#####        lappend cont [list $x $col]
#####        incr c
#####    }
#####
#####    return $cont

#debug#    puts "classes (cont) : $classes"

    return $classes
}


# setColormapColors --
#     Auxiliary function: Based on the current colormap type
#     create a colormap with requested number of entries
# Arguments:
#     ncont       Number of colors in the colormap
#     offset      Offset for interval
# Result:
#     List of colours
#
proc setColormapColors  {ncont offset} {
    global colorMapType
    global colorMap

#debug#    puts "SetColormapColors : ncont = $ncont"

    # Note : The default colormap is "jet"

    switch -- $colorMapType {

        custom {
            return
        }

        hsv {
            set hueStart     0.0
            set hueEnd     240.0
            set colorMap   {}

            for {set i 0} {$i <= $ncont} {incr i} {
                if { $ncont > 1 } {
                    set dh [expr {($hueStart - $hueEnd) / ($ncont - $offset)}]
                } else {
                    set dh 0.0
                }
                set hue  [expr {$hueStart - ($i * $dh)}]
                if {$hue < 0.0} {
                    set hue  [expr {360.0 + $hue}]
                }
                set rgbList [Hsv2rgb $hue 1.0 1.0]
                set r    [expr {int([lindex $rgbList 0] * 65535)}]
                set g    [expr {int([lindex $rgbList 1] * 65535)}]
                set b    [expr {int([lindex $rgbList 2] * 65535)}]

                set color  [format "#%.4x%.4x%.4x" $r $g $b]
                lappend colorMap $color
            }
        }

        hot {
            set colorMap {}
            set nc1          [expr {int($ncont * 0.33)}]
            set nc2          [expr {int($ncont * 0.67)}]

            for {set i 0} {$i <= $ncont} {incr i} {

                if {$i <= $nc1} {
                    set fval  [expr { double($i) / (double($nc1)) } ]
                    set r     [expr {int($fval * 65535)}]
                    set g     0
                    set b     0
                } else {
                    if {$i <= $nc2} {
                        set fval  [expr { double($i-$nc1) / (double($nc2-$nc1)) } ]
                        set r     65535
                        set g     [expr {int($fval * 65535)}]
                        set b     0
                    } else {
                        set fval  [expr { double($i-$nc2) / (double($ncont-$nc2)) } ]
                        set r     65535
                        set g     65535
                        set b     [expr {int($fval * 65535)}]
                    }
                }
                set color  [format "#%.4x%.4x%.4x" $r $g $b]
                lappend colorMap $color
            }
        }

        cool {
            set colorMap {}

            for {set i 0} {$i <= $ncont} {incr i} {

                set fval  [expr { double($i) / (double($ncont)-$offset) } ]
                set val   [expr { 1.0 - $fval }]

                set r    [expr {int($fval * 65535)}]
                set g    [expr {int($val * 65535)}]
                set b    65535

                set color  [format "#%.4x%.4x%.4x" $r $g $b]
                lappend colorMap $color
            }
        }

        grey -
        gray {
            set colorMap {}

            for {set i 0} {$i <= $ncont} {incr i} {

                set fval  [expr { double($i) / (double($ncont)-$offset) } ]
                set val  [expr {0.4 + (0.5 * $fval) }]

                set r    [expr {int($val * 65535)}]
                set g    [expr {int($val * 65535)}]
                set b    [expr {int($val * 65535)}]

                set color  [format "#%.4x%.4x%.4x" $r $g $b]
                lappend colorMap $color
            }
        }

        jet -
        default {
            set hueStart   240.0
            set hueEnd       0.0
            set colorMap   {}

            for {set i 0} {$i <= $ncont} {incr i} {
                if { $ncont > 1 } {
                    set dh [expr {($hueStart - $hueEnd) / ($ncont - $offset)}]
                } else {
                    set dh 0.0
                }
                set hue  [expr {$hueStart - ($i * $dh)}]
                if {$hue < 0.0} {
                    set hue  [expr {360.0 + $hue}]
                }
                set rgbList [Hsv2rgb $hue 1.0 1.0]
                set r    [expr {int([lindex $rgbList 0] * 65535)}]
                set g    [expr {int([lindex $rgbList 1] * 65535)}]
                set b    [expr {int([lindex $rgbList 2] * 65535)}]

                set color  [format "#%.4x%.4x%.4x" $r $g $b]
                lappend colorMap $color
            }
        }

    }
}

# colorMap --
#     Define the current colormap type
# Arguments:
#     cmap        Type of colormap
# Result:
#     Updated the internal variable "colorMapType"
# Note:
#     Possibly handle "custom" colormaps differently
#     At present, if the user passes in a list (length > 1)
#     rather than a string, then it is assumes that (s)he
#     passed in a list of colors.
#
proc colorMap {cmap} {
    global colorMapType
    global colorMap

    switch -- $cmap {

        "grey" -
        "gray" { set colorMapType $cmap }

        "jet"  { set colorMapType $cmap }

        "hot"  { set colorMapType $cmap }

        "cool" { set colorMapType $cmap }

        "hsv"  { set colorMapType $cmap }

        default {
            if {[string is alpha $cmap] == 1} {
                puts "Colormap : Unknown colorMapType, $cmap.  Using JET"
                set colorMapType jet

            } else {
                if {[llength $cmap] > 1} {
                    set colorMapType "custom"
                    set colorMap     $cmap
                }
            }
        }
    }
}



########################################################################
#  The following two routines were borrowed from :
#
#        http://mini.net/cgi-bin/wikit/666.html
########################################################################

# Rgb2hsv --
#
#       Convert a color value from the RGB model to HSV model.
#
# Arguments:
#       r g b  the red, green, and blue components of the color
#               value.  The procedure expects, but does not
#               ascertain, them to be in the range 0 to 1.
#
# Results:
#       The result is a list of three real number values.  The
#       first value is the Hue component, which is in the range
#       0.0 to 360.0, or -1 if the Saturation component is 0.
#       The following to values are Saturation and Value,
#       respectively.  They are in the range 0.0 to 1.0.
#
# Credits:
#       This routine is based on the Pascal source code for an
#       RGB/HSV converter in the book "Computer Graphics", by
#       Baker, Hearn, 1986, ISBN 0-13-165598-1, page 304.
#
proc Rgb2hsv {r g b} {
    set h [set s [set v 0.0]]
    set sorted [lsort -real [list $r $g $b]]
    set v [expr {double([lindex $sorted end])}]
    set m [lindex $sorted 0]

    set dist [expr {double($v-$m)}]
    if {$v} {
        set s [expr {$dist/$v}]
    }
    if {$s} {
        set r' [expr {($v-$r)/$dist}] ;# distance of color from red
        set g' [expr {($v-$g)/$dist}] ;# distance of color from green
        set b' [expr {($v-$b)/$dist}] ;# distance of color from blue
        if {$v==$r} {
            if {$m==$g} {
                set h [expr {5+${b'}}]
            } else {
                set h [expr {1-${g'}}]
            }
        } elseif {$v==$g} {
            if {$m==$b} {
                set h [expr {1+${r'}}]
            } else {
                set h [expr {3-${b'}}]
            }
        } else {
            if {$m==$r} {
                set h [expr {3+${g'}}]
            } else {
                set h [expr {5-${r'}}]
            }
        }
        set h [expr {$h*60}]          ;# convert to degrees
    } else {
        # hue is undefined if s == 0
        set h -1
    }
    return [list $h $s $v]
}

# Hsv2rgb --
#
#       Convert a color value from the HSV model to RGB model.
#
# Arguments:
#       h s v  the hue, saturation, and value components of
#               the color value.  The procedure expects, but
#               does not ascertain, h to be in the range 0.0 to
#               360.0 and s, v to be in the range 0.0 to 1.0.
#
# Results:
#       The result is a list of three real number values,
#       corresponding to the red, green, and blue components
#       of a color value.  They are in the range 0.0 to 1.0.
#
# Credits:
#       This routine is based on the Pascal source code for an
#       HSV/RGB converter in the book "Computer Graphics", by
#       Baker, Hearn, 1986, ISBN 0-13-165598-1, page 304.
#
proc Hsv2rgb {h s v} {
    set v [expr {double($v)}]
    set r [set g [set b 0.0]]
    if {$h == 360} { set h 0 }
    # if you feed the output of rgb2hsv back into this
    # converter, h could have the value -1 for
    # grayscale colors.  Set it to any value in the
    # valid range.
    if {$h == -1} { set h 0 }
    set h [expr {$h/60}]
    set i [expr {int(floor($h))}]
    set f [expr {$h - $i}]
    set p1 [expr {$v*(1-$s)}]
    set p2 [expr {$v*(1-($s*$f))}]
    set p3 [expr {$v*(1-($s*(1-$f)))}]
    switch -- $i {
        0 { set r $v  ; set g $p3 ; set b $p1 }
        1 { set r $p2 ; set g $v  ; set b $p1 }
        2 { set r $p1 ; set g $v  ; set b $p3 }
        3 { set r $p1 ; set g $p2 ; set b $v  }
        4 { set r $p3 ; set g $p1 ; set b $v  }
        5 { set r $v  ; set g $p1 ; set b $p2 }
    }
    return [list $r $g $b]
}

# DrawIsolinesFunctionValues --
#     Draw isolines in the given grid with given function values.
# Arguments:
#     canv : Canvas to draw in
#     xvec : List of points in the x axis
#     yvec : List of points in the y axis
#     fmat : Matrix of function values at the points defined by x and y.
#       The matrix is given as a list of rows, where each row
#       stores the function values with a fixed y and a varying x.
#     cont        List of contour classes (or empty to indicate
#                 automatic scaling
# Result:
#     None
# Side effect:
#     Isolines drawn
# Note:
#     A cell is only drawn if there are four well-defined
#     corners. If the x or y coordinate is missing or the value is
#     missing, the cell is skipped.
# Author : Michael Baudin
#
proc DrawIsolinesFunctionValues {canv xvec yvec fmat {cont {}}} {
  global scaling
  set nx [llength $xvec]
  set ny [llength $xvec]
  if {$nx!=$ny} then {
    error "The number of values in xvec (nx=$nx) is different from the number of values in yvec (ny=$ny)"
  }
  #
  # Check the given values of xvec and yvec against the scaling of the plot,
  # which was given at the creation of the plot.
  #
  set index 0
  foreach xval $xvec {
    if {$xval > $scaling($canv,xmax) || $xval < $scaling($canv,xmin)} then {
      error "The given x value $xval at index $index of xvec is not in the x-axis range \[$scaling($canv,xmin),$scaling($canv,xmax)\]"
    }
    incr index
  }
  set index 0
  foreach yval $yvec {
    if {$yval > $scaling($canv,ymax) || $yval < $scaling($canv,ymin)} then {
      error "The given y value $yval at index $index of yvec is not in the y-axis range \[$scaling($canv,ymin),$scaling($canv,ymax)\]"
    }
    incr index
  }
  #
  # Form the xmat and ymat matrices based on the given x and y.
  #
  set xmat {}
  for {set iy 0} {$iy < $ny} {incr iy} {
    set xi {}
    for {set ix 0} {$ix < $nx} {incr ix} {
      lappend xi [lindex $xvec $ix]
    }
    lappend xmat $xi
  }
  set ymat {}
  for {set iy 0} {$iy < $ny} {incr iy} {
    set yi {}
    set yiy [lindex $yvec $iy]
    for {set ix 0} {$ix < $nx} {incr ix} {
      lappend yi $yiy
    }
    lappend ymat $yi
  }
  DrawIsolines $canv $xmat $ymat $fmat $cont
}

# DrawLegendIsolines --
#
#     Draw isolines in the legend for this plot
#
# Arguments:
#     w           Canvas/plot to draw in
#     values      List of values as used for the plot itself
#     contours    Contour classes
#
# Result:
#     None
#
# Side effect:
#     Entries in the legend added
#
# Note:
#     No support for an empty list of contour classes yet
#
proc DrawLegendIsolines {w values contours} {
    global data_series
    global colorMap

    set contours [MakeContourClasses $values $contours 1]

    set count 0
    foreach class $contours colour $colorMap {
        incr count
        set data_series($w,isoline_$class,-colour) $colour
        set data_series($w,isoline_$class,-type)   "line"

        DrawLegend $w "isoline_$class" "$class"

        if { $count == [llength $contours] } {
            break
        }
    }
}

# DrawLegendShades --
#
#     Draw shades in the legend for this plot
#
# Arguments:
#     w           Canvas/plot to draw in
#     values      List of values as used for the plot itself
#     contours    Contour classes
#
# Result:
#     None
#
# Side effect:
#     Entries in the legend added
#
# Note:
#     No support for an empty list of contour classes yet
#
proc DrawLegendShades {w values contours} {
    global data_series
    global colorMap

    set contours [MakeContourClasses $values $contours 0]

    set count 0
    set dir   "<"
    foreach class $contours colour $colorMap {
        incr count

        if { $count == [llength $colorMap] } {
            set dir ">"
            set class [lindex $contours end]
        }

        set data_series($w,shade_${dir}_$class,-colour) $colour
        set data_series($w,shade_${dir}_$class,-type)   "rectangle"

        DrawLegend $w "shade_${dir}_$class" "$dir $class"
    }
}

#
# Define default colour maps
#
set contour_options(colourmap,rainbow) \
    {darkblue blue cyan green yellow orange red magenta}
set contour_options(colourmap,white-blue) \
    {white paleblue cyan blue darkblue}
set contour_options(colourmap,detailed) {
#00000000ffff
#000035e4ffff
#00006bc9ffff
#0000a1aeffff
#0000d793ffff
#0000fffff285
#0000ffffbca0
#0000ffff86bc
#0000ffff50d7
#0000ffff1af2
#1af2ffff0000
#50d7ffff0000
#86bcffff0000
#bca0ffff0000
#f285ffff0000
#ffffd7930000
#ffffa1ae0000
#ffff6bc90000
#ffff35e40000
#ffff00000000
#ffff00000000
}
set contour_options(colourmap) $contour_options(colourmap,detailed)

#
# Define the default colour map
#
colorMap jet

# End of plotcontour.tcl


# plotgantt.tcl --
#    Facilities to draw Gantt charts in a dedicated canvas
#
# Note:
#    This source file contains the private functions for Gantt charts.
#    It is the companion of "plotchart.tcl"
#    Some functions have been derived from the similar time chart
#    functions.
#

# GanttColor --
#    Set the color of a component
# Arguments:
#    w           Name of the canvas
#    component   Component in question
#    color       New colour
# Result:
#    None
# Side effects:
#    Items with a tag equal to that component are changed
#
proc GanttColor { w component color } {
    global settings

    set settings($w,color,$component) $color

    switch -- $component {
    "description" -
    "summary"     {
        $w itemconfigure $component -foreground $color
    }
    "odd"         -
    "even"        {
        $w itemconfigure $component -fill $color -outline $color
    }
    "completed"   -
    "left"        {
        $w itemconfigure $component -fill $color
    }
    }
}

# GanttFont --
#    Set the font of a component
# Arguments:
#    w           Name of the canvas
#    component   Component in question
#    font        New font
# Result:
#    None
# Side effects:
#    Items with a tag equal to that component are changed
#
proc GanttFont { w component font } {
    global settings

    set settings($w,font,$component) $font

    switch -- $component {
    "description" -
    "summary"     {
        $w itemconfigure $component -font $font
    }
    }
}

# DrawGanttPeriod --
#    Draw a period
# Arguments:
#    w           Name of the canvas
#    text        Text to identify the "period" item
#    time_begin  Start time
#    time_end    Stop time
#    completed   Fraction completed (in %)
# Result:
#    List of item numbers, for further manipulation
# Side effects:
#    Data bars drawn in canvas
#
proc DrawGanttPeriod { w text time_begin time_end completed } {
    global settings
    global data_series
    global scaling

    #
    # Draw the text first
    #
    set ytext [expr {$scaling($w,current)-0.5}]
    foreach {x y} [coordsToPixel $w $scaling($w,xmin) $ytext] {break}

    set items {}
    lappend items \
        [$w create text 5 $y -text $text -anchor w \
                                    -tag {description vertscroll above} \
                                    -font $settings($w,font,description)]

    #
    # Draw the bar to indicate the period
    #
    set xmin  [clock scan $time_begin]
    set xmax  [clock scan $time_end]
    set xcmp  [expr {$xmin + $completed*($xmax-$xmin)/100.0}]
    set ytop  [expr {$scaling($w,current)-0.5*(1.0-$scaling($w,dy))}]
    set ybott [expr {$scaling($w,current)-0.5*(1.0+$scaling($w,dy))}]

    foreach {x1 y1} [coordsToPixel $w $xmin $ytop ] {break}
    foreach {x2 y2} [coordsToPixel $w $xmax $ybott] {break}
    foreach {x3 y2} [coordsToPixel $w $xcmp $ybott] {break}

    lappend items \
        [$w create rectangle $x1 $y1 $x3 $y2 -fill $settings($w,color,completed) \
                                             -tag {completed vertscroll horizscroll below}] \
        [$w create rectangle $x3 $y1 $x2 $y2 -fill $settings($w,color,left) \
                                             -tag {left vertscroll horizscroll below}] \
        [$w create text      [expr {$x2+10}] $y -text "$completed%" \
                                             -anchor w \
                                             -tag {description vertscroll horizscroll below} \
                                             -font $settings($w,font,description)]

    set scaling($w,current) [expr {$scaling($w,current)-1.0}]

    ReorderChartItems $w

    return $items
}

# DrawGanttVertLine --
#    Draw a vertical line with a label
# Arguments:
#    w           Name of the canvas
#    text        Text to identify the line
#    time        Time for which the line is drawn
# Result:
#    None
# Side effects:
#    Line drawn in canvas
#
proc DrawGanttVertLine { w text time {colour black}} {
    global settings
    global data_series
    global scaling

    #
    # Draw the text first
    #
    set xtime [clock scan $time]
    set ytext [expr {$scaling($w,ymax)-0.5*$scaling($w,dy)}]
    foreach {x y} [coordsToPixel $w $xtime $ytext] {break}

    $w create text $x $y -text $text -anchor w -font $settings($w,font,scale) \
        -tag {horizscroll timeline}

    #
    # Draw the line
    #
    foreach {x1 y1} [coordsToPixel $w $xtime $scaling($w,ymin)] {break}
    foreach {x2 y2} [coordsToPixel $w $xtime $scaling($w,ymax)] {break}

    $w create line $x1 $y1 $x2 $y2 -fill black -tag {horizscroll timeline tline}

    $w raise topmask
}

# DrawGanttMilestone --
#    Draw a "milestone"
# Arguments:
#    w           Name of the canvas
#    text        Text to identify the line
#    time        Time for which the milestone is drawn
#    colour      Optionally the colour
# Result:
#    None
# Side effects:
#    Triangle drawn in canvas
#
proc DrawGanttMilestone { w text time {colour black}} {
    global settings
    global data_series
    global scaling

    #
    # Draw the text first
    #
    set ytext [expr {$scaling($w,current)-0.5}]
    foreach {x y} [coordsToPixel $w $scaling($w,xmin) $ytext] {break}

    set items {}
    lappend items \
       [$w create text 5 $y -text $text -anchor w -tag {description vertscroll above} \
             -font $settings($w,font,description)]
       # Colour text?

    #
    # Draw an upside-down triangle to indicate the time
    #
    set xcentre [clock scan $time]
    set ytop    [expr {$scaling($w,current)-0.2}]
    set ybott   [expr {$scaling($w,current)-0.8}]

    foreach {x1 y1} [coordsToPixel $w $xcentre $ybott] {break}
    foreach {x2 y2} [coordsToPixel $w $xcentre $ytop]  {break}

    set x2 [expr {$x1-0.4*($y1-$y2)}]
    set x3 [expr {$x1+0.4*($y1-$y2)}]
    set y3 $y2

    lappend items \
        [$w create polygon $x1 $y1 $x2 $y2 $x3 $y3 -fill $colour \
            -tag {vertscroll horizscroll below}]

    set scaling($w,current) [expr {$scaling($w,current)-1.0}]

    ReorderChartItems $w

    return $items
}

# DrawGanttConnect --
#    Draw a connection between two entries
# Arguments:
#    w           Name of the canvas
#    from        The from item
#    to          The to item
# Result:
#    List of item numbers, for further manipulation
# Side effects:
#    Arrow drawn in canvas
#
proc DrawGanttConnect { w from to } {
    global settings
    global data_series
    global scaling

    foreach {xf1 yf1 xf2 yf2} [$w coords [lindex $from 2]] {break}
    foreach {xt1 yt1 xt2 yt2} [$w coords [lindex $to   1]] {break}

    set yfc [expr {($yf1+$yf2)/2.0}]
    set ytc [expr {($yt1+$yt2)/2.0}]

    if { $xf2 > $xf1-15 } {
        set coords [list $xf2             $yfc            \
                         [expr {$xf2+5}]  $yfc            \
                         [expr {$xf2+5}]  [expr {$yf2+5}] \
                         [expr {$xt1-10}] [expr {$yf2+5}] \
                         [expr {$xt1-10}] $ytc            \
                         $xt1             $ytc            ]
    } else {
        set coords [list $xf2             $yfc            \
                         [expr {$xf2+5}]  $yfc            \
                         [expr {$xt2+5}]  $ytc            \
                         $xt1             $ytc            ]
    }

    ReorderChartItems $w

    return [$w create line $coords -arrow last -tag {vertscroll horizscroll below}]
}

# DrawGanttSummary --
#    Draw a summary entry
# Arguments:
#    w           Name of the canvas
#    text        Text to describe the summary
#    args        List of items belonging to the summary
# Result:
#    List of canvas items making up the summary
# Side effects:
#    Items are shifted down to make room for the summary
#
proc DrawGanttSummary { w text args } {
    global settings
    global data_series
    global scaling

    #
    # Determine the coordinates of the summary bar
    #
    set xmin {}
    set xmax {}
    set ymin {}
    set ymax {}
    foreach entry $args {
        foreach {x1 y1}             [$w coords [lindex $entry 1]] {break}
        foreach {dummy dummy x2 y2} [$w coords [lindex $entry 2]] {break}

        if { $xmin == {} || $xmin > $x1 } { set xmin $x1 }
        if { $xmax == {} || $xmax < $x2 } { set xmax $x2 }
        if { $ymin == {} || $ymin > $y1 } {
            set ymin  $y1
            set yminb $y2
        }
    }

    #
    # Compute the vertical shift
    #
    set yfirst $scaling($w,ymin)
    set ynext  [expr {$yfirst-1.0}]
    foreach {x y1} [coordsToPixel $w $scaling($w,xmin) $yfirst] {break}
    foreach {x y2} [coordsToPixel $w $scaling($w,xmin) $ynext ] {break}
    set dy [expr {$y2-$y1}]

    #
    # Shift the items
    #
    foreach entry $args {
        foreach item $entry {
            $w move $item 0 $dy
        }
    }

    #
    # Draw the summary text first
    #
    set ytext [expr {($ymin+$yminb)/2.0}]
    set ymin  [expr {$ymin+0.3*$dy}]

    set items {}
    lappend items \
        [$w create text 5 $ytext -text $text -anchor w -tag {summary vertscroll above} \
              -font $settings($w,font,summary)]
        # Colour text?

    #
    # Draw the bar
    #
    set coords [list [expr {$xmin-5}] [expr {$ymin-5}]  \
                     [expr {$xmax+5}] [expr {$ymin-5}]  \
                     [expr {$xmax+5}] [expr {$ymin+5}]  \
                     $xmax            [expr {$ymin+10}] \
                     [expr {$xmax-5}] [expr {$ymin+5}]  \
                     [expr {$xmin+5}] [expr {$ymin+5}]  \
                     $xmin            [expr {$ymin+10}] \
                     [expr {$xmin-5}] [expr {$ymin+5}]  ]

    lappend items \
        [$w create polygon $coords -tag {summarybar vertscroll horizscroll below} \
              -fill $settings($w,color,summarybar)]

    set scaling($w,current) [expr {$scaling($w,current)-1.0}]

    ReorderChartItems $w

    return $items
}


# plotobject.tcl --
#     Routine to plot arbitrary canvas items into plots
#

#
# Settings and variable for the DrawObject method
#
# Possible standard canvas item types
#
set canvasObject(StandardTypes) {arc line oval polygon rectangle text bitmap image window}

#
# Additional custom item types
#
set canvasObject(CustomTypes) {circle dot cross}

#
# All item types together
#
set canvasObject(AllTypes) [list]
foreach cElement $canvasObject(StandardTypes) {
    lappend canvasObject(AllTypes) $cElement
}
foreach cElement $canvasObject(CustomTypes) {
    lappend canvasObject(AllTypes)  $cElement
}
foreach {itemType ignoredOptions mappedOptions defaultValues} {
    arc
        {-symbol -type -filled -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-color -outline -colour -outline -fillcolor -fill}
        {}

    line
        {-symbol -type -filled -fillcolour -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-color -fill -colour -fill}
        {}

    oval
        {-symbol -type -filled -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-color -outline -colour -outline -fillcolor -fill}
        {}

    polygon
        {-symbol -type -filled -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-color -outline -colour -outline -fillcolor -fill}
        {}

    rectangle
        {-symbol -type -filled -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-color -outline -colour -outline -fillcolor -fill}
        {}

    text
        {-symbol -type -filled -fillcolour -boxwidth -width -whisker -whiskerwidth -mediancolour -medianwidth}
        {-colour -fill -color -fill}
        {}

    bitmap
        {-color -colour -symbol -type -filled -fillcolour -boxwidth -width -whisker -whiskerwidth -mediancolour -medianwidth}
        {}
        {}

    image
        {-color -colour -symbol -type -filled -fillcolour -boxwidth -width -whisker -whiskerwidth -mediancolour -medianwidth}
        {}
        {}

    window
        {-color -colour -symbol -type -filled -fillcolour -boxwidth -width -whisker -whiskerwidth -mediancolour -medianwidth}
        {}
        {}

    circle
        {-symbol -type -filled -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-colour -color -fillcolour -fillcolor -width -diameter}
        {-fillcolor {} -color black -diameter 10 -width 1}

    dot
        {-symbol -type -filled -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-colour -color -fillcolor -color -width -diameter}
        {-diameter 1 -color black}

    cross
        {-symbol -type -filled -boxwidth -whisker -whiskerwidth -mediancolour -medianwidth}
        {-colour -color -fillcolor -color}
        {-diameter 10 -color black -width 1 -capstyle butt}
} {
    #
    # These options from the series are ignored in the corresponding canvas item:
    #
    set canvasObject($itemType,ignored) $ignoredOptions

    #
    # These are a mapping from series/object option names to canvas item type names:
    #
    set canvasObject($itemType,mapping) $mappedOptions

    #
    # This is a list of object options and their default values:
    #
    set canvasObject($itemType,defaults) $defaultValues
}

# DrawObject --
#     Draw some canvas item onto the chart using chart coordinates
#
# Arguments:
#     w              Name of the canvas
#     item           Type of item
#     series         Name of the plotting series, used for default drawing options
#     args           List holding coordinates as the first elements of args (only numerical values)
#                    and additional configuration option value pairs thereafter
#                    (no numerical options; according to the canvas item)
#
# Result:
#     Id of the newly created canvas item
#
# Note: The special construct of 'args' makes it possible to
#       specify the coords as one list or as single arguments
#       just like the canvas items do
#
proc DrawObject {w item series args} {
    global data_series
    global canvasObject
    global config

    #
    # check for existent object types
    #
    if {[lsearch -exact $canvasObject(AllTypes) $item] < 0} {
            return -code error "no such canvas object: $item"
    }

    #
    # Split coords from args
    #
    if {[llength [lindex $args 0]] > 1} {
        #
        # Coordinates specified as one list:
        #
        set coords [lindex $args 0]
        set arguments [lrange $args 1 end]
    } else {
        #
        # Coordinates specified as single args -> find first non-numerical arg:
        # (the following is not strictly correct, but will do the job in this case)
        #
        set startIndex [lsearch -regexp -not $args {^[-+]?\.?[0-9]+}]
        switch $startIndex  {
            0 {return -code error "no coordinates given for $item object"}
            -1 {
                set arguments {}
                set coords $args
            }
            default {
                set arguments [lrange $args $startIndex end]
                incr startIndex -1
                set coords [lrange $args 0 $startIndex]
            }
        }
    }

    #
    # Transform coodinates into pixels:
    #
    if {[info exists config($w,object,transposecoordinates)] && $config($w,object,transposecoordinates)} {
        #
        # Transposed coordinates
        #
        foreach {y x} $coords {
            foreach {pxcrd pycrd} [coordsToPixel $w $x $y] {break}
            lappend pcoords $pxcrd $pycrd
        }
    } else {
        foreach {x y} $coords {
            foreach {pxcrd pycrd} [coordsToPixel $w $x $y] {break}
            lappend pcoords $pxcrd $pycrd
        }
    }

    #
    # Initialize with default options (only applicable to custom canvas objects)
    #
    if {[lsearch -exact $canvasObject(CustomTypes) $item] >= 0} {
        array set options $canvasObject($item,defaults)
    }

    #
    # Inherit options from the specified series
    #
    foreach key [array names data_series $w,$series,*] {
        set opt [lindex [split $key ,] end]

        #
        # Ignore non-options in data_series:
        #
        if {[string index $opt 0] ne "-"} {
            continue
        }

        #
        # Ignore non-existant canvas item option:
        #
        if {[lsearch -exact $canvasObject($item,ignored) $opt] >= 0} {
            continue
        }

        #
        # Map option to the corresponding canvas item type option:
        #
        set opt [string map $canvasObject($item,mapping) $opt]

        #
        # Finally save the option:
        #
        set options($opt) $data_series($key)
    }

    #
    # Load user specied options (merging with existing options)
    # and again map to the corresponding canvas item type options
    #
    foreach {userOpt userVal} $arguments {
            set userOpt [string map $canvasObject($item,mapping) $userOpt]
            set options($userOpt) $userVal
    }

    #
    # Create the item
    #
    if {[lsearch -exact $canvasObject(StandardTypes) $item] >= 0} {
        set id [$w create $item $pcoords]

        #
        # configure the item accordingly:
        #
        foreach {option value} [array get options] {
            $w itemconfigure $id $option $value
        }
    } else {
        set diff [expr {$options(-diameter)/2.0}]
        foreach {pxcrd pycrd} $pcoords {break}
        set pxcrd1 [expr {$pxcrd - $diff}]
        set pycrd1 [expr {$pycrd + $diff}]
        set pxcrd2 [expr {$pxcrd + $diff}]
        set pycrd2 [expr {$pycrd - $diff}]
        switch $item {
            circle {
                set id [$w create oval $pxcrd1 $pycrd1 $pxcrd2 $pycrd2 \
                        -fill $options(-fillcolor) -outline $options(-color) -width $options(-width)]
            }
            dot {
                set id [$w create oval $pxcrd1 $pycrd1 $pxcrd2 $pycrd2 -fill $options(-color) -outline {}]
            }
            cross {
                set id [$w create line $pxcrd1 $pycrd $pxcrd2 $pycrd \
                        -fill $options(-color) -width $options(-width) -capstyle $options(-capstyle)]
                set tag canvCross_$id
                $w itemconfigure $id -tags $tag
                $w create line $pxcrd $pycrd1 $pxcrd $pycrd2 \
                        -fill $options(-color) -width $options(-width) -tags $tag -capstyle $options(-capstyle)
                set id $tag
            }
        }
    }
    # add the tag 'object'
    $w addtag object withtag $id
    # return the canvas item id or tag, so the user can further manupulate it:
    return $id
}


# plotpack.tcl --
#     Implement a pack-like geometry manager for Plotchart
#
#     Note:
#     The canvas:* procedures are taken directly from the Wiki,
#     these procedures were written by Maurice (ulis) Bredelet
#     I have not changed the formatting or the naming convention,
#     as a small token of my appreciation for his Tcl work
#     - he died in February 2008.
#

# GetCanvas --
#     Destill the name of the canvas from the plot command
#
# Arguments:
#     cmd             Plot command
#
# Result:
#     Name of the widget
#
proc GetCanvas {cmd} {
    regsub {^[^_]+_} $cmd "" w
    return $w
}

# plotpack --
#     Copy an existing plot/chart into another canvas widget
#
# Arguments:
#     w               Canvas widget to copy to
#     dir             Direction to attach the new plot to the existing contents
#     args            List of plots/charts to be copied
#
# Result:
#     None
#
proc plotpack {w dir args} {
    global packing

    if { ![info exists packing($w,top)] } {
        set packing($w,top)    0
        set packing($w,left)   0
        set packing($w,right)  [WidthCanvas  $w]
        set packing($w,bottom) [HeightCanvas $w]
    }
    set top    $packing($w,top)
    set left   $packing($w,left)
    set right  $packing($w,right)
    set bottom $packing($w,bottom)

    foreach p $args {
        set save [canvas:save [GetCanvas $p]]
        switch -- $dir {
            "top" {
                 set xmove 0
                 set ymove $top
                 canvas:restore $w $save
                 $w move __NEW__ $xmove $ymove
                 $w dtag all __NEW__
                 set cwidth [WidthCanvas [GetCanvas $p]]
                 if { $left < $cwidth } {
                     set left $cwidth
                 }
                 set top  [expr {$top+[HeightCanvas [GetCanvas $p]]}]
            }
            "bottom" {
                 set xmove 0
                 set ymove [expr {$bottom-[HeightCanvas [GetCanvas $p]]}]
                 canvas:restore $w $save
                 $w move __NEW__ $xmove $ymove
                 $w dtag all __NEW__
                 set cwidth [WidthCanvas [GetCanvas $p]]
                 if { $left < $cwidth } {
                     set left $cwidth
                 }
                 set bottom $ymove
            }
            "left" {
                 set xmove $left
                 set ymove 0
                 canvas:restore $w $save
                 $w move __NEW__ $xmove $ymove
                 $w dtag all __NEW__
                 set left [expr {$left+[WidthCanvas [GetCanvas $p]]}]
                 set cheight [HeightCanvas [GetCanvas $p]]
                 if { $top < $cheight } {
                     set top $cheight
                 }
            }
            "right" {
                 set xmove [expr {$right-[WidthCanvas [GetCanvas $p]]}]
                 set ymove 0
                 canvas:restore $w $save
                 $w move __NEW__ $xmove $ymove
                 $w dtag all __NEW__
                 set right $xmove
                 if { $top < $cheight } {
                     set top $cheight
                 }
            }
        }
    }
    set packing($w,top)    $top
    set packing($w,left)   $left
    set packing($w,right)  $right
    set packing($w,bottom) $bottom
}

# canvas:* --
#     Procedures for copying the contents of a canvas widget - by "ulis"
#

# ==============================
#
#   clone a canvas widget
#
# ==============================

# ----------
#  canvas:clone proc
# ----------
# parm1: canvas widget
# parm2: clone canvas widget
# ----------

proc canvas:clone {canvas clone} { canvas:restore $clone [canvas:save $canvas] }

# ----------
#  options proc
#
#  return non empty options
# ----------
# parm: options list
# ----------
# return: non empty options list
# ----------

proc options {options} \
{
  set res {}
  foreach option $options \
  {
    set key   [lindex $option 0]
    set value [lindex $option 4]
    if {$value != ""} { lappend res [list $key $value] }
  }
  return $res
}

# ----------
#  canvas:save proc
#
#  serialize a canvas widget
# ----------
# parm1: canvas widget path
# ----------
# return: serialized widget
# ----------

proc canvas:save {w} \
{
  # canvas name
  lappend save $w
  # canvas option
  lappend save [options [$w configure]]
  # canvas focus
  lappend save [$w focus]
  # canvas items
  foreach id [$w find all] \
  {
    set item {}
    # type & id
    set type [$w type $id]
    lappend item [list $type $id]
    # coords
    lappend item [$w coords $id]
    # tags
    set tags [concat __NEW__ [$w gettags $id]] ;# AM: My change
    lappend item $tags
    # binds
    set binds {}
      # id binds
    set events [$w bind $id]
    foreach event $events \
    { lappend binds [list $id $event [$w bind $id $event]] }
      # tags binds
    foreach tag $tags \
    {
      set events [$w bind $tag]
      foreach event $events \
      { lappend binds [list $tag $event [$w bind $tag $event]] }
    }
    lappend item $binds
    # options
    lappend item [options [$w itemconfigure $id]]
    # type specifics
    set specifics {}
    switch -- $type {
      arc       {}
      bitmap    {}
      image     \
      {
        # image name
        set iname [$w itemcget $id -image]
        lappend specifics $iname
        # image type
        lappend specifics [image type $iname]
        # image options
        lappend specifics [options [$iname configure]]
      }
      line      {}
      oval      {}
      polygon   {}
      rectangle {}
      text      \
      {
        foreach index {insert sel.first sel.last} \
        {
          # text indexes
          catch \
          { lappend specifics [$w index $id $index] }
        }
      }
      window    \
      {
        # window name
        set wname [$w itemcget $id -window]
        lappend specifics $wname
        # window type
        lappend specifics [string tolower [winfo class $wname]]
        # window options
        lappend specifics [options [$wname configure]]
      }
    }
    lappend item $specifics
    lappend save $item
  }
  # return serialized canvas
  return $save
}

# ----------
#  canvas:restore proc
#
#  restore a serialized canvas widget
# ----------
# parm1: canvas widget path
# parm2: serialized widget to restore
# ----------

proc canvas:restore {w save} \
{
  # create canvas options
  # eval canvas $w [join [lindex $save 1]] ;# AM: My change
  # items
  foreach item [lrange $save 3 end] \
  {
    foreach {typeid coords tags binds options specifics} $item \
    {
      # get type
      set type [lindex $typeid 0]
      # create bitmap or window
      switch -- $type {
        image   \
        {
          foreach {iname itype ioptions} $specifics break
          if {![image inuse $iname]} \
          { eval image create $itype $iname [join $ioptions] }
        }
        window  \
        {
          foreach {wname wtype woptions} $specifics break
          if {![winfo exists $wname]} \
          { eval $wtype $wname [join $woptions] }
          raise $wname
        }
      }
      # create item
      set id [eval $w create $type $coords [join $options]]
      $w itemconfigure $id -tags $tags ;# AM: "options" may contain the old list of tags
      # item bindings
      foreach bind $binds \
      {
        foreach {id event script} $bind { $w bind $id $event $script }
      }
      # item specifics
      if {$specifics != ""} \
      {
        switch -- $type {
          text    \
          {
            foreach {insert sel.first sel.last} $specifics break
            $w icursor $id $insert
            if {${sel.first} != ""} \
            {
              $w select from $id ${sel.first}
              $w select to   $id ${sel.last}
            }
          }
        }
      }
    }
  }
  # focused item
  set focus [lindex $save 2]
  if {$focus != ""} \
  {
    $w focus [lindex $save 2]
    focus -force $w
  }
  # return path
  return $w
}

# ----------
#  canvas:dump proc
#
#  dump a canvas widget
# ----------
# parm: canvas widget path
# ----------
# return: widget dump
# ----------

proc canvas:dump {w} \
{
  # canvas name
  lappend res [lindex $w 0]
  # canvas options
  foreach option [lindex $w 1] { lappend res [join $option \t] }
  # focused item
  lappend res [join [lindex $w 2] \t]
  # items
  foreach item [lrange $w 3 end] \
  {
    foreach {type coords tags binds options specifics} $item \
    {
      # item type
      lappend res [join $type \t]
      # item coords
      lappend res \tcoords\t$coords
      # item tags
      lappend res \ttags\t$tags
      # item bindings
      lappend res \tbinds
      foreach bind $binds { lappend res \t\t$bind }
      # item options
      lappend res \toptions
      foreach option $options \
      {
        set key [lindex $option 0]
        set value [lindex $option 1]
        lappend res \t\t$key\t$value
      }
      # item specifics
      if {$specifics != ""} \
      {
        lappend res \tspecifics
        foreach specific $specifics \
        {
          if {[llength $specific] == 1}  { lappend res \t\t$specific } \
          else { foreach token $specific { lappend res \t\t$token } }
        }
      }
    }
  }
  # return dump
  return [join $res \n]
}


# plotpriv.tcl --
#    Facilities to draw simple plots in a dedicated canvas
#
# Note:
#    This source file contains the private functions.
#    It is the companion of "plotchart.tcl"
#

# WidthCanvas --
#    Return the width of the canvas
# Arguments:
#    w           Name of the canvas
#    useref      Use reference width if it exists
# Result:
#    Width in pixels
#
proc WidthCanvas {w {useref 1}} {
    global scaling

    set ref $scaling($w,reference)

    if { [string match {[0-9]*} $w] } {
        set w [string range $w 2 end]
    }

    if { [info exists scaling($ref,refwidth)] && $useref } {
        set width $scaling($ref,refwidth)
    } else {
        set width [winfo width $w]

        if { $width < 10 } {
            set width [$w cget -width]
        }
    }
    incr width -[$w cget -borderwidth]

    return $width
}

# HeightCanvas --
#    Return the height of the canvas
# Arguments:
#    w           Name of the canvas
#    useref      Use reference height if it exists
# Result:
#    Height in pixels
#
proc HeightCanvas {w {useref 1}} {
    global scaling

    set ref $scaling($w,reference)

    if { [string match {[0-9]*} $w] } {
        set w [string range $w 2 end]
    }

    if { [info exists scaling($ref,refheight)] && $useref } {
        set height $scaling($ref,refheight)
    } else {
        set height [winfo height $w]
        if { $height < 10 } {
            set height [$w cget -height]
        }
    }
    incr height -[$w cget -borderwidth]
    return $height
}

# GetCanvas --
#    Return the widget name for the canvas
# Arguments:
#    w           Name of the canvas
# Result:
#    Height in pixels
#
proc GetCanvas {w} {

    return $w
}

# SavePlot --
#    Save the plot/chart to a PostScript file (using default options)
# Arguments:
#    w           Name of the canvas
#    filename    Name of the file to write
#    args        Additional optional arguments as ?option value ... ...?
#                     -format name            a file format different from PostScript to save the plot into
#                     -plotregion region      define what region of the plot to save
#                                             ('bbox' saves all within the bbox, 'window' saves what is visible in the current window)
# Result:
#    None
# Side effect:
#    A (new) PostScript file or other file format
#
proc SavePlot { w filename args } {
    array set options {-format ps -plotregion window}
    array set options $args
    foreach {opt val} $args {
        if {$opt ni {-format -plotregion}} {
            return -code error "Unknown option: $opt - must be: -format or -plotregion"
        }
    }
    if {$options(-plotregion) eq "bbox" && $options(-format) ne ""ps} {
        return -code error "'-plotregion bbox' can only be used together with '-format ps'"
    }
    if {$options(-format) ne "ps"} {
        package require Img
        #
        # This is a kludge:
        # Somehow tkwait does not always work (on Windows XP, that is)
        #
        raise [winfo toplevel $w]
        # tkwait visibility [winfo toplevel $w]
        after 2000 {set waited 0}
        vwait waited
        set img [image create photo -data $w -format window]
        $img write $filename -format $options(-format)
    } else {
        #
        # Wait for the canvas to become visible - just in case.
        # Then write the file
        #
        update idletasks
        if {$options(-plotregion) eq "window"} {
            $w postscript -file $filename
        } elseif {$options(-plotregion) eq "bbox"} {
            lassign [$w bbox all] xmin ymin xmax ymax
            # '+2' here, because the bbox from the canvas is only approximate
            # and may be a tiny bit too small sometimes, especially with text
            # at the edges
            set width  [expr {$xmax-$xmin+2}]
            set height [expr {$ymax-$ymin+2}]
            $w postscript -file $filename -x $xmin -y $ymin -height $height -width $width
        } else {
            return -code error "Unknown value '$options(-plotregion)' for -plotregion option"
        }
    }
}

# DetermineFromAxesBox --
#    Determine the layout from the information in an axes box
# Arguments:
#    axesbox           Data defining the axes box
#    pxdef             Default minimum x-coordinate
#    pydef             Default minimum y-coordinate
#    margin_right      Margin right
#    margin_bottom     Margin bottom
# Result:
#    List of four values
#
proc DetermineFromAxesBox {axesbox pxdef pydef margin_right margin_bottom} {
    global scaling

    foreach {ref_plot dir upperx uppery axis_width axis_height} $axesbox {break}

    set pos      [string first _ $ref_plot]
    set ref_plot [string range $ref_plot [expr {$pos+1}] end]

    set refxmin $scaling($ref_plot,pxmin)
    set refymin $scaling($ref_plot,pymin)
    set refxmax $scaling($ref_plot,pxmax)
    set refymax $scaling($ref_plot,pymax)

    switch -- [string toupper $dir] {
        "N" {
            set pxmin [expr {($refxmin + $refxmax)/2}]
            set pymin $refymin
        }
        "NW" {
            set pxmin $refxmin
            set pymin $refymin
        }
        "NE" {
            set pxmin $refxmax
            set pymin $refymin
        }
        "E" {
            set pxmin $refxmax
            set pymin [expr {($refymin + $refymax)/2}]
        }
        "SE" {
            set pxmin $refxmax
            set pymin $refymax
        }
        "S" {
            set pxmin [expr {($refxmin + $refxmax)/2}]
            set pymin $refymax
        }
        "SW" {
            set pxmin $refxmin
            set pymin $refymax
        }
        "W" {
            set pxmin $refxmin
            set pymin [expr {($refymin + $refymax)/2}]
        }
        "C" {
            set pxmin [expr {($refxmin + $refxmax)/2}]
            set pymin [expr {($refymin + $refymax)/2}]
        }
        default {
            set pxmin $refxmin
            set pymin $refymin
        }
    }
    set pxmin  [expr {$pxmin       - $pxdef + $upperx}]
    set pymin  [expr {$pymin       - $pydef - $uppery}]        ;# Because of inversion of y-axis
    set width  [expr {$axis_width  + $pxdef + $margin_right}]
    set height [expr {$axis_height + $pydef + $margin_bottom}]

    return [list $pxmin $pymin $width $height]
}

# MarginsRectangle --
#    Determine the margins for a rectangular plot/chart
# Arguments:
#    w           Name of the plot
#    argv        List of options
#    notext      Number of lines of text to make room for at the top
#                (default: 2.0)
#    text_width  Number of characters to be displayed at most on left
#                (default: 8)
# Result:
#    List of four values
#
proc MarginsRectangle { w argv {notext 2.0} {text_width 8}} {
    global config
    global scaling

    if { [string match {[0-9]*} $w] } {
        set c [string range $w 2 end]
    } else {
        set c $w
    }
    set char_width  $config(font,char_width)
    set char_height $config(font,char_height)
    set config($w,font,char_width)  $char_width
    set config($w,font,char_height) $char_height

    foreach {char_width char_height} [FontMetrics $w] {break}
    set margin_right [expr {$char_width * 4}]
    if { $margin_right < $config($w,margin,right) } {
        set margin_right $config($w,margin,right)
    }
    set margin_bottom [expr {$char_height * 2 + 2}]
    if { $margin_bottom < $config($w,margin,bottom) } {
        set margin_bottom $config($w,margin,bottom)
    }

    set pxmin [expr {$char_width*$text_width}]
    if { $pxmin < $config($w,margin,left) } {
        set pxmin $config($w,margin,left)
    }
    set pymin [expr {int($char_height*$notext) + [$w cget -borderwidth]}]
    if { $pymin < $config($w,margin,top) } {
        set pymin $config($w,margin,top)
    }

    array set options $argv
    if {[info exists options(-box)]} {
        foreach {offx offy width height} $options(-box) {break}
        if { $offy == 0 } {
            set offy [$w cget -borderwidth]
        }
        set scaling($w,reference) $w
        set scaling($w,refx)      $offx
        set scaling($w,refy)      $offy
        set scaling($w,refwidth)  [expr {$offx + $width}]
        set scaling($w,refheight) [expr {$offy + $height}]
    } elseif {[info exists options(-axesbox)]} {
        foreach {offx offy width height} [DetermineFromAxesBox $options(-axesbox) $pxmin $pymin $margin_right $margin_bottom] {break}
        if { $offy == 0 } {
            set offy [$w cget -borderwidth]
        }
        set ref_plot [lindex $options(-axesbox) 0]
        set pos      [string first _ $ref_plot]
        set ref      [string range $ref_plot [expr {$pos+1}] end]
        set scaling($w,reference) $scaling($ref,reference) ;# A chain of references is possible!
    } else {
        set scaling($w,reference) $w
        set offx   0
        set offy   [$w cget -borderwidth]
        set width  [WidthCanvas $w]
        set height [HeightCanvas $w]
        set scaling($w,refx)      0
        set scaling($w,refy)      0
        set scaling($w,refwidth)  $width
        set scaling($w,refheight) $height
    }

    set pxmin [expr {$offx + $pxmin}]
    set pymin [expr {$offy + $pymin}]

    set pxmax [expr {$offx + $width  - $margin_right}]
    set pymax [expr {$offy + $height - $margin_bottom}]

    set ref $scaling($w,reference)

    if { ! [info exists scaling($ref,boxxmin)] } {
        set scaling($ref,boxxmin) $pxmin
        set scaling($ref,boxymin) $pymin
        set scaling($ref,boxxmax) $pxmax
        set scaling($ref,boxymax) $pymax
        set scaling($ref,refx)    $offx
        set scaling($ref,refy)    $offy
    } else {
        Minset scaling($ref,boxxmin) $pxmin
        Minset scaling($ref,boxymin) $pymin
        Maxset scaling($ref,boxxmax) $pxmax
        Maxset scaling($ref,boxymax) $pymax
        Minset scaling($ref,refx)    $offx
        Minset scaling($ref,refy)    $offy
    }

    return [list $pxmin $pymin $pxmax $pymax]
}

# Minset, Maxset --
#     Auxiliary procedures to conditionally update a variable
# Arguments:
#     varName    Name of the variable
#     newValue   New value
#
proc Minset {varName newValue} {
    upvar 1 $varName var

    if { $var > $newValue } {
        set var $newValue
    }
}
proc Maxset {varName newValue} {
    upvar 1 $varName var

    if { $var < $newValue } {
        set var $newValue
    }
}

# MarginsSquare --
#    Determine the margins for a square plot/chart
# Arguments:
#    w           Name of the canvas
#    notext      Number of lines of text to make room for at the top
#                (default: 2.0)
#    text_width  Number of characters to be displayed at most on left
#                (default: 8)
# Result:
#    List of four values
#
proc MarginsSquare { w {notext 2.0} {text_width 8}} {
    global config
    global scaling

    set scaling($w,reference) $w
    set scaling($w,refx)      0
    set scaling($w,refy)      [$w cget -borderwidth]
    set scaling($w,refwidth)  [WidthCanvas $w]
    set scaling($w,refheight) [HeightCanvas $w]

    set char_width  $config(font,char_width)
    set char_height $config(font,char_height)
    set config($w,font,char_width)  $char_width
    set config($w,font,char_height) $char_height

    foreach {char_width char_height} [FontMetrics $w] {break}
    set margin_right [expr {$char_width * 4}]
    if { $margin_right < $config($w,margin,right) } {
        set margin_right $config($w,margin,right)
    }
    set margin_bottom [expr {$char_height * 2 + 2}]
    if { $margin_bottom < $config($w,margin,bottom) } {
        set margin_bottom $config($w,margin,bottom)
    }

    set pxmin [expr {$char_width*$text_width}]
    if { $pxmin < $config($w,margin,left) } {
        set pxmin $config($w,margin,left)
    }
    set pymin [expr {int($char_height*$notext)}]
    if { $pymin < $config($w,margin,top) } {
        set pymin $config($w,margin,top)
    }
    set pxmax [expr {[WidthCanvas $w]  - $margin_right}]
    set pymax [expr {[HeightCanvas $w] - $margin_bottom}]

    if { $pxmax-$pxmin > $pymax-$pymin } {
        set pxmax [expr {$pxmin + ($pymax - $pymin)}]
    } else {
        set pymax [expr {$pymin + ($pxmax - $pxmin)}]
    }

    return [list $pxmin $pymin $pxmax $pymax]
}

# MarginsCircle --
#    Determine the margins for a circular plot/chart
# Arguments:
#    w           Name of the canvas
#    args        additional arguments for placement of plot,
#                currently: '-box', '-reference', and '-units'
# Result:
#    List of four values giving the pixel coordinates
#    of the boundary of the piechart
#
proc MarginsCircle { w args } {
   global scaling

   array set options $args
   if { [info exists options(-box)] } {
       set scaling($w,reference) $w
   } elseif { [info exists options(-reference)] } {
       set ref_plot [lindex $options(-reference) 0]
       set pos      [string first _ $ref_plot]
       set ref      [string range $ref_plot [expr {$pos+1}] end]
       set scaling($w,reference) $scaling($ref,reference)
   } else {
       set scaling($w,reference) $w
   }

   set pxmin 80
   set pymin 30
   set pxmax [expr {[WidthCanvas $w]  - 80}]
   set pymax [expr {[HeightCanvas $w] - 30}]
   #set pxmax [expr {[$w cget -width]  - 80}]
   #set pymax [expr {[$w cget -height] - 30}]

   # width (dx) and height (dy) of plot region in pixels:
   if {[info exists options(-units)]} {
      # refUnitX, refUnitY - size of one world coordinate unit in the piechart,
      #      given as canvas coords (can also be m,c,i,p units)
      # Note: the pie is always 2 world coordinate units in diameter
      #
      lassign $options(-units) refUnitX refUnitY
      set wc [string range $w 2 end]
      set refUnitX [winfo pixels $wc $refUnitX]
      set refUnitY [winfo pixels $wc $refUnitY]
      set dx [expr {$refUnitX * 2}]
      set dy [expr {$refUnitY * 2}]
   } else {
      set dx [expr {$pxmax-$pxmin+1}]
      set dy [expr {$pymax-$pymin+1}]
      # make sure, we get a centred circle:
      if {$dx < $dy} {
          set dy $dx
      } else {
          set dx $dy
      }
      set pxmin [expr {($pxmin+$pxmax-$dx)/2}]
   }

   # new default coords of plotting region:
   set pxmax [expr {$pxmin + $dx}]
   set pymax [expr {$pymin + $dy}]

   if {[info exists options(-reference)]} {
        # refPlot - name of the plot referring to
        # refX - x world coordinate of center of new piechart in refPlot coordinate system
        # refY - see above, just for y
        #
        lassign $options(-reference) refPlot refX refY
        set pos [string first _ $refPlot]
        set refPlot [string range $refPlot [expr {$pos+1}] end]
        lassign [coordsToPixel $refPlot $refX $refY] refpx refpy
        if {$dx < $dy} {set delta [expr {$dx/2.0}]} else {set delta [expr {$dy/2.0}]}
        set pxmin [expr {$refpx - $delta}]
        set pxmax [expr {$refpx + $delta}]
        set pymin [expr {$refpy - $delta}]
        set pymax [expr {$refpy + $delta}]
   } elseif {[info exists options(-box)]} {
        # put the pie into the middle of the -box and make it
        # as large as possible, ignoring the labels for now,
        # that may be placed outside the box
        # Note: also ignores -units setting
        lassign $options(-box) pxmin pymin width height
        if {$height >= $width} {
            # place vertically in the middle of the -box
            if { $pxmin == 0 } {set pxmin [$w cget -borderwidth]}
            set pymin [expr {$pymin + ($height-$width)/2.0}]
            if { $pymin == 0 } {set pymin [$w cget -borderwidth]}
        } else {
            # place horizontally in the middle of the -box
            if { $pymin == 0 } {set pymin [$w cget -borderwidth]}
            set pxmin [expr {$pxmin + ($width-$height)/2.0}]
            if { $pxmin == 0 } {set pxmin [$w cget -borderwidth]}
        }
        # only take the smallest dimension to keep the pie a circle:
        if {$width < $height} {set height $width}
        if {$height < $width} {set width $height}
        set pxmax [expr {$pxmin + $width}]
        set pymax [expr {$pymin + $height}]

        set scaling($w,refx)      $refX
        set scaling($w,refy)      $refY
        set scaling($w,refwidth)  [expr {$refX + $width}]
        set scaling($w,refheight) [expr {$refY + $height}]
   } else {
        set scaling($w,refx)      0
        set scaling($w,refy)      [$w cget -borderwidth]
        set scaling($w,refwidth)  [WidthCanvas $w]
        set scaling($w,refheight) [HeightCanvas $w]
   }

   return [list $pxmin $pymin $pxmax $pymax]
}

# Margins3DPlot --
#    Determine the margins for a 3D plot
# Arguments:
#    w           Name of the canvas
# Result:
#    List of four values
#
proc Margins3DPlot { w } {
   global scaling

   set scaling($w,reference) $w
   set scaling($w,refx)      0
   set scaling($w,refy)      [$w cget -borderwidth]
   set scaling($w,refwidth)  [WidthCanvas $w]
   set scaling($w,refheight) [HeightCanvas $w]

   set yfract 0.33
   set zfract 0.50
   if { [info exists scaling($w,yfract)] } {
      set yfract $scaling($w,yfract)
   } else {
      set scaling($w,yfract) $yfract
   }
   if { [info exists scaling($w,zfract)] } {
      set zfract $scaling($w,zfract)
   } else {
      set scaling($w,zfract) $zfract
   }

   set yzwidth  [expr {(-120+[WidthCanvas $w])/(1.0+$yfract)}]
   set yzheight [expr {(-60+[HeightCanvas $w])/(1.0+$zfract)}]
   #set yzwidth  [expr {(-120+[$w cget -width])/(1.0+$yfract)}]
   #set yzheight [expr {(-60+[$w cget -height])/(1.0+$zfract)}]

   set pxmin    [expr {60+$yfract*$yzwidth}]
   set pxmax    [expr {[WidthCanvas $w] - 60}]
   #set pxmax    [expr {[$w cget -width] - 60}]
   set pymin    30
   set pymax    [expr {30+$yzheight}]

   return [list $pxmin $pymin $pxmax $pymax]
}

# GetPlotArea --
#    Return the area reserved for the plot
# Arguments:
#    w           Name of the canvas
# Result:
#    List of: (x,y) upper left, (x,y) lower right, width and height
#
proc GetPlotArea { w } {
   global scaling

   set width  [expr {$scaling($w,pxmax) - $scaling($w,pxmin) + 1}]
   set height [expr {$scaling($w,pymax) - $scaling($w,pymin) + 1}]

   return [list $scaling($w,pxmin) $scaling($w,pymin) $scaling($w,pxmax) $scaling($w,pymax) $width $height]
}

# SetColours --
#    Set the colours for those plots that treat them as a global resource
# Arguments:
#    w           Name of the canvas
#    args        List of colours to be used
# Result:
#    None
#
proc SetColours { w args } {
   global scaling

   set scaling($w,colours) $args
}

# CycleColours --
#    create cycling colours for those plots that treat them as a global resource
# Arguments:
#    colours     List of colours to be used. An empty list will activate to default colours
#    nr_data     Number of data records
# Result:
#    List of 'nr_data' colours to be used
#
proc CycleColours { colours nr_data } {
   if {![llength ${colours}]} {
       # force to most usable default colour list
       set colours {green blue red cyan yellow magenta}
   }

   if {[llength ${colours}] < ${nr_data}} {
   # cycle through colours
   set init_colours ${colours}
        set colours {}
        set pos 0
        for {set nr 0} {${nr} < ${nr_data}} {incr nr} {
            lappend colours [lindex ${init_colours} ${pos}]
            incr pos
            if {[llength ${init_colours}] <= ${pos}} {
                set pos 0
            }
   }
        if {[string equal [lindex ${colours} 0] [lindex ${colours} end]]} {
            # keep first and last colour different from selected colours
       #    this will /sometimes fail in cases with only one/two colours in list
       set colours [lreplace ${colours} end end [lindex ${colours} 1]]
        }
   }
   return ${colours}
}

# DataConfig --
#    Configure the data series
# Arguments:
#    w           Name of the canvas
#    series      Name of the series in question
#    args        Option and value pairs
# Result:
#    None
#
proc DataConfig { w series args } {
   global data_series
   global options
   global option_keys
   global option_values

   foreach {option value} $args {
      set idx [lsearch $options $option]
      if { $idx < 0 } {
         return -code error "Unknown or invalid option: $option (value: $value)"
      } else {
         set key [lindex $option_keys    $idx]
         set idx [lsearch $option_values $key]
         set values  [lindex $option_values [incr idx]]
         if { $values != "..." } {
            if { [lsearch $values $value] < 0 } {
               return -code error "Unknown or invalid value: $value for option $option - $values"
            }
         }
         set data_series($w,$series,$key) $value
      }
   }
}

# ScaleIsometric --
#    Determine the scaling for an isometric plot
# Arguments:
#    w           Name of the canvas
#    xmin        Minimum x coordinate
#    ymin        Minimum y coordinate
#    xmax        Maximum x coordinate
#    ymax        Maximum y coordinate
#                (default: 1.5)
# Result:
#    None
# Side effect:
#    Array with scaling parameters set
#
proc ScaleIsometric { w xmin ymin xmax ymax } {
   global scaling

   set pxmin $scaling($w,pxmin)
   set pymin $scaling($w,pymin)
   set pxmax $scaling($w,pxmax)
   set pymax $scaling($w,pymax)

   set dx [expr {double($xmax-$xmin)/($pxmax-$pxmin)}]
   set dy [expr {double($ymax-$ymin)/($pymax-$pymin)}]

   #
   # Which coordinate is dominant?
   #
   if { $dy < $dx } {
      set yminn [expr {0.5*($ymax+$ymin) - 0.5 * $dx * ($pymax-$pymin)}]
      set ymaxn [expr {0.5*($ymax+$ymin) + 0.5 * $dx * ($pymax-$pymin)}]
      set ymin  $yminn
      set ymax  $ymaxn
   } else {
      set xminn [expr {0.5*($xmax+$xmin) - 0.5 * $dy * ($pxmax-$pxmin)}]
      set xmaxn [expr {0.5*($xmax+$xmin) + 0.5 * $dy * ($pxmax-$pxmin)}]
      set xmin  $xminn
      set xmax  $xmaxn
   }

   worldCoordinates $w $xmin $ymin $xmax $ymax
}

# PlotHandler --
#    Handle the subcommands for an XY plot or chart
# Arguments:
#    type        Type of plot/chart
#    w           Name of the canvas
#    command     Subcommand or method to run
#    args        Data for the command
# Result:
#    Whatever returned by the subcommand
#
proc PlotHandler { type w command args } {
    global methodProc

    if { [info exists methodProc($type,$command)] } {
        if { [llength $methodProc($type,$command)] == 1 } {
            eval $methodProc($type,$command) $w $args
        } else {
            eval $methodProc($type,$command)_$w $w $args
        }
    } else {
        return -code error "No such method - $command"
    }
}

# DrawMask --
#    Draw the stuff that masks the data lines outside the graph
# Arguments:
#    w           Name of the canvas
# Result:
#    None
# Side effects:
#    Several polygons drawn in the background colour
#
proc DrawMask { w } {
    global scaling
    global config

    if { $config($w,mask,draw) == 0 } {
        return
    }

    if { [string match {[0-9]*} $w] } {
        set c [string range $w 2 end]
    } else {
        set c $w
    }

    set ref $scaling($w,reference)

    if { [info exists scaling($ref,boxxmin)] } {
        set pxmin  $scaling($ref,boxxmin)
        set pymin  $scaling($ref,boxymin)
        set pxmax  $scaling($ref,boxxmax)
        set pymax  $scaling($ref,boxymax)
        set offx   $scaling($ref,refx)
        set offy   $scaling($ref,refy)
    } else {
        set pxmin  [expr {$scaling($w,pxmin)-1}]
        set pymin  [expr {$scaling($w,pymin)-1}]
        set pxmax  $scaling($w,pxmax)
        set pymax  $scaling($w,pymax)
        set offx   0
        set offy   0
    }
    set width  [expr {[WidthCanvas  $w 0] + 1}]
    set height [expr {[HeightCanvas $w 0] + 1}]

    set colour $config($w,background,outercolor)

    #$w delete "mask && $w"
    $w delete "mask && $ref"
    $w create rectangle $offx  $offy  $pxmin $height -fill $colour -outline $colour -tag [list mask $ref]
    $w create rectangle $offx  $offy  $width $pymin  -fill $colour -outline $colour -tag [list mask $ref]
    $w create rectangle $offx  $pymax $width $height -fill $colour -outline $colour -tag [list mask $ref]
    $w create rectangle $pxmax $offy  $width $height -fill $colour -outline $colour -tag [list mask $ref]

    $w lower mask
}

# DrawScrollMask --
#    Draw the masking rectangles for a time or Gantt chart
# Arguments:
#    w           Name of the canvas
# Result:
#    None
# Side effects:
#    Several polygons drawn in the background colour, with appropriate
#    tags
#
proc DrawScrollMask { w } {
   global scaling
   global config

   set width  [expr {[WidthCanvas $w]  + 1}]
   set height [expr {[HeightCanvas $w] + 1}]
   set colour $config($w,background,outercolor)
   set pxmin  [expr {$scaling($w,pxmin)-1}]
   set pxmax  $scaling($w,pxmax)
   set pymin  [expr {$scaling($w,pymin)-1}]
   set pymax  $scaling($w,pymax)
   $w create rectangle 0      0      $pxmin $height -fill $colour -outline $colour -tag vertmask
   $w create rectangle 0      0      $width $pymin  -fill $colour -outline $colour -tag horizmask
   $w create rectangle 0      $pymax $width $height -fill $colour -outline $colour -tag horizmask
   $w create rectangle $pxmax 0      $width $height -fill $colour -outline $colour -tag vertmask

   $w create rectangle 0      0      $pxmin $pymin  -fill $colour -outline $colour -tag {topmask top}
   $w create rectangle $pxmax 0      $width $pymin  -fill $colour -outline $colour -tag {topmask top}

   $w lower topmask
   $w lower horizmask
   $w lower vertmask
}

# DrawTitle --
#    Draw the title
# Arguments:
#    w           Name of the canvas
#    title       Title to appear above the graph
#    position    Position of the title (default: center)
# Result:
#    None
# Side effects:
#    Text string drawn
#
proc DrawTitle { w title {position center}} {
    global scaling
    global config

    set ref    $scaling($w,reference)
    set offx   $scaling($ref,refx)
    set offy   $scaling($ref,refy)
    set width  [WidthCanvas $w]
    #set width  [$w cget -width]
    set pymin  $scaling($w,pymin)

    switch -- $position {
        "left" {
            set tx [expr {$offx + 3}]
            set anchor nw
        }
        "right" {
            set tx [expr {$width - 3}]
            set anchor ne
        }
        default {
            set tx [expr {($offx + $width)/2}]
            set anchor n
        }
    }

    $w delete "title_$anchor && $ref"
    set obj [$w create text $tx [expr {$offy + 3 + [$w cget -borderwidth]}] -text $title \
                -tags [list title title_$anchor $ref] -font $config($w,title,font) \
                -fill $config($w,title,textcolor) -anchor $anchor]

    set titlecolour $config($w,title,background)
    if { $titlecolour == "" } {
        set titlecolour $config($w,background,outercolor)
    }
    set bbox    [$w bbox $obj]
    set theight [lindex $bbox end]
    set bgobj [$w create rectangle $offx $offy $width $theight -fill $titlecolour -tag [list titlebackground $ref] -outline $titlecolour]
    $w raise titlebackground
    $w raise title
    $w raise ytext
}

# DrawData --
#    Draw the data in an XY-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        Next x coordinate
#    ycrd        Next y coordinate
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawData { w series xcrd ycrd } {
   global data_series
   global scaling

   #
   # Check for missing values
   #
   if { $xcrd == "" || $ycrd == "" } {
       unset -nocomplain data_series($w,$series,x)
       return
   }

   #
   # Draw the line piece
   #
   set colour "black"
   if { [info exists data_series($w,$series,-colour)] } {
      set colour $data_series($w,$series,-colour)
   }

   set type "line"
   if { [info exists data_series($w,$series,-type)] } {
      set type $data_series($w,$series,-type)
   }
   set filled "no"
   if { [info exists data_series($w,$series,-filled)] } {
      set filled $data_series($w,$series,-filled)
   }
   set fillcolour white
   if { [info exists data_series($w,$series,-fillcolour)] } {
      set fillcolour $data_series($w,$series,-fillcolour)
   }
   set width 1
   if { [info exists data_series($w,$series,-width)] } {
      set width $data_series($w,$series,-width)
   }

   foreach {pxcrd pycrd} [coordsToPixel $w $xcrd $ycrd] {break}

   if { [info exists data_series($w,$series,x)] } {
       set xold $data_series($w,$series,x)
       set yold $data_series($w,$series,y)
       foreach {pxold pyold} [coordsToPixel $w $xold $yold] {break}

       if { $filled ne "no" } {
           if { $filled eq "down" } {
               set pym $scaling($w,pymax)
           } else {
               set pym $scaling($w,pymin)
           }
           $w create polygon $pxold $pym $pxold $pyold $pxcrd $pycrd $pxcrd $pym \
               -fill $fillcolour -outline {} -width $width -tag [list data data_$series]
       }

       if { $type == "line" || $type == "both" } {
          $w create line $pxold $pyold $pxcrd $pycrd \
                         -fill $colour -width $width -tag [list data data_$series]
       }
   }

   if { $type == "symbol" || $type == "both" } {
      set symbol "dot"
      if { [info exists data_series($w,$series,-symbol)] } {
         set symbol $data_series($w,$series,-symbol)
      }
      DrawSymbolPixel $w $series $pxcrd $pycrd $symbol $colour [list "data" data_$series]
   }

   $w lower data

   set data_series($w,$series,x) $xcrd
   set data_series($w,$series,y) $ycrd
}

# DrawStripData --
#    Draw the data in a stripchart
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        Next x coordinate
#    ycrd        Next y coordinate
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawStripData { w series xcrd ycrd } {
   global data_series
   global scaling

   #
   # Check for missing values
   #
   if { $xcrd == "" || $ycrd == "" } {
       unset data_series($w,$series,x)
       return
   }

   if { $xcrd > $scaling($w,xmax) } {
      set xdelt $scaling($w,xdelt)
      set xmin  $scaling($w,xmin)
      set xmax  $scaling($w,xmax)

      set xminorg $xmin
      while { $xmax < $xcrd } {
         set xmin [expr {$xmin+$xdelt}]
         set xmax [expr {$xmax+$xdelt}]
      }
      set ymin  $scaling($w,ymin)
      set ymax  $scaling($w,ymax)

      worldCoordinates $w $xmin $ymin $xmax $ymax
      DrawXaxis $w $xmin $xmax $xdelt

      foreach {pxminorg pyminorg} [coordsToPixel $w $xminorg $ymin] {break}
      foreach {pxmin pymin}       [coordsToPixel $w $xmin    $ymin] {break}
      $w move data [expr {$pxminorg-$pxmin+1}] 0
   }

   DrawData $w $series $xcrd $ycrd
}

# DrawLogYData --
#    Draw the data in an X-logY-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        Next x coordinate
#    ycrd        Next y coordinate
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawLogYData { w series xcrd ycrd } {

    DrawData $w $series $xcrd [expr {log10($ycrd)}]
}

# DrawLogXData --
#    Draw the data in an logX-Y-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        Next x coordinate
#    ycrd        Next y coordinate
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawLogXData { w series xcrd ycrd } {

    DrawData $w $series [expr {log10($xcrd)}] $ycrd
}

# DrawLogXLogYData --
#    Draw the data in an logX-logY-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        Next x coordinate
#    ycrd        Next y coordinate
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawLogXLogYData { w series xcrd ycrd } {

    DrawData $w $series [expr {log10($xcrd)}] [expr {log10($ycrd)}]
}

# DrawInterval --
#    Draw the data as an error interval in an XY-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        X coordinate
#    ymin        Minimum y coordinate
#    ymax        Maximum y coordinate
#    ycentr      Central y coordinate (optional)
# Result:
#    None
# Side effects:
#    New interval drawn in canvas
#
proc DrawInterval { w series xcrd ymin ymax {ycentr {}} } {
   global data_series
   global scaling

   #
   # Check for missing values
   #
   if { $xcrd == "" || $ymin == "" || $ymax == "" } {
       return
   }

   #
   # Draw the line piece
   #
   set colour "black"
   if { [info exists data_series($w,$series,-colour)] } {
      set colour $data_series($w,$series,-colour)
   }

   foreach {pxcrd pymin} [coordsToPixel $w $xcrd $ymin] {break}
   foreach {pxcrd pymax} [coordsToPixel $w $xcrd $ymax] {break}
   if { $ycentr != "" } {
       foreach {pxcrd pycentr} [coordsToPixel $w $xcrd $ycentr] {break}
   }

   #
   # Draw the I-shape (note the asymmetry!)
   #
   $w create line $pxcrd $pymin $pxcrd $pymax \
                        -fill $colour -tag [list data data_$series]
   $w create line [expr {$pxcrd-3}] $pymin [expr {$pxcrd+4}] $pymin \
                        -fill $colour -tag [list data data_$series]
   $w create line [expr {$pxcrd-3}] $pymax [expr {$pxcrd+4}] $pymax \
                        -fill $colour -tag [list data data_$series]

   if { $ycentr != "" } {
      set symbol "dot"
      if { [info exists data_series($w,$series,-symbol)] } {
         set symbol $data_series($w,$series,-symbol)
      }
      DrawSymbolPixel $w $series $pxcrd $pycentr $symbol $colour [list data data_$series]
   }

   $w lower data
}

# DrawSymbolPixel --
#    Draw a symbol in an xy-plot, polar plot or stripchart
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    pxcrd       Next x (pixel) coordinate
#    pycrd       Next y (pixel) coordinate
#    symbol      What symbol to draw
#    colour      What colour to use
#    tag         What tag to use
# Result:
#    None
# Side effects:
#    New symbol drawn in canvas
#
proc DrawSymbolPixel { w series pxcrd pycrd symbol colour tag } {
   global data_series
   global scaling

   set radius 4
   if { [info exists data_series($w,$series,-radius)] } {
      set radius $data_series($w,$series,-radius)
   }

   set pxmin  [expr {$pxcrd - $radius}]
   set pxmax  [expr {$pxcrd + $radius}]
   set pymin  [expr {$pycrd - $radius}]
   set pymax  [expr {$pycrd + $radius}]

   switch -- $symbol {
   "plus"     { $w create line $pxmin $pycrd $pxmax $pycrd \
                               $pxcrd $pycrd $pxcrd $pymin \
                               $pxcrd $pymax \
                               -fill $colour -tag $tag \
                               -capstyle projecting
              }
   "cross"    { $w create line $pxmin $pymin $pxmax $pymax \
                               $pxcrd $pycrd $pxmax $pymin \
                               $pxmin $pymax \
                               -fill $colour -tag $tag \
                               -capstyle projecting
              }
   "circle"   { $w create oval $pxmin $pymin $pxmax $pymax \
                               -outline $colour -tag $tag
              }
   "dot"      { $w create oval $pxmin $pymin $pxmax $pymax \
                               -outline $colour -fill $colour -tag $tag
              }
   "up"       { $w create polygon $pxmin $pymax $pxmax $pymax \
                               $pxcrd $pymin \
                               -outline $colour -fill {} -tag $tag
              }
   "upfilled" { $w create polygon $pxmin $pymax $pxmax $pymax \
                              $pxcrd $pymin \
                              -outline $colour -fill $colour -tag $tag
              }
   "down"     { $w create polygon $pxmin $pymin $pxmax $pymin \
                              $pxcrd $pymax \
                              -outline $colour -fill {} -tag $tag
              }
   "downfilled" { $w create polygon $pxmin $pymin $pxmax $pymin \
                              $pxcrd $pymax \
                              -outline $colour -fill $colour -tag $tag
              }
   }
}

# DrawTimeData --
#    Draw the data in an TX-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    time        Next date/time value
#    xcrd        Next x coordinate (vertical axis)
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawTimeData { w series time xcrd } {
    DrawData $w $series [clock scan $time] $xcrd
}

# DetermineMedian --
#    Determine the median of a sorted list of values
# Arguments:
#    values      Sorted values
# Result:
#    Median value
#
proc DetermineMedian { values } {
    set length [llength $values]

    if { $length == 1 } {
        set median [lindex $values 0]
    } elseif { $length % 2 == 1 } {
        set median [lindex $values [expr {$length/2}]]
    } else {
        set median1 [lindex $values [expr {$length/2-1}]]
        set median2 [lindex $values [expr {$length/2}]]
        set median  [expr {($median1 + $median2)/2.0}]
    }
    return $median
}

# DrawBoxWhiskers --
#    Draw the data in an XY-plot as box-and-whiskers
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        Next x coordinate or a list of values
#    ycrd        Next y coordinate or a list of values
# Result:
#    None
# Side effects:
#    New data drawn in canvas
# Note:
#    We can do either a horizontal box (one y value) or
#    a vertical box (one x value). Not both
#
proc DrawBoxWhiskers { w series xcrd ycrd } {
    global data_series
    global scaling

    #
    # Check orientation
    #
    set type "?"
    if { [llength $xcrd] > 1 && [llength $ycrd] == 1 } {
        set type h
    }
    if { [llength $xcrd] == 1 && [llength $ycrd] > 1 } {
        set type v
    }
    if { $type == "?" } {
        return -code error "Use either a list of x values or a list of y values - not both"
    }

    #
    # Determine the quartiles:
    #
    # quartile1 is the 25% quantile
    # quartile2 is the 50% quantile (the median value)
    # quartile3 is the 75% quantile
    #
    # also
    # values between 'lower'/'upper' and outlower'/'outupper' are values within 1.5*IQR - 3*IQR (drawn as a dot)
    # values outside 'outlower'/'outupper' are values outside 3*IQR (drawn as a star)
    #
    # quartile1 is the 25% quantile
    # quartile2 is the 50% quantile (the median value)
    # quartile3 is the 75% quantile
    #
    # also
    # values between 'lower'/'upper' and outlower'/'outupper' are values within 1.5*IQR - 3*IQR (drawn as a dot)
    # values outside 'outlower'/'outupper' are values outside 3*IQR (drawn as a star)
    #
    if { $type == "h" } {
        set data [lsort -real -increasing $xcrd]
    } else {
        set data [lsort -real -increasing $ycrd]
    }
    set length    [llength $data]
    if { $length % 2 == 0 } {
        set lowerhalf [expr {($length-1)/2}]
        set upperhalf [expr {($length+1)/2}]
    } else {
        set lowerhalf [expr {$length/2-1}]
        set upperhalf [expr {$length/2+1}]
    }

    set quartile2 [DetermineMedian $data]
    set quartile1 [DetermineMedian [lrange $data 0 $lowerhalf]]
    set quartile3 [DetermineMedian [lrange $data $upperhalf end]]

    set hspread   [expr {$quartile3-$quartile1}]

    set lower     [expr {$quartile1-1.5*$hspread}]
    set upper     [expr {$quartile3+1.5*$hspread}]
    set outlower  [expr {$quartile1-3.0*$hspread}]
    set outupper  [expr {$quartile3+3.0*$hspread}]

    set whisker IQR
    if { [info exists data_series($w,$series,-whisker)] } {
        set whisker $data_series($w,$series,-whisker)
    }
    if { $whisker eq "extremes" } {
        set minimum [lindex $data 0]
        set maximum [lindex $data end]
    } elseif { $whisker eq "IQR" || $whisker eq "iqr" } {

        set minimum {}
        set maximum {}
        foreach value $data {
            if { $value >= $lower } {
                if { $minimum == {} || $minimum > $value } {
                    set minimum $value
                }
            }
            if { $value <= $upper } {
                if { $maximum == {} || $maximum < $value } {
                    set maximum $value
                }
            }
        }
    } elseif { $whisker eq "none"} {
        # nop
    } else {
        return -code error "unknown value '$whisker' for -whisker option"
    }

    #
    # Draw the box and whiskers
    #
    set colour "black"
    if { [info exists data_series($w,$series,-colour)] } {
        set colour $data_series($w,$series,-colour)
    }
    set mediancolour $colour
    if { [info exists data_series($w,$series,-mediancolour)] } {
        set mediancolour $data_series($w,$series,-mediancolour)
    }
    set mediancolour $colour
    if { [info exists data_series($w,$series,-mediancolour)] } {
       set mediancolour $data_series($w,$series,-mediancolour)
    }
    set filled "no"
    if { [info exists data_series($w,$series,-filled)] } {
        set filled $data_series($w,$series,-filled)
    }
    set fillcolour white
    if { [info exists data_series($w,$series,-fillcolour)] } {
       set fillcolour $data_series($w,$series,-fillcolour)
    }
    set boxwidth 10
    if { [info exists data_series($w,$series,-boxwidth)] } {
       set boxwidth $data_series($w,$series,-boxwidth)
    }
    set medianwidth 2
    if { [info exists data_series($w,$series,-medianwidth)] } {
       set medianwidth $data_series($w,$series,-medianwidth)
    }
    set whiskerwidth 1
    if { [info exists data_series($w,$series,-whiskerwidth)] } {
       set whiskerwidth $data_series($w,$series,-whiskerwidth)
    }

    if { $type == "h" } {
        #
        # Horizontal boxplot:
        #
        foreach {pxcrd1 pycrd2} [coordsToPixel $w $quartile1 $ycrd] {break}
        foreach {pxcrd2 pycrd2} [coordsToPixel $w $quartile2 $ycrd] {break}
        foreach {pxcrd3 pycrd2} [coordsToPixel $w $quartile3 $ycrd] {break}
        if {$whisker ne "none"} {
            foreach {pxcrdm pycrd1} [coordsToPixel $w $minimum $ycrd] {break}
            foreach {pxcrdM pycrd2} [coordsToPixel $w $maximum $ycrd] {break}
            set pycrd0h [expr {$pycrd1-$boxwidth/4}]
            set pycrd2h [expr {$pycrd1+$boxwidth/4}]
        } else {
            foreach {- pycrd1} [coordsToPixel $w 0 $ycrd] {break}
        }
        set pycrd0  [expr {$pycrd1-$boxwidth/2}]
        set pycrd2  [expr {$pycrd1+$boxwidth/2}]

        if {$whisker ne "none"} {
            #
            # Left whisker:
            #
            $w create line      $pxcrdm $pycrd1 $pxcrd1 $pycrd1 \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
            $w create line      $pxcrdm $pycrd0h $pxcrdm $pycrd2h \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
            # right whisker:
            #
            # Right whisker:
            #
            $w create line      $pxcrd3 $pycrd1 $pxcrdM $pycrd1 \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
            $w create line      $pxcrdM $pycrd0h $pxcrdM $pycrd2h \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
        }
        #
        # Box:
        #
        $w create rectangle $pxcrd1 $pycrd0 $pxcrd3 $pycrd2 \
            -outline $colour -fill $fillcolour -tag [list data data_$series]
        #
        # Median:
        #
        $w create line      $pxcrd2 $pycrd0 $pxcrd2 $pycrd2 -width $medianwidth \
                             -fill $mediancolour -tag [list data data_$series]

        if {$whisker eq "IQR"} {
            foreach value $data {
                if { $value < $outlower || $value > $outupper } {
                    foreach {px py} [coordsToPixel $w $value $ycrd] {break}
                    $w create text $px $py -text "*" -anchor c \
                                 -fill $colour -tag [list data data_$series]
                    continue
                }
                if { $value < $lower || $value > $upper } {
                    foreach {px py} [coordsToPixel $w $value $ycrd] {break}
                    $w create oval [expr {$px-2}] [expr {$py-2}] \
                                   [expr {$px+2}] [expr {$py+2}] \
                                 -fill $colour -tag [list data data_$series]
                    continue
                }
            }
        }
    } else {
        #
        # Vertical boxplot:
        #
        foreach {pxcrd2 pycrd1} [coordsToPixel $w $xcrd $quartile1] {break}
        foreach {pxcrd2 pycrd2} [coordsToPixel $w $xcrd $quartile2] {break}
        foreach {pxcrd2 pycrd3} [coordsToPixel $w $xcrd $quartile3] {break}
        if {$whisker ne "none"} {
            foreach {pxcrd1 pycrdm} [coordsToPixel $w $xcrd $minimum] {break}
            foreach {pxcrd2 pycrdM} [coordsToPixel $w $xcrd $maximum] {break}
            set pxcrd0h [expr {$pxcrd1-$boxwidth/4}]
            set pxcrd2h [expr {$pxcrd1+$boxwidth/4}]
        } else {
            foreach {pxcrd1 -} [coordsToPixel $w $xcrd 0] {break}
        }
        set pxcrd0  [expr {$pxcrd1-$boxwidth/2}]
        set pxcrd2  [expr {$pxcrd1+$boxwidth/2}]

        if {$whisker ne "none"} {
            #
            # Lower whisker:
            #
            $w create line      $pxcrd1 $pycrdm $pxcrd1 $pycrd1 \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
            $w create line      $pxcrd0h $pycrdm $pxcrd2h $pycrdm \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
            # upper whisker:
            #
            # Upper whisker:
            #
            $w create line      $pxcrd1 $pycrd3 $pxcrd1 $pycrdM \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
            $w create line      $pxcrd0h $pycrdM $pxcrd2h $pycrdM \
                                 -fill $colour -tag [list data data_$series] -width $whiskerwidth
        }
        #
        # Box:
        #
        $w create rectangle $pxcrd0 $pycrd1 $pxcrd2 $pycrd3 \
            -outline $colour -fill $fillcolour -tag [list data data_$series]
        #
        # Median:
        #
        $w create line      $pxcrd0 $pycrd2 $pxcrd2 $pycrd2 -width $medianwidth \
                             -fill $mediancolour -tag [list data data_$series]

        if {$whisker eq "IQR"} {
            foreach value $data {
                if { $value < $outlower || $value > $outupper } {
                    foreach {px py} [coordsToPixel $w $xcrd $value] {break}
                    $w create text $px $py -text "*" \
                                 -fill $colour -tag [list data data_$series]
                    continue
                }
                if { $value < $lower || $value > $upper } {
                    foreach {px py} [coordsToPixel $w $xcrd $value] {break}
                    $w create oval [expr {$px-3}] [expr {$py-3}] \
                                   [expr {$px+3}] [expr {$py+3}] \
                                 -fill $colour -tag [list data data_$series]
                    continue
                }
            }
        }
    }

    $w lower data
}

# DrawBoxData --
#    Draw the data in a boxplot
#    where either the x-axis or the y-axis consists of labels
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    label       Label on the x- or y-axis to put the box on
#    values      List of values to plot the box and whiskers for
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawBoxData { w series label values } {
    global config
    global scaling
    global settings

    set index [lsearch $config($w,axisnames) $label]
    if { $index == -1 } {
        return "Label $label not found on axis"
    }

    set coord [expr {$index + 1}]

    if { $settings($w,orientation) eq "vertical" } {
        DrawBoxWhiskers $w $series $coord $values
    } else {
        DrawBoxWhiskers $w $series $values $coord
    }
}

# DrawPie --
#    Draw the pie
# Arguments:
#    w           Name of the canvas
#    data        Data series (pairs of label-value)
# Result:
#    None
# Side effects:
#    Pie filled
#
proc DrawPie { w data } {
   global data_series
   global scaling
   global config

   set pxmin $scaling($w,pxmin)
   set pymin $scaling($w,pymin)
   set pxmax $scaling($w,pxmax)
   set pymax $scaling($w,pymax)

   set colours $scaling(${w},colours)

   if {[llength ${data}] == 2} {
       # use canvas create oval as arc does not fill with colour for a full circle
       set colour [lindex ${colours} 0]
       ${w} create oval ${pxmin} ${pymin} ${pxmax} ${pymax} -fill ${colour} \
         -width $config($w,slice,outlinewidth) -outline $config($w,slice,outline)
       # text looks nicer at 45 degree
       set rad [expr {45.0 * 3.1415926 / 180.0}]
       set xtext [expr {(${pxmin}+${pxmax}+cos(${rad})*(${pxmax}-${pxmin}+20))/2}]
       set ytext [expr {(${pymin}+${pymax}-sin(${rad})*(${pymax}-${pymin}+20))/2}]
       foreach {label value} ${data} {
           break
       }
       if { $config($w,labels,shownumbers) } {
           if { $config($w,labels,format) ne "" } {
               set label [format $config($w,labels,formatright) $value $label]
           } else {
               set label [format $config($w,labels,format) $label $value]
           }
       }
       ${w} create text ${xtext} ${ytext} -text ${label} -anchor w -font $config($w,labels,font)
       set scaling($w,angles) {0 360}
   } else {
       #
       # Determine the scale for the values
       # (so we can draw the correct angles)
       #

       set newdata  {}
       set sum 0.0
       foreach {label value} $data {
           lappend newdata [list $value $label]
          set sum [expr {$sum + $value}]
       }
       set factor [expr {360.0/$sum}]

       set data $newdata
       if { $config($w,labels,sorted) } {
           set data [lsort -index 0 -real $newdata]
       }

       #
       # Draw the line piece
       #
       set angle_init $config($w,slice,startangle)
       set op $config($w,slice,direction)

       set sum     0.0
       set idx     0
       set segment 0

       array unset scaling ${w},angles
       array unset scaling ${w},extent
       set colours [CycleColours ${colours} [expr {[llength ${data}] / 2}]]

       foreach sublist $data {
          foreach {value label} $sublist {break}
          set colour [lindex $colours $idx]
          incr idx

          if { $value == "" } {
              break
          }

          set angle_bgn [expr $angle_init $op ($sum * $factor)]
          set angle_ext $op[expr {$value * $factor}]
          lappend scaling(${w},angles) [expr {int(${angle_bgn})}]
          lappend scaling(${w},extent) [expr {int(${angle_ext})}]

          $w create arc  $pxmin $pymin $pxmax $pymax \
                         -start $angle_bgn -extent $angle_ext \
                         -fill $colour -style pieslice -tag [list data segment_$segment] \
                         -width $config($w,slice,outlinewidth) -outline $config($w,slice,outline)

          set rad   [expr {($angle_bgn+0.5*$angle_ext)*3.1415926/180.0}]
          # hack for label positioning 'out' or 'in':
          if {$config($w,labels,placement) eq "out"} {
            set xtext [expr {($pxmin+$pxmax+cos($rad)*($pxmax-$pxmin+20))/2}]
            set ytext [expr {($pymin+$pymax-sin($rad)*($pymax-$pymin+20))/2}]
            if { $xtext > ($pxmin+$pxmax)/2 } {
               set dir w
            } else {
               set dir e
            }
          } elseif {$config($w,labels,placement) eq "in"} {
            set dir c
            set centerx [expr {$pxmax - ($pxmax-$pxmin)/2.0}]
            set centery [expr {$pymax - ($pymax-$pymin)/2.0}]
            # 33% from the center to the radius
            set xtext [expr {$centerx + cos($rad)*($pxmax-$pxmin)*0.33}]
            set ytext [expr {$centery - sin($rad)*($pymax-$pymin)*0.33}]
          }

          if { $config($w,labels,shownumbers) } {
              if { $dir eq "w" && $config($w,labels,formatright) ne "" } {
                  set label [format $config($w,labels,formatright) $value $label]
              } else {
                  set label [format $config($w,labels,format) $label $value]
              }
          }

          $w create text $xtext $ytext -text $label -anchor $dir -tag segment_$segment \
            -font $config($w,labels,font) -fill $config($w,labels,textcolor)

          $w bind segment_$segment <ButtonPress-1> [list PieExplodeSegment $w $segment 1]

          set sum [expr {$sum + $value}]
          incr segment
       }
   }
}

# DrawSpiralPie --
#    Draw the spiral pie
# Arguments:
#    w           Name of the canvas
#    data        Data series (pairs of label-value)
# Result:
#    None
# Side effects:
#    Pie filled
#
proc DrawSpiralPie { w data } {
   global data_series
   global scaling
   global config

   set pxmin $scaling($w,pxmin)
   set pymin $scaling($w,pymin)
   set pxmax $scaling($w,pxmax)
   set pymax $scaling($w,pymax)

   set colours $scaling(${w},colours)

   if {[llength ${data}] == 2} {
       # use canvas create oval as arc does not fill with colour for a full circle
       set colour [lindex ${colours} 0]
       ${w} create oval ${pxmin} ${pymin} ${pxmax} ${pymax} -fill ${colour} \
         -width $config($w,slice,outlinewidth) -outline $config($w,slice,outline)
       # text looks nicer at 45 degree
       set rad [expr {45.0 * 3.1415926 / 180.0}]
       set xtext [expr {(${pxmin}+${pxmax}+cos(${rad})*(${pxmax}-${pxmin}+20))/2}]
       set ytext [expr {(${pymin}+${pymax}-sin(${rad})*(${pymax}-${pymin}+20))/2}]
       foreach {label value} ${data} {
           break
       }
       if { $config($w,labels,shownumbers) } {
           if { $config($w,labels,format) ne "" } {
               set label [format $config($w,labels,formatright) $value $label]
           } else {
               set label [format $config($w,labels,format) $label $value]
           }
       }

       ${w} create text ${xtext} ${ytext} -text ${label} -anchor w -font $config($w,labels,font)
       set scaling($w,angles) {0 360}
   } else {
       #
       # Determine the scale for the values
       # (so we can draw the correct radii)
       #
       set maxvalue [lindex $data 1]
       set newdata  {}
       foreach {label value} $data {
           lappend newdata [list $value $label]
           if { $maxvalue < $value } {
               set maxvalue $value
           }
       }
       set data $newdata
       if { $config($w,labels,sorted) } {
           set data [lsort -index 0 -real $newdata]
       }

       set factor [expr {1.0/sqrt($maxvalue)}]
       set dangle [expr {360.0/[llength $data]}]

       #
       # Draw the line piece
       #
       set angle_init $config($w,slice,startangle)
       set op         $config($w,slice,direction)

       set sum     0.0
       set idx     0
       set segment 0

       array unset scaling ${w},angles
       array unset scaling ${w},extent
       set colours [CycleColours ${colours} [llength ${data}]]

       foreach sublist $data {
          foreach {value label} $sublist {break}
          set colour [lindex $colours $idx]
          incr idx

          if { $value == "" } {
              break
          }

          set angle_bgn [expr $angle_init $op $sum]
          set angle_ext [expr $op $dangle]
          lappend scaling(${w},angles) [expr {int(${angle_bgn})}]
          lappend scaling(${w},extent) [expr {int(${angle_ext})}]

          set slicexmin [expr {0.5 * ($pxmax + $pxmin - sqrt($value) * $factor * ($pxmax-$pxmin))}]
          set slicexmax [expr {0.5 * ($pxmax + $pxmin + sqrt($value) * $factor * ($pxmax-$pxmin))}]
          set sliceymin [expr {0.5 * ($pymax + $pymin - sqrt($value) * $factor * ($pymax-$pymin))}]
          set sliceymax [expr {0.5 * ($pymax + $pymin + sqrt($value) * $factor * ($pymax-$pymin))}]

          $w create arc  $slicexmin $sliceymin $slicexmax $sliceymax \
                         -start $angle_bgn -extent $angle_ext \
                         -fill $colour -style pieslice -tag [list data segment_$segment] \
                         -width $config($w,slice,outlinewidth) -outline $config($w,slice,outline)

          set rad   [expr {($angle_bgn+0.5*$angle_ext)*3.1415926/180.0}]
          # hack for label positioning 'out' or 'in':
          if {$config($w,labels,placement) eq "out"} {
            set xtext [expr {($slicexmin+$slicexmax+cos($rad)*($slicexmax-$slicexmin+20))/2}]
            set ytext [expr {($sliceymin+$sliceymax-sin($rad)*($sliceymax-$sliceymin+20))/2}]
            if { $xtext > ($slicexmin+$sliceymax)/2 } {
               set dir w
            } else {
               set dir e
            }
          } elseif {$config($w,labels,placement) eq "in"} {
            set dir c
            set centerx [expr {$slicexmax - ($slicexmax-$slicexmin)/2.0}]
            set centery [expr {$sliceymax - ($sliceymax-$sliceymin)/2.0}]
            # 33% from the center to the radius
            set xtext [expr {$centerx + cos($rad)*($slicexmax-$slicexmin)*0.33}]
            set ytext [expr {$centery - sin($rad)*($sliceymax-$sliceymin)*0.33}]
          }

          if { $config($w,labels,shownumbers) } {
              if { $dir eq "w" && $config($w,labels,formatright) ne "" } {
                  set label [format $config($w,labels,formatright) $value $label]
              } else {
                  set label [format $config($w,labels,format) $label $value]
              }
          }

          $w create text $xtext $ytext -text $label -anchor $dir -tag segment_$segment \
            -font $config($w,labels,font) -fill $config($w,labels,textcolor)

          $w bind segment_$segment <ButtonPress-1> [list PieExplodeSegment $w $segment 1]

          set sum [expr {$sum + $dangle}]
          incr segment
       }
   }
}

# DrawPolarData --
#    Draw data given in polar coordinates
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    rad         Next radius
#    phi         Next angle (in degrees)
# Result:
#    None
# Side effects:
#    Data drawn in canvas
#
proc DrawPolarData { w series rad phi } {
   global torad
   set xcrd [expr {$rad*cos($phi*$torad)}]
   set ycrd [expr {$rad*sin($phi*$torad)}]

   DrawData $w $series $xcrd $ycrd
}

# DrawVertBarData --
#    Draw the vertical bars
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    ydata       Series of y data
#    colour      The colour to use (optional)
#    dir         Direction if graded colours are used (see DrawGradientBackground)
#    brightness  Brighten (bright) or darken (dark) the colours
# Result:
#    None
# Side effects:
#    Data bars drawn in canvas
#
proc DrawVertBarData { w series ydata {colour black} {dir {}} {brightness bright}} {
   global data_series
   global scaling
   global legend
   global settings
   global config

   #
   # Draw the bars
   #
   set x $scaling($w,xbase)

   #
   # set the colours
   #
   if {[llength ${colour}]} {
       set colours ${colour}
   } elseif {[info exists scaling(${w},colours)]} {
       set colours $scaling(${w},colours)
   } else {
       set colours {}
   }
   set colours [CycleColours ${colours} [llength ${ydata}]]

   #
   # Legend information
   #
   set legendcol [lindex $colours 0]
   set data_series($w,$series,-colour) $legendcol
   set data_series($w,$series,-type)   rectangle
   if { [info exists legend($w,canvas)] } {
       set legendw $legend($w,canvas)
       $legendw itemconfigure $series -fill $legendcol
   }

   set newbase {}

   set idx 0
   foreach yvalue $ydata ybase $scaling($w,ybase) {
      set colour [lindex ${colours} ${idx}]
      incr idx

      if { $yvalue == "" } {
          set yvalue 0.0
      }

      set xnext [expr {$x+$scaling($w,barwidth)}]
      set y     [expr {$yvalue+$ybase}]
      foreach {px1 py1} [coordsToPixel $w $x     $ybase] {break}
      foreach {px2 py2} [coordsToPixel $w $xnext $y    ] {break}

      if { $dir == {} } {
          $w create rectangle $px1 $py1 $px2 $py2 \
                         -fill $colour -outline $config($w,bar,outline) -tag [list data $w data_$series]
      } else {
          if { $brightness == "dark" } {
              set intensity black
          } else {
              set intensity white
          }
          DrawGradientBackground $w $colour $dir $intensity [list $px1 $py1 $px2 $py2]
      }

      if { $settings($w,showvalues) } {
          set pxtext [expr {($px1+$px2)/2.0}]
          set pytext [expr {$py2-5}]
          set text   [format $settings($w,valueformat) $yvalue]
          if { $settings($w,valuefont) == "" } {
              $w create text $pxtext $pytext -text $text -anchor s \
                         -fill $settings($w,valuecolour) -tag [list data $w data_$series]
          } else {
              $w create text $pxtext $pytext -text $text -anchor s \
                         -fill $settings($w,valuecolour) -tag [list data $w data_$series] \
                         -font $settings($w,valuefont)
          }
      }

      $w lower [list data && $w]

      set x [expr {$x+1.0}]

      lappend newbase $y
   }

   #
   # Prepare for the next series
   #
   if { $scaling($w,stacked) } {
      set scaling($w,ybase) $newbase
   }

   set scaling($w,xbase) [expr {$scaling($w,xbase)+$scaling($w,xshift)}]
}

# DrawHorizBarData --
#    Draw the horizontal bars
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xdata       Series of x data
#    colour      The colour to use (optional)
#    dir         Direction if graded colours are used (see DrawGradientBackground)
#    brightness  Brighten (bright) or darken (dark) the colours
# Result:
#    None
# Side effects:
#    Data bars drawn in canvas
#
proc DrawHorizBarData { w series xdata {colour black} {dir {}} {brightness bright}} {
   global data_series
   global scaling
   global legend
   global settings
   global config

   #
   # Draw the bars
   #
   set y $scaling($w,ybase)

   #
   # set the colours
   #
   if {[llength ${colour}]} {
       set colours ${colour}
   } elseif {[info exists scaling(${w},colours)]} {
       set colours $scaling(${w},colours)
   } else {
       set colours {}
   }
   set colours [CycleColours ${colours} [llength ${xdata}]]

   #
   # Legend information
   #
   set legendcol [lindex $colours 0]
   set data_series($w,$series,-colour) $legendcol
   if { [info exists legend($w,canvas)] } {
       set legendw $legend($w,canvas)
       $legendw itemconfigure $series -fill $legendcol
   }

   set newbase {}

   set idx 0
   foreach xvalue $xdata xbase $scaling($w,xbase) {
      set colour [lindex ${colours} ${idx}]
      incr idx

      if { $xvalue == "" } {
          set xvalue 0.0
      }

      set ynext [expr {$y+$scaling($w,barwidth)}]
      set x     [expr {$xvalue+$xbase}]
      foreach {px1 py1} [coordsToPixel $w $xbase $y    ] {break}
      foreach {px2 py2} [coordsToPixel $w $x     $ynext] {break}

      if { $dir == {} } {
          $w create rectangle $px1 $py1 $px2 $py2 \
                         -fill $colour -outline $config($w,bar,outline) -tag [list data $w data_$series]
      } else {
          if { $brightness == "dark" } {
              set intensity black
          } else {
              set intensity white
          }
          DrawGradientBackground $w $colour $dir $intensity [list $px1 $py1 $px2 $py2]
      }

      if { $settings($w,showvalues) } {
          set pytext [expr {($py1+$py2)/2.0}]
          set pxtext [expr {$px2+5}]
          set text   [format $settings($w,valueformat) $xvalue]
          if { $settings($w,valuefont) == "" } {
              $w create text $pxtext $pytext -text $text -anchor w \
                         -fill $settings($w,valuecolour) -tag [list data $w data_$series]
          } else {
              $w create text $pxtext $pytext -text $text -anchor w \
                         -fill $settings($w,valuecolour) -tag [list data $w data_$series] \
                         -font $settings($w,valuefont)
          }
      }

      $w lower [list data && $w]

      set y [expr {$y+1.0}]

      lappend newbase $x
   }

   #
   # Prepare for the next series
   #
   if { $scaling($w,stacked) } {
      set scaling($w,xbase) $newbase
   }

   set scaling($w,ybase) [expr {$scaling($w,ybase)+$scaling($w,yshift)}]
}

# DrawHistogramData --
#    Draw the vertical bars (or lines or symbols) for a histogram
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        X coordinate (for the righthand side of the bar)
#    ycrd        Y coordinate
# Result:
#    None
# Side effects:
#    Data bars drawn in canvas
#
proc DrawHistogramData { w series xcrd ycrd } {
   global data_series
   global scaling

   #
   # Check for missing values (only y-value can be missing!)
   #
   if { $ycrd == "" } {
       set data_series($w,$series,x) $xcrd
       return
   }

   #
   # Draw the bar/line
   #
   set colour "black"
   if { [info exists data_series($w,$series,-colour)] } {
      set colour $data_series($w,$series,-colour)
   }
   set fillcolour "black"
   if { [info exists data_series($w,$series,-fillcolour)] } {
      set fillcolour $data_series($w,$series,-fillcolour)
   }
   set width 1
   if { [info exists data_series($w,$series,-width)] } {
      set width $data_series($w,$series,-width)
   }
   set style "filled"
   if { [info exists data_series($w,$series,-style)] } {
      set style $data_series($w,$series,-style)
   }
   if { $style == "symbol" } {
       set symbol "plus"
       if { [info exists data_series($w,$series,-symbol)] } {
           set symbol $data_series($w,$series,-symbol)
       }
   }

   foreach {pxcrd pycrd} [coordsToPixel $w $xcrd $ycrd] {break}

   if { [info exists data_series($w,$series,x)] } {
      set xold       $data_series($w,$series,x)
      set pystair    $data_series($w,$series,pystair)
   } else {
      set xold       $scaling($w,xmin)
      set pystair    $scaling($w,pymax)
   }
   set yold $scaling($w,ymin)
   foreach {pxold pyold} [coordsToPixel $w $xold $yold] {break}

   switch -- $style {
       "filled" {
           $w create rectangle $pxold $pyold $pxcrd $pycrd \
                -fill $fillcolour -outline {} -tag [list data $w data_$series]
           $w create line $pxold $pystair $pxold $pycrd $pxcrd $pycrd \
                -fill $colour -width $width -tag [list data $w data_$series]
       }
       "stair" {
           $w create line $pxold $pystair $pxold $pycrd $pxcrd $pycrd \
                -fill $colour -width $width -tag [list data $w data_$series]
       }
       "spike" {
           $w create line $pxcrd $pyold $pxcrd $pycrd \
                -fill $colour -width $width -tag [list data $w data_$series]
       }
       "plateau" {
           $w create line $pxold $pycrd $pxold $pycrd $pxcrd $pycrd \
                -fill $colour -width $width -tag [list data $w data_$series]
       }
       "symbol" {
           DrawSymbolPixel $w $series $pxcrd $pycrd $symbol $colour [list data $w data_$series]
       }
   }

   $w lower [list data && $w]

   set data_series($w,$series,x)       $xcrd
   set data_series($w,$series,pystair) $pycrd
}

# DrawHistogramCumulative --
#    Draw the vertical bars for a histogram - accumulate the data
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        X coordinate (for the righthand side of the bar)
#    ycrd        Y coordinate
# Result:
#    None
# Side effects:
#    Data bars drawn in canvas
#
proc DrawHistogramCumulative { w series xcrd ycrd } {
   global data_series
   global scaling

   #
   # Check for missing values (only y-value can be missing!)
   #
   if { $ycrd == "" } {
       set data_series($w,$series,x) $xcrd
       return
   }

   #
   # Prepare the data
   #
   if { [info exists data_series($w,$series,y)] } {
      set ycrd [expr {$data_series($w,$series,y) + $ycrd}]
   }

   DrawHistogramData $w $series $xcrd $ycrd

   set data_series($w,$series,y) $ycrd
}

# DrawTimePeriod --
#    Draw a period
# Arguments:
#    w           Name of the canvas
#    text        Text to identify the "period" item
#    time_begin  Start time
#    time_end    Stop time
#    colour      The colour to use (optional)
# Result:
#    None
# Side effects:
#    Data bars drawn in canvas
#
proc DrawTimePeriod { w text time_begin time_end {colour black}} {
   global data_series
   global scaling

   #
   # Draw the text first
   #
   set ytext [expr {$scaling($w,current)+0.5*$scaling($w,dy)}]
   foreach {x y} [coordsToPixel $w $scaling($w,xmin) $ytext] {break}

   $w create text 5 $y -text $text -anchor w \
       -tags [list vertscroll above item_[expr {int($scaling($w,current))}]]

   #
   # Draw the bar to indicate the period
   #
   set xmin  [clock scan $time_begin]
   set xmax  [clock scan $time_end]
   set ybott [expr {$scaling($w,current)+$scaling($w,dy)}]

   foreach {x1 y1} [coordsToPixel $w $xmin $scaling($w,current)] {break}
   foreach {x2 y2} [coordsToPixel $w $xmax $ybott              ] {break}

   $w create rectangle $x1 $y1 $x2 $y2 -fill $colour \
       -tags [list $w vertscroll horizscroll below item_[expr {int($scaling($w,current))}]]

   ReorderChartItems $w

   set scaling($w,current) [expr {$scaling($w,current)-1.0}]

   RescaleChart $w
}

# DrawTimeVertLine --
#    Draw a vertical line with a label
# Arguments:
#    w           Name of the canvas
#    text        Text to identify the line
#    time        Time for which the line is drawn
# Result:
#    None
# Side effects:
#    Line drawn in canvas
#
proc DrawTimeVertLine { w text time {colour black}} {
   global data_series
   global scaling

   #
   # Draw the text first
   #
   set xtime [clock scan $time]
   #set ytext [expr {$scaling($w,ymax)-0.5*$scaling($w,dy)}]
   set ytext $scaling($w,ymax)
   foreach {x y} [coordsToPixel $w $xtime $ytext] {break}
   set y [expr {$y-5}]

   $w create text $x $y -text $text -anchor sw -tags [list $w horizscroll timeline]

   #
   # Draw the line
   #
   foreach {x1 y1} [coordsToPixel $w $xtime $scaling($w,ymin)] {break}
   foreach {x2 y2} [coordsToPixel $w $xtime $scaling($w,ymax)] {break}

   $w create line $x1 $y1 $x2 $y2 -fill black -tags [list $w horizscroll timeline tline]

   $w raise topmask
}

# DrawTimeMilestone --
#    Draw a "milestone"
# Arguments:
#    w           Name of the canvas
#    text        Text to identify the line
#    time        Time for which the milestone is drawn
#    colour      Optionally the colour
# Result:
#    None
# Side effects:
#    Line drawn in canvas
#
proc DrawTimeMilestone { w text time {colour black}} {
   global data_series
   global scaling

   #
   # Draw the text first
   #
   set ytext [expr {$scaling($w,current)+0.5*$scaling($w,dy)}]
   foreach {x y} [coordsToPixel $w $scaling($w,xmin) $ytext] {break}

   $w create text 5 $y -text $text -anchor w \
       -tags [list vertscroll above item_[expr {int($scaling($w,current))}]]

   #
   # Draw an upside-down triangle to indicate the time
   #
   set xcentre [clock scan $time]
   set ytop    $scaling($w,current)
   set ybott   [expr {$scaling($w,current)+0.8*$scaling($w,dy)}]

   foreach {x1 y1} [coordsToPixel $w $xcentre $ybott] {break}
   foreach {x2 y2} [coordsToPixel $w $xcentre $ytop]  {break}

   set x2 [expr {$x1-0.4*($y1-$y2)}]
   set x3 [expr {$x1+0.4*($y1-$y2)}]
   set y3 $y2

   $w create polygon $x1 $y1 $x2 $y2 $x3 $y3 -fill $colour \
       -tags [list $w vertscroll horizscroll below item_[expr {int($scaling($w,current))}]]

   ReorderChartItems $w

   set scaling($w,current) [expr {$scaling($w,current)-1.0}]

   RescaleChart $w
}

# ScaleItems --
#    Scale all items by a given factor
# Arguments:
#    w           Name of the canvas
#    xcentre     X-coordinate of centre
#    ycentre     Y-coordinate of centre
#    factor      The factor to scale them by
# Result:
#    None
# Side effects:
#    All items are scaled by the given factor and the
#    world coordinates are adjusted.
#
proc ScaleItems { w xcentre ycentre factor } {
   global scaling

   $w scale all $xcentre $ycentre $factor $factor

   foreach {xc yc} [pixelToCoords $w $xcentre $ycentre] {break}

   set rfact               [expr {1.0/$factor}]
   set scaling($w,xfactor) [expr {$scaling($w,xfactor)*$factor}]
   set scaling($w,yfactor) [expr {$scaling($w,yfactor)*$factor}]
   set scaling($w,xmin)    [expr {(1.0-$rfact)*$xc+$rfact*$scaling($w,xmin)}]
   set scaling($w,xmax)    [expr {(1.0-$rfact)*$xc+$rfact*$scaling($w,xmax)}]
   set scaling($w,ymin)    [expr {(1.0-$rfact)*$yc+$rfact*$scaling($w,ymin)}]
   set scaling($w,ymax)    [expr {(1.0-$rfact)*$yc+$rfact*$scaling($w,ymax)}]
}

# MoveItems --
#    Move all items by a given vector
# Arguments:
#    w           Name of the canvas
#    xmove       X-coordinate of move vector
#    ymove       Y-coordinate of move vector
# Result:
#    None
# Side effects:
#    All items are moved by the given vector and the
#    world coordinates are adjusted.
#
proc MoveItems { w xmove ymove } {
   global scaling

   $w move all $xmove $ymove

   set dx                  [expr {$scaling($w,xfactor)*$xmove}]
   set dy                  [expr {$scaling($w,yfactor)*$ymove}]
   set scaling($w,xmin)    [expr {$scaling($w,xmin)+$dx}]
   set scaling($w,xmax)    [expr {$scaling($w,xmax)+$dx}]
   set scaling($w,ymin)    [expr {$scaling($w,ymin)+$dy}]
   set scaling($w,ymax)    [expr {$scaling($w,ymax)+$dy}]
}

# DrawIsometricData --
#    Draw the data in an isometric plot
# Arguments:
#    w           Name of the canvas
#    type        Type of data
#    args        Coordinates and so on
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawIsometricData { w type args } {
   global data_series

   #
   # What type of data?
   #
   if { $type == "rectangle" } {
      foreach {x1 y1 x2 y2 colour} [concat $args "black"] {break}
      foreach {px1 py1} [coordsToPixel $w $x1 $y1] {break}
      foreach {px2 py2} [coordsToPixel $w $x2 $y2] {break}
      $w create rectangle $px1 $py1 $px2 $py2 \
                     -outline $colour -tag [list $w data]
      $w lower data
   }

   if { $type == "filled-rectangle" } {
      foreach {x1 y1 x2 y2 colour} [concat $args "black"] {break}
      foreach {px1 py1} [coordsToPixel $w $x1 $y1] {break}
      foreach {px2 py2} [coordsToPixel $w $x2 $y2] {break}
      $w create rectangle $px1 $py1 $px2 $py2 \
                     -outline $colour -fill $colour -tag [list $w data]
      $w lower [list data && $w]
   }

   if { $type == "filled-circle" } {
      foreach {x1 y1 rad colour} [concat $args "black"] {break}
      set x2 [expr {$x1+$rad}]
      set y2 [expr {$y1+$rad}]
      set x1 [expr {$x1-$rad}]
      set y1 [expr {$y1-$rad}]
      foreach {px1 py1} [coordsToPixel $w $x1 $y1] {break}
      foreach {px2 py2} [coordsToPixel $w $x2 $y2] {break}
      $w create oval $px1 $py1 $px2 $py2 \
                     -outline $colour -fill $colour -tag [list $w data]
      $w lower [list data && $w]
   }

   if { $type == "circle" } {
      foreach {x1 y1 rad colour} [concat $args "black"] {break}
      set x2 [expr {$x1+$rad}]
      set y2 [expr {$y1+$rad}]
      set x1 [expr {$x1-$rad}]
      set y1 [expr {$y1-$rad}]
      foreach {px1 py1} [coordsToPixel $w $x1 $y1] {break}
      foreach {px2 py2} [coordsToPixel $w $x2 $y2] {break}
      $w create oval $px1 $py1 $px2 $py2 \
                     -outline $colour -tag [list $w data]
      $w lower [list data && $w]
   }

}

# BackgroundColour --
#    Set the background colour or other aspects of the background
# Arguments:
#    w           Name of the canvas
#    part        Which part: axes or plot
#    colour      Colour to use (or if part is "image", name of the image)
#    dir         Direction of increasing whiteness (optional, for "gradient"
#    brightness  Brighten (bright) or darken (dark) the colours
#
# Result:
#    None
# Side effect:
#    Colour of the relevant part is changed
#
proc BackgroundColour { w part colour {dir {}} {brighten bright}} {
    if { $part == "axes" } {
        $w configure -highlightthickness 0
        $w itemconfigure mask -fill $colour -outline $colour
    }
    if { $part == "plot" } {
        $w configure -highlightthickness 0
        $w configure -background $colour
    }
    if { $part == "gradient" } {
          if { $brighten == "dark" } {
              set intensity black
          } else {
              set intensity white
          }
        DrawGradientBackground $w $colour $dir $intensity
    }
    if { $part == "image" } {
        DrawImageBackground $w $colour
    }
}

# DrawRadialSpokes --
#    Draw the spokes of the radial chart
# Arguments:
#    w           Name of the canvas
#    names       Names of the spokes
# Result:
#    None
# Side effects:
#    Radial chart filled in
#
proc DrawRadialSpokes { w names } {
   global settings
   global scaling

   set pxmin $scaling($w,pxmin)
   set pymin $scaling($w,pymin)
   set pxmax $scaling($w,pxmax)
   set pymax $scaling($w,pymax)

   $w create oval $pxmin $pymin $pxmax $pymax -outline black

   set dangle [expr {2.0 * 3.1415926 / [llength $names]}]
   set angle  0.0
   set xcentr [expr {($pxmin+$pxmax)/2.0}]
   set ycentr [expr {($pymin+$pymax)/2.0}]

   foreach name $names {
       set xtext  [expr {$xcentr+cos($angle)*($pxmax-$pxmin+20)/2}]
       set ytext  [expr {$ycentr-sin($angle)*($pymax-$pymin+20)/2}]
       set xspoke [expr {$xcentr+cos($angle)*($pxmax-$pxmin)/2}]
       set yspoke [expr {$ycentr-sin($angle)*($pymax-$pymin)/2}]

       if { cos($angle) >= 0.0 } {
           set anchor w
       } else {
           set anchor e
       }

       if { abs($xspoke-$xcentr) < 2 } {
           set xspoke $xcentr
       }
       if { abs($yspoke-$ycentr) < 2 } {
           set yspoke $ycentr
       }

       $w create text $xtext $ytext -text $name -anchor $anchor
       $w create line $xcentr $ycentr $xspoke $yspoke -fill black

       set angle [expr {$angle+$dangle}]
   }
}

# DrawRadial --
#    Draw the data for the radial chart
# Arguments:
#    w           Name of the canvas
#    values      Values for each spoke
#    colour      Colour of the line
#    thickness   Thickness of the line (optional)
# Result:
#    None
# Side effects:
#    New line drawn
#
proc DrawRadial { w values colour {thickness 1} } {
   global data_series
   global settings
   global scaling

   if { [llength $values] != $settings($w,number) } {
       return -code error "Incorrect number of data given - should be $settings($w,number)"
   }

   set pxmin $scaling($w,pxmin)
   set pymin $scaling($w,pymin)
   set pxmax $scaling($w,pxmax)
   set pymax $scaling($w,pymax)

   set dangle [expr {2.0 * 3.1415926 / [llength $values]}]
   set angle  0.0
   set xcentr [expr {($pxmin+$pxmax)/2.0}]
   set ycentr [expr {($pymin+$pymax)/2.0}]

   set coords {}

   if { ! [info exists data_series($w,base)] } {
       set data_series($w,base) {}
       foreach value $values {
           lappend data_series($w,base) 0.0
       }
   }

   set newbase {}
   foreach value $values base $data_series($w,base) {
       if { $settings($w,style) != "lines" } {
           set value [expr {$value+$base}]
       }
       set factor [expr {$value/$settings($w,scale)}]
       set xspoke [expr {$xcentr+$factor*cos($angle)*($pxmax-$pxmin)/2}]
       set yspoke [expr {$ycentr-$factor*sin($angle)*($pymax-$pymin)/2}]

       if { abs($xspoke-$xcentr) < 2 } {
           set xspoke $xcentr
       }
       if { abs($yspoke-$ycentr) < 2 } {
           set yspoke $ycentr
       }

       lappend coords $xspoke $yspoke
       lappend newbase $value
       set angle [expr {$angle+$dangle}]
   }

   set data_series($w,base) $newbase

   if { $settings($w,style) == "filled" } {
       set fillcolour $colour
   } else {
       set fillcolour ""
   }

   set id [$w create polygon $coords -outline $colour -width $thickness -fill $fillcolour -tags [list data $w]]
   $w lower $id
}

# DrawTrendLine --
#    Draw a trend line based on the given data in an XY-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        Next x coordinate
#    ycrd        Next y coordinate
# Result:
#    None
# Side effects:
#    New/updated trend line drawn in canvas
#
proc DrawTrendLine { w series xcrd ycrd } {
    global data_series
    global scaling

    #
    # Check for missing values
    #
    if { $xcrd == "" || $ycrd == "" } {
        return
    }

    #
    # Compute the coefficients of the line
    #
    if { [info exists data_series($w,$series,xsum)] } {
        set nsum  [expr {$data_series($w,$series,nsum)  + 1.0}]
        set xsum  [expr {$data_series($w,$series,xsum)  + $xcrd}]
        set x2sum [expr {$data_series($w,$series,x2sum) + $xcrd*$xcrd}]
        set ysum  [expr {$data_series($w,$series,ysum)  + $ycrd}]
        set xysum [expr {$data_series($w,$series,xysum) + $ycrd*$xcrd}]
    } else {
        set nsum  [expr {1.0}]
        set xsum  [expr {$xcrd}]
        set x2sum [expr {$xcrd*$xcrd}]
        set ysum  [expr {$ycrd}]
        set xysum [expr {$ycrd*$xcrd}]
    }

    if { $nsum*$x2sum != $xsum*$xsum } {
        set a [expr {($nsum*$xysum-$xsum*$ysum)/($nsum*$x2sum - $xsum*$xsum)}]
    } else {
        set a 0.0
    }
    set b [expr {($ysum-$a*$xsum)/$nsum}]

    set xmin $scaling($w,xmin)
    set xmax $scaling($w,xmax)

    foreach {pxmin pymin} [coordsToPixel $w $xmin [expr {$a*$xmin+$b}]] {break}
    foreach {pxmax pymax} [coordsToPixel $w $xmax [expr {$a*$xmax+$b}]] {break}

    #
    # Draw the actual line
    #
    set colour "black"
    if { [info exists data_series($w,$series,-colour)] } {
        set colour $data_series($w,$series,-colour)
    }

    if { [info exists data_series($w,$series,trend)] } {
        $w coords $data_series($w,$series,trend) $pxmin $pymin $pxmax $pymax
    } else {
        set data_series($w,$series,trend) \
            [$w create line $pxmin $pymin $pxmax $pymax -fill $colour -tag [list data $w data_$series]]
    }

    $w lower [list data && $w]

    set data_series($w,$series,nsum)  $nsum
    set data_series($w,$series,xsum)  $xsum
    set data_series($w,$series,x2sum) $x2sum
    set data_series($w,$series,ysum)  $ysum
    set data_series($w,$series,xysum) $xysum
}

# VectorConfigure --
#    Set configuration options for vectors
# Arguments:
#    w           Name of the canvas
#    series      Data series (identifier for vectors)
#    args        Pairs of configuration options:
#                -scale|-colour|-centred|-type {cartesian|polar|nautical}
# Result:
#    None
# Side effects:
#    Configuration options are stored
#
proc VectorConfigure { w series args } {
    global data_series
    global scaling

    foreach {option value} $args {
        switch -- $option {
            "-scale" {
                if { $value > 0.0 } {
                    set scaling($w,$series,vectorscale) $value
                } else {
                    return -code error "Scale factor must be positive"
                }
            }
            "-colour" - "-color" {
                set data_series($w,$series,vectorcolour) $value
            }
            "-centered" - "-centred" {
                set data_series($w,$series,vectorcentred) $value
            }
            "-type" {
                if { [lsearch {cartesian polar nautical} $value] >= 0 } {
                    set data_series($w,$series,vectortype) $value
                } else {
                    return -code error "Unknown vector components option: $value"
                }
            }
            default {
                return -code error "Unknown vector option: $option ($value)"
            }
        }
    }
}

# DrawVector --
#    Draw a vector at the given coordinates with the given components
# Arguments:
#    w           Name of the canvas
#    series      Data series (identifier for the vectors)
#    xcrd        X coordinate of start or centre
#    ycrd        Y coordinate of start or centre
#    ucmp        X component or length
#    vcmp        Y component or angle
# Result:
#    None
# Side effects:
#    New arrow drawn in canvas
#
proc DrawVector { w series xcrd ycrd ucmp vcmp } {
    global data_series
    global scaling

    #
    # Check for missing values
    #
    if { $xcrd == "" || $ycrd == "" } {
        return
    }
    #
    # Check for missing values
    #
    if { $ucmp == "" || $vcmp == "" } {
        return
    }

    #
    # Get the options
    #
    set scalef  1.0
    set colour  black
    set centred 0
    set type    cartesian
    if { [info exists scaling($w,$series,vectorscale)] } {
        set scalef $scaling($w,$series,vectorscale)
    }
    if { [info exists data_series($w,$series,vectorcolour)] } {
        set colour $data_series($w,$series,vectorcolour)
    }
    if { [info exists data_series($w,$series,vectorcentred)] } {
        set centred $data_series($w,$series,vectorcentred)
    }
    if { [info exists data_series($w,$series,vectortype)] } {
        set type $data_series($w,$series,vectortype)
    }

    #
    # Compute the coordinates of beginning and end of the arrow
    #
    switch -- $type {
        "polar" {
            set x1 [expr {$ucmp * cos( 3.1415926 * $vcmp / 180.0 ) }]
            set y1 [expr {$ucmp * sin( 3.1415926 * $vcmp / 180.0 ) }]
            set ucmp $x1
            set vcmp $y1
        }
        "nautical" {
            set x1 [expr {$ucmp * sin( 3.1415926 * $vcmp / 180.0 ) }]
            set y1 [expr {$ucmp * cos( 3.1415926 * $vcmp / 180.0 ) }]
            set ucmp $x1
            set vcmp $y1
        }
    }

    set u1 [expr {$scalef * $ucmp}]
    set v1 [expr {$scalef * $vcmp}]

    foreach {x1 y1} [coordsToPixel $w $xcrd $ycrd] {break}

    if { $centred } {
        set x1 [expr {$x1 - 0.5 * $u1}]
        set y1 [expr {$y1 + 0.5 * $v1}]
    }

    set x2 [expr {$x1 + $u1}]
    set y2 [expr {$y1 - $v1}]

    #
    # Draw the arrow
    #
    $w create line $x1 $y1 $x2 $y2 -fill $colour -tag [list data $w data_$series] -arrow last
    $w lower data
}

# DotConfigure --
#    Set configuration options for dots
# Arguments:
#    w           Name of the canvas
#    series      Data series (identifier for dots)
#    args        Pairs of configuration options:
#                -radius|-colour|-classes {value colour ...}|-outline|-scalebyvalue|
#                -scale
# Result:
#    None
# Side effects:
#    Configuration options are stored
#
proc DotConfigure { w series args } {
    global data_series
    global scaling

    foreach {option value} $args {
        switch -- $option {
            "-scale" {
                if { $value > 0.0 } {
                    set scaling($w,$series,dotscale) $value
                } else {
                    return -code error "Scale factor must be positive"
                }
            }
            "-colour" - "-color" {
                set data_series($w,$series,dotcolour) $value
            }
            "-radius" {
                set data_series($w,$series,dotradius) $value
            }
            "-scalebyvalue" {
                set data_series($w,$series,dotscalebyvalue) $value
            }
            "-outline" {
                set data_series($w,$series,dotoutline) $value
            }
            "-classes" {
                set data_series($w,$series,dotclasses) $value
            }
            "-3deffect" {
                set data_series($w,$series,dot3deffect) $value
            }
            default {
                return -code error "Unknown dot option: $option ($value)"
            }
        }
    }
}

# DrawDot --
#    Draw a dot at the given coordinates, size and colour based on the given value
# Arguments:
#    w           Name of the canvas
#    series      Data series (identifier for the vectors)
#    xcrd        X coordinate of start or centre
#    ycrd        Y coordinate of start or centre
#    value       Value to be used
# Result:
#    None
# Side effects:
#    New oval drawn in canvas
#
proc DrawDot { w series xcrd ycrd value } {
    global data_series
    global scaling

    #
    # Check for missing values
    #
    if { $xcrd == "" || $ycrd == "" || $value == "" } {
        return
    }

    #
    # Get the options
    #
    set scalef   1.0
    set colour   black
    set usevalue 1
    set outline  black
    set radius   3
    set classes  {}
    set use3deffect off
    if { [info exists scaling($w,$series,dotscale)] } {
        set scalef $scaling($w,$series,dotscale)
    }
    if { [info exists data_series($w,$series,dotcolour)] } {
        set colour $data_series($w,$series,dotcolour)
    }
    if { [info exists data_series($w,$series,dotoutline)] } {
        set outline {}
        if { $data_series($w,$series,dotoutline) } {
            set outline black
        }
    }
    if { [info exists data_series($w,$series,dotradius)] } {
        set radius $data_series($w,$series,dotradius)
    }
    if { [info exists data_series($w,$series,dotclasses)] } {
        set classes $data_series($w,$series,dotclasses)
    }
    if { [info exists data_series($w,$series,dotscalebyvalue)] } {
        set usevalue $data_series($w,$series,dotscalebyvalue)
    }
    if { [info exists data_series($w,$series,dot3deffect)] } {
        set use3deffect $data_series($w,$series,dot3deffect)
    }

    #
    # Compute the radius and the colour
    #
    if { $usevalue } {
        set radius [expr {$scalef * $value}]
    }
    if { $classes != {} } {
        foreach {limit col} $classes {
            if { $value < $limit } {
                set colour $col
                break
            }
        }
    }

    foreach {x y} [coordsToPixel $w $xcrd $ycrd] {break}

    set x1 [expr {$x - $radius}]
    set y1 [expr {$y - $radius}]
    set x2 [expr {$x + $radius}]
    set y2 [expr {$y + $radius}]

    #
    # Draw the oval
    #
    $w create oval $x1 $y1 $x2 $y2 -fill $colour -tag [list data $w data_$series] -outline $outline

    #
    # 3D effect
    #
    if { $use3deffect } {

        set xcentre [expr {$x - 0.6 * $radius}]
        set ycentre [expr {$y - 0.6 * $radius}]

        set factor    1.0
        set newradius $radius
        while { $newradius > 2 } {

            set factor    [expr {$factor * 0.8}]
            set newradius [expr {$radius * $factor}]
            set newcolour [BrightenColour $colour white [expr {1.0-$factor**2}]]

            set newdot [$w create oval $x1 $y1 $x2 $y2 -fill $newcolour -outline {} \
                            -tag [list data $w data_$series]]
            $w scale $newdot $xcentre $ycentre $factor $factor
        }
    }

    $w lower [list data && $w]
}

# DrawLog*Dot, DrawPolarDot --
#    Draw a dot at the given coordinates - variants for logarithmic axes and polar axis
# Arguments:
#    w           Name of the canvas
#    series      Data series (identifier for the vectors)
#    xcrd        X coordinate of start or centre
#    ycrd        Y coordinate of start or centre
#    value       Value to be used
# Result:
#    None
# Side effects:
#    New oval drawn in canvas
#
proc DrawLogXDot { w series xcrd ycrd value } {

    DrawDot $w $series [expr {log10($xcrd)}] $ycrd $value
}

proc DrawLogYDot { w series xcrd ycrd value } {

    DrawDot $w $series $xcrd [expr {log10($ycrd)}] $value
}

proc DrawLogXLogYDot { w series xcrd ycrd value } {

    DrawDot $w $series [expr {log10($xcrd)}] [expr {log10($ycrd)}] $value
}

proc DrawPolarDot { w series rad phi value } {
   global torad
   set xcrd [expr {$rad*cos($phi*$torad)}]
   set ycrd [expr {$rad*sin($phi*$torad)}]

   DrawDot $w $series $xcrd $ycrd $value
}

# DrawRchart --
#    Draw data together with two horizontal lines representing the
#    expected range
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xcrd        X coordinate of the data point
#    ycrd        Y coordinate of the data point
# Result:
#    None
# Side effects:
#    New data point drawn, lines updated
#
proc DrawRchart { w series xcrd ycrd } {
    global data_series
    global scaling

    #
    # Check for missing values
    #
    if { $xcrd == "" || $ycrd == "" } {
        return
    }

    #
    # In any case, draw the data point
    #
    DrawData $w $series $xcrd $ycrd

    #
    # Compute the expected range
    #
    if { ! [info exists data_series($w,$series,rchart)] } {
        set data_series($w,$series,rchart) $ycrd
    } else {
        lappend data_series($w,$series,rchart) $ycrd

        if { [llength $data_series($w,$series,rchart)] < 2 } {
            return
        }

        set filtered $data_series($w,$series,rchart)
        set outside  1
        while { $outside } {
            set data     $filtered
            foreach {ymin ymax} [RchartValues $data] {break}
            set filtered {}
            set outside  0
            foreach y $data {
                if { $y < $ymin || $y > $ymax } {
                    set outside 1
                } else {
                    lappend filtered $y
                }
            }
        }

        #
        # Draw the limit lines
        #
        if { [info exists data_series($w,$series,rchartlimits)] } {
            eval $w delete $data_series($w,$series,rchartlimits)
        }

        set colour "black"
        if { [info exists data_series($w,$series,-colour)] } {
            set colour $data_series($w,$series,-colour)
        }

        set xmin $scaling($w,xmin)
        set xmax $scaling($w,xmax)

        foreach {pxmin pymin} [coordsToPixel $w $xmin $ymin] {break}
        foreach {pxmax pymax} [coordsToPixel $w $xmax $ymax] {break}


        set data_series($w,$series,rchartlimits) [list \
            [$w create line $pxmin $pymin $pxmax $pymin -fill $colour -tag [list data $w data_$series]] \
            [$w create line $pxmin $pymax $pxmax $pymax -fill $colour -tag [list data $w data_$series]] \
        ]
    }
}

# RchartValues --
#    Compute the expected range for a series of data
# Arguments:
#    data        Data to be examined
# Result:
#    Expected minimum and maximum
#
proc RchartValues { data } {
    set sum   0.0
    set sum2  0.0
    set ndata [llength $data]

    if { $ndata <= 1 } {
        return [list $data $data]
    }

    foreach v $data {
        set sum   [expr {$sum  + $v}]
        set sum2  [expr {$sum2 + $v*$v}]
    }

    if { $ndata < 2 } {
       return [list $v $v]
    }

    set variance [expr {($sum2 - $sum*$sum/double($ndata))/($ndata-1.0)}]
    if { $variance < 0.0 } {
        set variance 0.0
    }

    set vmean [expr {$sum/$ndata}]
    set stdev [expr {sqrt($variance)}]
    set vmin  [expr {$vmean - 3.0 * $stdev}]
    set vmax  [expr {$vmean + 3.0 * $stdev}]

    return [list $vmin $vmax]
}

# ReorderChartItems --
#    Rearrange the drawing order of time and Gantt chart items
# Arguments:
#    w           Canvas widget containing them
# Result:
#    None
#
proc ReorderChartItems { w } {

    $w lower above
    $w lower vertmask
    $w lower tline
    $w lower below
    $w lower lowest

}

# RescaleChart --
#    Reset the scaling of the scrollbar(s) for time and Gantt charts
# Arguments:
#    w           Canvas widget containing them
# Result:
#    None
# Note:
#    To be called after scaling($w,current) has been updated
#    or a new time line has been added
#
proc RescaleChart { w } {
    global scaling

    if { [info exists scaling($w,vscroll)] } {
        if { $scaling($w,current) >= 0.0 } {
            set scaling($w,theight) $scaling($w,ymax)
            $scaling($w,vscroll) set 0.0 1.0
        } else {
            set scaling($w,theight) [expr {$scaling($w,ymax)-$scaling($w,current)}]
            $scaling($w,vscroll) set $scaling($w,curpos) \
                [expr {$scaling($w,curpos) + $scaling($w,ymax)/$scaling($w,theight)}]
        }
    }

    if { [info exists scaling($w,hscroll)] } {
        foreach {xmin dummy xmax} [$w bbox $w horizscroll] {break}
        set scaling($w,twidth) [expr {$xmax-$xmin}]
        if { $scaling($w,twidth) < $scaling($w,pxmax)-$scaling($w,pxmin) } {
            $scaling($w,hscroll) set 0.0 1.0
        } else {
            $scaling($w,hscroll) set $scaling($w,curhpos) \
                [expr {$scaling($w,curhpos) + \
                         ($scaling($w,pxmax)-$scaling($w,pxmin)) \
                         /double($scaling($w,twidth))}]
        }
    }
}

# ConnectVertScrollbar --
#    Connect a vertical scroll bar to the chart
# Arguments:
#    w           Canvas widget containing them
#    scrollbar   Scroll bar in question
# Result:
#    None
#
proc ConnectVertScrollbar { w scrollbar } {
    global scaling

    $scrollbar configure -command [list VertScrollChart $w]
    bind $w <4> [list VertScrollChart $w scroll  -1 units]
    bind $w <5> [list VertScrollChart $w scroll   1 units]
    bind $w <MouseWheel> [list VertScrollChart $w scroll %D wheel]
    set scaling($w,vscroll) $scrollbar

    RescaleChart $w
}

# ConnectHorizScrollbar --
#    Connect a horizontal scroll bar to the chart
# Arguments:
#    w           Canvas widget containing them
#    scrollbar   Scroll bar in question
# Result:
#    None
#
proc ConnectHorizScrollbar { w scrollbar } {
    global scaling

    $scrollbar configure -command [list HorizScrollChart $w]
    set scaling($w,hscroll) $scrollbar

    RescaleChart $w
}

# VertScrollChart --
#    Scroll a chart using the vertical scroll bar
# Arguments:
#    w           Canvas widget containing them
#    operation   Operation to respond to
#    number      Number representing the size of the displacement
#    unit        Unit of displacement
# Result:
#    None
#
proc !VertScrollChart { w operation number {unit {}}} {
    global scaling

    set pixheight [expr {$scaling($w,pymax)-$scaling($w,pymin)}]
    set height    [expr {$pixheight*$scaling($w,theight)/$scaling($w,ymax)}]

    switch -- $operation {
        "moveto" {
            set dy                 [expr {$height*($scaling($w,curpos)-$number)}]
            set scaling($w,curpos) $number
        }
        "scroll" {
            if { $unit == "units" } {
                set dy     [expr {-$number*$height/$scaling($w,theight)}]
                set newpos [expr {$scaling($w,curpos) + $number/$scaling($w,theight)}]
            } else {
                set dy     [expr {-$number*$pixheight}]
                set newpos [expr {$scaling($w,curpos) + $number*$scaling($w,ymax)/$scaling($w,theight)}]
            }

            # TODO: guard against scrolling too far
            #if { $newpos < 0.0 } {
            #    set newpos 0.0
            #    set dy     [expr {$...}]
            #}
            #
            #if { $newpos > 1.0 } {
            #    set newpos 1.0
            #    set dy     [expr {$...}]
            #}
            set scaling($w,curpos) $newpos
        }
    }

    #
    # TODO: limit the position between 0 and 1
    #

    $w move vertscroll 0 $dy

    RescaleChart $w
}
proc VertScrollChart { w operation number {unit {}}} {
    global scaling

    # Get the height of the scrolling region and the current position of the slider
    set height [expr {$scaling($w,pymax)-$scaling($w,pymin)}]
    foreach {ts bs} [$scaling($w,vscroll) get] {break}

    if { $unit == "wheel" } {
        set operation "scroll"
        set unit      "units"
        set number    [expr {$number>0? 1 : -1}]
    }

    switch -- $operation {
        "moveto" {
            # No scrolling if we are already at the top or bottom
            if { $number < 0.0 } {
                set number 0.0
            }
            if { $number+($bs-$ts) > 1.0 } {
                set number [expr {1.0-($bs-$ts)}]
            }
            set dy     [expr {$height*($scaling($w,curpos)-$number)/($bs-$ts)}]
            set scaling($w,curpos) $number
            $w move vertscroll 0 $dy
        }
        "scroll" {
            # Handle "units" and "pages" the same

            # No scrolling if we are at the top or bottom
            if {$number == -1 && $ts == 0.0} {
                return
            }

            if {$number == 1 && $bs == 1.0} {
                return
            }

            # Scroll 1 unit in coordinate space, converted to pixel space
            foreach {x1 y1} [coordsToPixel $w 0 0.0] {break}
            foreach {x2 y2} [coordsToPixel $w 0 1.0] {break}

            # This is the amount to scroll based on the current height
            set amt [expr {$number*($y2-$y1)/$height}]

            # Handle boundary conditions, don't want to scroll too far off
            # the top or bottom.
            if {$number == 1 && $bs-$amt > 1.0} {
                set amt [expr {$bs-1.0}]
            } elseif {$number == -1 && $ts-$amt < 0.0} {
                set amt $ts
            }

            # Set the scrolling parameters and scroll
            set dy  [expr {$height*($scaling($w,curpos)-($ts-$amt))/($bs-$ts)}]
            set scaling($w,curpos) [expr {$ts-$amt}]
            $w move vertscroll 0 $dy
        }
    }

    RescaleChart $w
}

# HorizScrollChart --
#    Scroll a chart using the horizontal scroll bar
# Arguments:
#    w           Canvas widget containing them
#    operation   Operation to respond to
#    number      Number representing the size of the displacement
#    unit        Unit of displacement
# Result:
#    None
#
proc HorizScrollChart { w operation number {unit {}}} {
    global scaling

    # Get the width of the scrolling region and the current position of the slider
    set width [expr {double($scaling($w,pxmax)-$scaling($w,pxmin))}]
    foreach {ts bs} [$scaling($w,hscroll) get] {break}

    switch -- $operation {
        "moveto" {
            # No scrolling if we are already at the top or bottom
            if { $number < 0.0 } {
                set number 0.0
            }
            if { $number+($bs-$ts) > 1.0 } {
                set number [expr {1.0-($bs-$ts)}]
            }
            set dx     [expr {$width*($scaling($w,curhpos)-$number)/($bs-$ts)}]
            set scaling($w,curhpos) $number
            $w move horizscroll $dx 0
        }
        "scroll" {
            # Handle "units" and "pages" the same

            # No scrolling if we are at the top or bottom
            if {$number == -1 && $ts == 0.0} {
                return
            }

            if {$number == 1 && $bs == 1.0} {
                return
            }

            # Scroll 1 unit in coordinate space, converted to pixel space
            set dx [expr {0.1*($scaling($w,xmax)-$scaling($w,xmin))}]
            foreach {x1 y1} [coordsToPixel $w 0   0.0] {break}
            foreach {x2 y2} [coordsToPixel $w $dx 0.0] {break}

            # This is the amount to scroll based on the current width
            set amt [expr {$number*($x2-$x1)/$width}]

            # Handle boundary conditions, don't want to scroll too far off
            # the left or the right
            if {$number == 1 && $bs-$amt > 1.0} {
                set amt [expr {$bs-1.0}]
            } elseif {$number == -1 && $ts-$amt < 0.0} {
                set amt $ts
            }

            # Set the scrolling parameters and scroll
            set dx  [expr {$width*($scaling($w,curhpos)-($ts-$amt))/($bs-$ts)}]
            set scaling($w,curhpos) [expr {$ts-$amt}]
            $w move horizscroll $dx 0
        }
    }

    RescaleChart $w
}

# DrawWindRoseData --
#    Draw the data for each sector
# Arguments:
#    w           Name of the canvas
#    data        List of "sectors" data
#    colour      Colour to use
# Result:
#    None
# Side effects:
#    Data added to the wind rose
#
proc DrawWindRoseData { w data colour } {

    global data_series

    set start_angle  $data_series($w,start_angle)
    set increment    $data_series($w,increment_angle)
    set width_sector $data_series($w,d_angle)

    set new_cumulative {}

    foreach value $data cumulative_radius $data_series($w,cumulative_radius) {
        set radius [expr {$value + $cumulative_radius}]

        foreach {xright ytop}    [polarToPixel $w [expr {$radius*sqrt(2.0)}]  45.0] {break}
        foreach {xleft  ybottom} [polarToPixel $w [expr {$radius*sqrt(2.0)}] 225.0] {break}

        $w create arc $xleft $ytop $xright $ybottom -style pie -fill $colour \
            -tag [list $w data_$data_series($w,count_data)] -start $start_angle -extent $width_sector

        lappend new_cumulative $radius

        set start_angle [expr {$start_angle - $increment}]
    }

    $w lower [list data_$data_series($w,count_data) && $w]

    set data_series($w,cumulative_radius) $new_cumulative
    incr data_series($w,count_data)
}

# DrawYband --
#    Draw a vertical grey band in a plot
# Arguments:
#    w           Name of the canvas
#    xmin        Lower bound of the band
#    xmax        Upper bound of the band
# Result:
#    None
# Side effects:
#    Horizontal band drawn in canvas
#
proc DrawYband { w xmin xmax } {
    global scaling


    foreach {xp1 yp1} [coordsToPixel $w $xmin $scaling($w,ymin)] {break}
    foreach {xp2 yp2} [coordsToPixel $w $xmax $scaling($w,ymax)] {break}

    $w create rectangle $xp1 $yp1 $xp2 $yp2 -fill grey70 -outline grey70 -tag [list band $w]

    $w lower [list band && $w] ;# TODO: also in "plot" method
}

# DrawXband --
#    Draw a horizontal grey band in a plot
# Arguments:
#    w           Name of the canvas
#    ymin        Lower bound of the band
#    ymax        Upper bound of the band
# Result:
#    None
# Side effects:
#    Horizontal band drawn in canvas
#
proc DrawXband { w ymin ymax } {
    global scaling


    foreach {xp1 yp1} [coordsToPixel $w $scaling($w,xmin) $ymin] {break}
    foreach {xp2 yp2} [coordsToPixel $w $scaling($w,xmax) $ymax] {break}

    $w create rectangle $xp1 $yp1 $xp2 $yp2 -fill grey70 -outline grey70 -tag [list band $w]

    $w lower [list band $w] ;# TODO: also in "plot" method
}

# DrawLabelDot --
#    Draw a label and a symbol (dot) in a plot
# Arguments:
#    w           Name of the canvas
#    x           X coordinate of the dot
#    y           Y coordinate of the dot
#    text        Text to be shown
#    orient      (Optional) orientation of the text wrt the dot
#                (w, e, n, s)
#
# Result:
#    None
# Side effects:
#    Label and dot drawn in canvas
# Note:
#    The routine uses the data series name "labeldot" to derive
#    the properties
#
proc DrawLabelDot { w x y text {orient w} } {
    global scaling

    foreach {xp yp} [coordsToPixel $w $x $y] {break}

    switch -- [string tolower $orient] {
        "w" {
            set xp [expr {$xp - 5}]
            set anchor e
        }
        "e" {
            set xp [expr {$xp + 10}]
            set anchor w
        }
        "s" {
            set yp [expr {$yp + 5}]
            set anchor n
        }
        "n" {
            set yp [expr {$yp - 5}]
            set anchor s
        }
        default {
            set xp [expr {$xp - 5}]
            set anchor w
        }
    }

    $w create text $xp $yp -text $text -fill grey -tag [list data $w] -anchor $anchor
    DrawData $w labeldot $x $y
}

# DrawLabelDotPolar --
#    Draw a label and a symbol (dot) in a polar plot
# Arguments:
#    w           Name of the canvas
#    rad         Radial coordinate of the dot
#    angle       Tangential coordinate of the dot
#    text        Text to be shown
#    orient      (Optional) orientation of the text wrt the dot
#                (w, e, n, s)
#
# Result:
#    None
# Side effects:
#    Label and dot drawn in canvas
# Note:
#    The routine uses the data series name "labeldot" to derive
#    the properties
#
proc DrawLabelDotPolar { w rad angle text {orient w} } {
    global torad

    set xcrd [expr {$rad*cos($angle*$torad)}]
    set ycrd [expr {$rad*sin($angle*$torad)}]

    DrawLabelDot $w $xcrd $ycrd $text $orient
}

# ConfigBar --
#    Configuration options for vertical and horizontal barcharts
# Arguments:
#    w           Name of the canvas
#    args        List of arguments
# Result:
#    None
# Side effects:
#    Items that are already visible will NOT be changed to the new look
#
proc ConfigBar { w args } {
    global settings

    foreach {option value} $args {
        set option [string range $option 1 end]
        if { [lsearch {showvalues valuefont valuecolour valuecolor valueformat} \
                $option] >= 0} {
            if { $option == "valuecolor" } {
                set option "valuecolour"
            }
            set settings($w,$option) $value
        } else {
            return -code error "Unknown barchart option: -$option"
        }
    }
}

# DrawFunction --
#    Draw a function f(x) in an XY-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series (for the colour)
#    xargs       List of arguments to the (anonymous) function
#    function    Function expression
#    args        All parameters in the expression
#                (and possibly the option -samples x)
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
# Note:
#    This method requires Tcl 8.5
#
# TODO:
#    Check for numerical problems!
#
proc DrawFunction { w series xargs function args } {
   global data_series
   global scaling

   #
   # Check the number of arguments
   #
   if { [llength $xargs]     != [llength $args] + 1 &&
        [llength $xargs] + 2 != [llength $args] + 1 } {
       return -code error "plotfunc: number of (extra) arguments does not match the list of variables"
   }

   #
   # Determine the number of samples
   #
   set number 50
   if { [llength $xargs] + 2 == [llength $args] + 1 } {
       if { [lindex $args end-1] != "-samples" } {
           return -code error "plotfunc: unknown option - [lindex $args end-1]"
       }
       if { ! [string is integer [lindex $args end]] } {
           return -code error "plotfunc: number of samples must be an integer - is instead \"[lindex $args end]\""
       }
       set number [lindex $args end]
       set args   [lrange $args 0 end-2]
   }

   #
   # Get the caller's namespace
   #
   set namespace [uplevel 2 {namespace current}]

   #
   # The actual drawing
   #
   set colour black
   if { [info exists data_series($w,$series,-colour)] } {
      set colour $data_series($w,$series,-colour)
   }

   set width 1
   if { [info exists data_series($w,$series,-width)] } {
      set width $data_series($w,$series,-width)
   }

   set xmin   $scaling($w,xmin)
   set dx     [expr {($scaling($w,xmax) - $xmin) / ($number - 1.0)}]

   set coords {}
   set lambda [string map [list XARGS $xargs FUNCTION $function NS $namespace] {{XARGS} {expr {FUNCTION}} NS}]

   for { set i 0 } { $i < $number } { incr i } {
       set x [expr {$xmin + $dx*$i}]

       if { [catch {
           set y [apply $lambda $x {*}$args]

           foreach {pxcrd pycrd} [coordsToPixel $w $x $y] {break}

           lappend coords $pxcrd $pycrd
       } msg] } {
           if { [llength $coords] > 2 } {
               $w create line $coords -fill $colour -smooth 1 -width $width -tag [list data $w data_$series]
               set coords {}
           }
       }

   }
   if { [llength $coords] > 2 } {
       $w create line $coords -fill $colour -smooth 1 -width $width -tag [list data $w data_$series]
   }

   $w lower [list data && $w]
}

# ClearPlot --
#     Clear the current canvas and associated data
#     in order to be able to draw another plot
#     and re-using the same canvas
#
# Arguments:
#     w        Name of the canvas
#
# Results:
#     None
#
# Side effects:
#   all objects on the canvas will be deleted
#   and all associated data removed
#
proc ClearPlot {w} {
    global data_series
    global scaling

    foreach s [array names data_series "$w,*"] {
        unset data_series($s)
    }
    foreach s [array names scaling "$w,*"] {
        unset scaling($s)
    }
    #$w delete $w
}

# NewPlotInCanvas --
#     Determine the name for the new plot
#
# Arguments:
#     c  Name of the canvas
#
# Results:
#     Unique name for the plot
#
proc NewPlotInCanvas {c} {
    global scaling

    if { ! [info exists scaling($c,plots)] } {
        set scaling($c,plots) 0
    } else {
        incr scaling($c,plots)
    }

    return [format "%02d%s" $scaling($c,plots) $c]
}

# DrawDataList --
#    Draw the data contained in two lists in an XY-plot
# Arguments:
#    w           Name of the canvas
#    series      Data series
#    xlist       List of x coordinates
#    ylist       List of y coordinates
#    every       Draw a symbol every N data
# Result:
#    None
# Side effects:
#    New data drawn in canvas
#
proc DrawDataList { w series xlist ylist {every {}} } {
    global data_series
    global scaling

    if { $every == {} } {
        set every [expr {int(sqrt([llength $xlist]))}]
        if { [llength $xlist] < 10 } {
            set every 1
        }
    }

    #
    # Determine the properties
    #
    set colour "black"
    if { [info exists data_series($w,$series,-colour)] } {
       set colour $data_series($w,$series,-colour)
    }

    set type "line"
    if { [info exists data_series($w,$series,-type)] } {
       set type $data_series($w,$series,-type)
    }
    set filled "no"
    if { [info exists data_series($w,$series,-filled)] } {
       set filled $data_series($w,$series,-filled)
    }
    set fillcolour white
    if { [info exists data_series($w,$series,-fillcolour)] } {
       set fillcolour $data_series($w,$series,-fillcolour)
    }
    set width 1
    if { [info exists data_series($w,$series,-width)] } {
       set width $data_series($w,$series,-width)
    }

    #
    # Draw all data
    # For the moment: no continuation!
    #
    if { [info exists data_series($w,$series,x)] } {
        set xold    $data_series($w,$series,x)
        set yold    $data_series($w,$series,y)

        set pcoords [coordsToPixel $w $xold $yold]

    } else {
        set xold    {}
        set yold    {}
        set pcoords {}
    }

    foreach xcrd $xlist ycrd $ylist {
        #
        # Check for missing values
        #
        if { $xcrd == "" || $ycrd == "" } {
            if { $pcoords != {} } {
                if { $type == "line" || $type == "both" } {
                    $w create line $pcoords \
                             -fill $colour -width $width -tag [list data $w data_$series]
                }
            }
            set pcoords {}
            continue
        } else {

            foreach {pxcrd pycrd} [coordsToPixel $w $xcrd $ycrd] {break}
            lappend pcoords $pxcrd $pycrd
        }
    }
    set data_series($w,$series,x) $xcrd
    set data_series($w,$series,y) $ycrd

    if { $pcoords != {} } {
        if { $type == "line" || $type == "both" } {
            $w create line $pcoords \
                     -fill $colour -width $width -tag [list data $w data_$series]
        }
    }

    if { $type == "symbol" || $type == "both" } {
        set symbol "dot"
        if { [info exists data_series($w,$series,-symbol)] } {
           set symbol $data_series($w,$series,-symbol)
        }
        for {set i 0} {$i < [llength $xlist]} {incr i $every} {
            set xcrd [lindex $xlist $i]
            set ycrd [lindex $ylist $i]

            if { $xcrd != {} && $ycrd != {} } {
                foreach {pxcrd pycrd} [coordsToPixel $w $xcrd $ycrd] {break}

                DrawSymbolPixel $w $series $pxcrd $pycrd $symbol $colour [list data $w data_$series]
            }
        }
    }

    $w lower [list data && $w]
}

# RenderText --
#    Draw the specified text into a plot using special rendering tags
# Arguments:
#    w           Name of the canvas
#    x           canvas x coordinate
#    y           canvas y coordinate
#    args        the text to render and additional text formatting information as option value pairs
# Result:
#    None
# Side effects:
#    Text String drawn in canvas
#
proc RenderText { w x y args } {
   global render

   set render(poshoriz) $x
   set render(posvert) $y
   set render(items) [list]
   set render(superFont) {}
   set render(subFont) {}

   array set options {-font {} -text {} -fill {} -anchor c -tags {}}
   # specified options:
   array set options $args
   # options to actually use:
   array set newOptions $args
   array unset newOptions -text
   # use this -anchor for now, correct later:
   set newOptions(-anchor) sw

   # do the rendering:
   foreach {text tag} $options(-text) {
       lassign [RenderSpecs $tag $options(-font)] xp1 yp1 xp2 yp2 advance newFont
       set newOptions(-font) $newFont
       RenderTextDo $w $text $xp1 $yp1 $xp2 $yp2 $advance [array get newOptions]
   }

   # fix the -anchor for the whole string:
   set bbox [$w bbox {*}$render(items)]
   lassign $bbox bx1 by1 bx2 by2
   lassign {0 0} dx dy
   # dy:
   switch $options(-anchor) {
       n - nw - ne {
          set dy [expr {$by2 - $by1}]
       }
       w - e - c {
          set dy [expr {($by2 - $by1)/2.0}]
       }
   }
   # dx:
   switch $options(-anchor) {
       c - n - s {
          set dx [expr {($bx1-$bx2)/2.0}]
       }
       ne - e - se {
          set dx [expr {$bx1-$bx2}]
       }
   }
   foreach item $render(items) {$w move $item $dx $dy}
}

# renderSpecs --
#    Read a render tag and determine the position of the
#    associated text string
#
# Arguments:
#    tag    tag to get specifications for
#    font   font requested by the user
#
# Result:
#    List of specs with relative positions, advancing information, and the font to use
#
proc RenderSpecs {tag font} {
   global render
   set advance 1
   set xp1     0 ;# how much to add to x coord before drawing
   set yp1     0 ;# how much to add to y coord before drawing
   set xp2     0 ;# how much to add to x coord afer drawing
   set yp2     0 ;# how much to add to y coord after drawing

   switch -- $tag {
       "_" { # Subscript
           if {$render(subFont) eq ""} {
               set render(subFont) [font create {*}[font configure $font]]
               set fontsize [font configure $font -size]
               set fontsize [expr {round($fontsize * 3.0/5.0)}]
               font configure $render(subFont) -size $fontsize
           } else {
               set fontsize [$render(subFont) configure -size]
           }
           set tmpFont $render(subFont)
           set yp1 [expr {round($fontsize/3.0)}]
           set yp2 [expr {-1 * $yp1}]
           set xp1 [expr {round($fontsize/-5.0)}]
           set xp2 [expr {round($fontsize/-5.0)}]
           set advance 1
        }
       "^" { # Superscript
             if {$render(subFont) eq ""} {
                 set render(superFont) [font create {*}[font configure $font]]
                 set fontsize [font configure $font -size]
                 set fontsize [expr {round($fontsize * 3.0/5.0)}]
                 font configure $render(superFont) -size $fontsize
             } else {
                 set fontsize [$render(superFont) configure -size]
             }
             set tmpFont $render(superFont)
             set yp1 [expr {round($fontsize/-1.5)}]
             set yp2 [expr {-1 * $yp1}]
             set xp1 [expr {round($fontsize/-5.0)}]
             set xp2 [expr {round($fontsize/-5.0)}]
             set advance 1
           }
       default {
           set tmpFont $font
       }
   }
   return [list $xp1 $yp1 $xp2 $yp2 $advance $tmpFont]
}

# doRender --
#    Render the given string according to the additional
#    rendering information
#
# Arguments:
#    canvas       Canvas in which to draw
#    string       text to be rendered
#    xp1          X-offset relative to current position before drawing
#    yp1          Y-offset relative to current position before drawing
#    xp2          X-offset after drawing
#    yp2          Y-offset after drawing
#    advance      whether we should advance to the next x position
#    fontOptions  list of pairs with formatting info for the font to use
#
# Result:
#    None
#
# Side effect:
#    The token is drawn on the canvas
#
proc RenderTextDo {canvas string xp1 yp1 xp2 yp2 advance fontOptions} {
   global render

   # new coords where to start drawing text:
   set xpos [expr {$render(poshoriz)+$xp1}]
   set ypos [expr {$render(posvert)+$yp1}]

   set item [$canvas create text $xpos $ypos -text $string {*}$fontOptions]
   lappend render(items) $item
   set bbox [$canvas bbox $item]
   set width [expr {[lindex $bbox 2]-[lindex $bbox 0]}]
   set xpos [expr {$xpos+$width+$xp2}]
   set ypos [expr {$ypos+$yp2}]

   if {$advance} {
      set render(poshoriz) $xpos
      set render(posvert) $ypos
   }
}


# plotspecial.tcl --
#    Facilities to draw specialised plots in a dedicated canvas
#
# Note:
#    It is a companion of "plotchart.tcl"
#

# DrawTargetData --
#    Compute the coordinates for the symbol representing the skill and draw it
#
# Arguments:
#    w           Name of the canvas
#    series      Name of the series of symbols
#    xvalues     List of model results
#    yvalues     List of measurements to which the model results are compared
# Result:
#    None
#
# Side effects:
#    Symbol drawn
#
# Note:
#    The lists of model data and measurements must have the same length
#    Missing data can be represented as {}. Only pairs that have both x and
#    y values are used in the computations.
#
proc DrawTargetData { w series xvalues yvalues } {
    global data_series

    if { [llength $xvalues] != [llength $yvalues] } {
        return -code error "Lists of model data and measurements should have the same length"
    }

    set xn {}
    set yn {}
    set xmean 0.0
    set ymean 0.0
    set count 0

    foreach x $xvalues y $yvalues {
        if { $x != {} && $y != {} } {
            lappend xn $x
            lappend yn $y

            set xmean [expr {$xmean + $x}]
            set ymean [expr {$ymean + $y}]
            incr count
        }
    }

    if { $count <= 1 } {
        return
    }

    set xmean [expr {$xmean/double($count)}]
    set ymean [expr {$ymean/double($count)}]

    set sumx2  0.0
    set sumy2  0.0
    set sumxy  0.0

    foreach x $xn y $yn {
        set sumx2 [expr {$sumx2 + ($x-$xmean)*($x-$xmean)}]
        set sumy2 [expr {$sumy2 + ($y-$ymean)*($y-$ymean)}]
        set sumxy [expr {$sumxy + ($x-$xmean)*($y-$ymean)}]
    }

    set stdevx [expr {sqrt($sumx2 / double($count-1))}]
    set stdevy [expr {sqrt($sumy2 / double($count-1))}]
    set corrxy [expr {$sumxy / $stdevx / $stdevy / double($count-1)}]

    set bstar  [expr {($xmean-$ymean) / $stdevy}]
    set sstar2 [expr {$sumx2 / $sumy2}]
    set rmsd   [expr {sqrt(1.0 + $sstar2 - 2.0 * sqrt($sstar2) * $corrxy)}]


    DataConfig $w $series -type symbol
    DrawData $w $series $rmsd $bstar
}

# DrawPerformanceData --
#    Compute the coordinates for the performance profiles and draw the lines
#
# Arguments:
#    w                  Name of the canvas
#    profiledata        Names and data for each profiled item
# Result:
#    None
#
# Side effects:
#    Symbol drawn
#
# Note:
#    The lists of model data and measurements must have the same length
#    Missing data can be represented as {}. Only pairs that have both x and
#    y values are used in the computations.
#
proc DrawPerformanceData { w profiledata } {
    global data_series
    global scaling

    #
    # Determine the minima per solved problem - they function as scale factors
    #
    set scale {}
    set values [lindex $profiledata 1]
    set number [llength $values]
    foreach v $values {
        lappend scale {}
    }

    foreach {series values} $profiledata {
        set idx 0
        foreach s $scale v $values {
            if { $s == {} || $s > $v } {
                lset scale $idx $v
            }
            incr idx
        }
    }

    #
    # Scale the data (remove the missing values)
    # and draw the series
    #
    set plotdata {}
    foreach {series values} $profiledata {
        set newvalues {}
        foreach s $scale v $values {
            if { $s != {} && $v != {} && $s != 0.0 } {
                lappend newvalues [expr {$v / $s}]
            }
        }
        set newvalues [lsort -real $newvalues]

        set count     1

        set yprev     {}
        foreach v $newvalues vn [concat [lrange $newvalues 1 end] 1.0e20] {
            set y [expr {$count/double($number)}]

            #
            # Construct the staircase
            #
            if { $v != $vn } {
                if { $yprev == {} } {
                    DrawData $w $series 1.0 $y
                } else {
                    DrawData $w $series $v $yprev
                }

                DrawData $w $series $v $y
                set  yprev $y
            }
            incr count

            puts "$series: $v $y"
        }
    }
}


# plottable.tcl --
#     Routines for drawing a table and its contents
#

# DrawTableFrame --
#     Draw the horizontal and vertical lines for the table
#
# Arguments:
#     w            Widget in which to draw
#
proc DrawTableFrame { w } {
    global scaling
    global config

    set pxmin [lindex $scaling($w,leftside)    0]
    set pxmax [lindex $scaling($w,rightside) end]
    set pymin $scaling($w,topside)
                                                     #Config      #Config
    $w create line $pxmin $pymin $pxmax $pymin -fill $config($w,frame,color) \
        -width $config($w,frame,outerwidth) -tag frame

    set scaling($w,hseparator) [$w create line $pxmin $pymin $pxmin $pymin \
            -fill $config($w,frame,color) -width $config($w,frame,outerwidth) -tag frame]

    set scaling($w,vseparators) {}

    set linewidth "outerwidth"
    foreach left $scaling($w,leftside) {

        lappend scaling($w,vseparators) [$w create line $left $pymin $left $pymin \
               -fill $config($w,frame,color) -width $config($w,frame,$linewidth) -tag frame]
        set linewidth "innerwidth"
    }

    set right [lindex $scaling($w,rightside) end]

    lappend scaling($w,vseparators) [$w create line $right $pymin $right $pymin \
           -fill $config($w,frame,color) -width $config($w,frame,outerwidth) -tag frame]
}

# SetFormatCommand --
#     Set the format command
#
# Arguments:
#     w            Widget in which to draw
#     command      Command to use
#
proc SetFormatCommand { w command } {
    global scaling

    set fullname [uplevel 2 [list namespace which $command]]

    if { $fullname == "" } {
        return -code error "No such command or procedure: $command"
    } else {
        set scaling($w,formatcommand) $fullname
    }
}

# DefaultFormat --
#     Default routine for formatting the contents of a cell
#
# Arguments:
#     chart        Table chart name
#     w            Widget in which to draw
#     row          Row of the current cell
#     column       Column of the current cell
#     value        Value to draw
#
# Result:
#     String to be drawn
#
# Note:
#     Does not set any cell properties
#
proc DefaultFormat { chart w row column value } {

    return $value
}

# TextAnchor --
#     Determine the position of the text in a cell
#
# Arguments:
#     chart        Table chart name
#     type         Type of cell
#     left         Left side of the cell
#     right        Right side of the cell
#
# Result:
#     X and Y-coordinate and anchor
#
proc TextAnchor { w type left right } {
    global scaling
    global config

    set ypos [expr {$scaling($w,topside) + $config($w,cell,topspace)}]

    switch -- $config($w,$type,anchor) {
        "left" {
            set anchor nw
            set xpos   [expr {$left + $config($w,cell,leftspace)}]
        }
        "right" {
            set anchor ne
            set xpos   [expr {$right - $config($w,cell,rightspace)}]
        }
        "center" -
        default  {
            set anchor n
            set xpos [expr {($left + $right) / 2.0}]
        }
    }

    return [list $xpos $ypos $anchor]
}

#
# DrawRow --
#     Draw a single row
#
# Arguments:
#     w            Widget in which to draw
#     values       Values to fill the row with
#     option       Option for drawing
#
# Note:
#     This does not take care at all of any configuration options!
#
proc DrawRow { w values {option {}} } {
    global scaling
    global config

    if { [llength $values] < [llength $scaling($w,leftside)] } {
        return -code error "Too few values to fill the row"
    }

    if { $option eq "header" } {
        foreach v $values left $scaling($w,leftside) right $scaling($w,rightside) {

            foreach {xpos ypos anchor} [TextAnchor $w header $left $right] {break}

            $w create rectangle $left $scaling($w,topside) $right [expr {$scaling($w,topside)+$config($w,header,height)}] \
                -tag cellbg -fill $scaling($w,cell,-background) -outline $scaling($w,cell,-background)

            $w create text $xpos $ypos -text $v -fill $config($w,header,color) -anchor $anchor
        }
    } else {

        # TODO
        set type oddrow
        if { $scaling($w,row) % 2 == 0 } {
            set type evenrow
        }

        set column 0
        foreach value $values left $scaling($w,leftside) right $scaling($w,rightside) {

            foreach {xpos ypos anchor} [TextAnchor $w cell $left $right] {break}

            set scaling($w,left)     $left
            set scaling($w,right)    $right
            set scaling($w,hasworld) 0

            set text [$scaling($w,formatcommand) table_$w $w $scaling($w,row) $column $value]

            if { $scaling($w,cell,-background) ne "" } {
                $w create rectangle $left $scaling($w,topside) $right [expr {$scaling($w,topside)+$config($w,$type,height)}] \
                    -tag cellbg -fill $scaling($w,cell,-background) -outline $scaling($w,cell,-background)
            }

            $w create text $xpos $ypos -text $text -anchor $anchor -tag celltext \
                -fill $scaling($w,cell,-color)
            incr column
        }
    }

    set oldtop $scaling($w,toptable)
    set scaling($w,topside) [expr {$scaling($w,topside) + $config($w,evenrow,height)}]

    $w coords $scaling($w,hseparator) [lindex $scaling($w,leftside)    0] $scaling($w,topside) \
                                      [lindex $scaling($w,rightside) end] $scaling($w,topside)

    foreach vseparator $scaling($w,vseparators) hcoord $scaling($w,leftside) {
        if { $hcoord == {} } {
            set hcoord [lindex $scaling($w,rightside) end]
        }
        $w coords $vseparator $hcoord $oldtop $hcoord $scaling($w,topside)
    }

    incr scaling($w,row)

    $w lower cellbg
    $w raise celltext
    $w raise frame
}

#
# DrawSeparator --
#     Draw a horizontal separator
#
# Arguments:
#     w            Widget in which to draw
#
proc DrawSeparator { w } {
    global scaling
    global config

    set left  [lindex $scaling($w,leftside)    0]
    set right [lindex $scaling($w,rightside) end]

    $w create line $left $scaling($w,topside) $right $scaling($w,topside) -tag frame \
        -fill $config($w,frame,color) -width $config($w,frame,innerwidth)

    $w raise frame
}

# ConfigureTableCell --
#     Set the properties of the "current" table cell
#
# Arguments:
#     w            Widget in which to draw
#     args         List of key-value pairs
#
proc ConfigureTableCell { w args } {
    global scaling
    global config

    foreach {key value} $args {
        switch -- $key {
            "-background" -
            "-color"      -
            "-font"       -
            "-justify"    {
                set scaling($w,cell,$key) $value
            }
            "-anchor"     {
                #
                # Problem: this takes effect in the _next_ cell!
                #
                set config($w,cell,anchor) $value
            }
            default {
                return -code error "Unknown cell property: $key"
            }
        }
    }
}

# TableCellCoordinates --
#     Get the pixel coordinates of the "current" table cell
#
# Arguments:
#     w            Widget in which to draw
#
proc TableCellCoordinates { w } {
    global scaling
    global config

    return [list $scaling($w,left) $scaling($w,topside) $scaling($w,right) [expr {$scaling($w,topside)+$config($w,evenrow,height)}]]
}

# TableWorldCoordinates --
#     Set the world coordinates for the "current" table cell
#
# Arguments:
#     w            Widget in which to draw
#     xmin         Minimum x-coordinate
#     ymin         Minimum y-coordinate
#     xmax         Maximum x-coordinate
#     ymax         Maximum y-coordinate
#
proc TableWorldCoordinates { w xmin ymin xmax ymax } {
    global scaling
    global config

    viewPort         $w $scaling($w,left)  $scaling($w,topside) \
                        $scaling($w,right) [expr {$scaling($w,topside)+$config($w,evenrow,height)}]
    worldCoordinates $w $xmin $ymin $xmax $ymax

    set scaling($w,hasworld) 1
}

# TableWorldToPixels --
#     Convert the world coordinates for the "current" table cell to pixels
#
# Arguments:
#     w            Widget in which to draw
#     args         Either a single argument (list of xy-pairs) or separate
#                  argumentns representing xy-pairs
#
proc TableWorldToPixels { w args } {
    global scaling

    if { [llength $args] == 1 } {
        set coords [lindex $args 0]
    } else {
        set coords $args
    }
    if { $scaling($w,hasworld) } {
        set pixelCoords {}
        foreach {x y} $coords {
            set pixelCoords [concat $pixelCoords [coordsToPixel $w $x $y]]
        }
        set coords $pixelCoords
    }

    return $coords
}


# scaling.tcl --
#    Make a nice scale for the axes in the Plotchart package
#

#
# Try and load the math::fuzzy package for better
# comparisons
#
if { [catch {
    package require math::fuzzy
    namespace import ::math::fuzzy::tlt
    namespace import ::math::fuzzy::tgt
    }] } {

    proc tlt {a b} {
        expr {$a < $b }
    }
    proc tgt {a b} {
        expr {$a > $b }
    }
}

# determineScaleFromList --
#    Determine nice values for an axis from a list of values
#
# Arguments:
#    values    List of values
#    inverted  Whether to return values for an inverted axis (1) or not (0)
#              Defaults to 0.
# Result:
#    A list of three values, a nice minimum and maximum
#    and stepsize
# Note:
#    Missing values (empty strings) are allowed in the list of values
#
proc determineScaleFromList { values {inverted 0} } {

    set xmin {}
    set xmax {}

    foreach v $values {
        if { $v == {} } {
            continue
        }
        if { $xmin == {} || $xmin > $v } {
            set xmin $v
        }
        if { $xmax == {} || $xmax < $v } {
            set xmax $v
        }
    }

    return [determineScale $xmin $xmax $inverted]
}

# determineScale --
#    Determine nice values for an axis from the given extremes
#
# Arguments:
#    xmin      Minimum value
#    xmax      Maximum value
#    inverted  Whether to return values for an inverted axis (1) or not (0)
#              Defaults to 0.
# Result:
#    A list of three values, a nice minimum and maximum
#    and stepsize
# Note:
#    xmin is assumed to be smaller or equal xmax
#
proc determineScale { xmin xmax {inverted 0} } {
   set dx [expr {abs($xmax-$xmin)}]

   if { $dx == 0.0 } {
      if { $xmin == 0.0 } {
         return [list -0.1 0.1 0.1]
      } else {
         set dx [expr {0.2*abs($xmax)}]
         set xmin [expr {$xmin-0.5*$dx}]
         set xmax [expr {$xmin+0.5*$dx}]
      }
   }

   #
   # Very small ranges (relatively speaking) cause problems
   # The range must be at least 1.0e-8
   #
   if { $dx < 0.5e-8*(abs($xmin)+abs($xmax)) } {
       set xmean [expr {0.5*($xmin+$xmax)}]
       set dx    [expr {1.0e-8*$xmean}]
       set xmin  [expr {$xmean - 0.5*$dx}]
       set xmax  [expr {$xmean + 0.5*$dx}]
   }

   #
   # Determine the factor of 10 so that dx falls within the range 1-10
   #
   set expon  [expr {int(log10($dx))}]
   set factor [expr {pow(10.0,$expon)}]

   set dx     [expr {$dx/$factor}]

   foreach {limit step} {1.4 0.2 2.0 0.5 5.0 1.0 10.0 2.0} {
      if { $dx < $limit } {
         break
      }
   }

   set fmin    [expr {$xmin/$factor/$step}]
   set fmax    [expr {$xmax/$factor/$step}]
#  if { abs($fmin) > 1.0e10 } {
#      set fmin [expr {$fmin > 0.0 ? 1.0e10 : -1.0e10}]
#  }
#  if { abs($fmax) > 1.0e10 } {
#      set fmax [expr {$fmax > 0.0 ? 1.0e10 : -1.0e10}]
#  }
   set nicemin [expr {$step*$factor*wide($fmin)}]
   set nicemax [expr {$step*$factor*wide($fmax)}]

   if { [tlt $nicemax $xmax] } {
      set nicemax [expr {$nicemax+$step*$factor}]
   }
   if { [tgt $nicemin $xmin] } {
      set nicemin [expr {$nicemin-$step*$factor}]
   }

   if { !$inverted } {
       return [list $nicemin $nicemax [expr {$step*$factor}]]
   } else {
       return [list $nicemax $nicemin [expr {-$step*$factor}]]
   }
}

# determineTimeScale --
#    Determine nice date/time values for an axis from the given extremes
#
# Arguments:
#    tmin      Minimum date/time
#    tmax      Maximum date/time
# Result:
#    A list of three values, a nice minimum and maximum
#    and stepsize
# Note:
#    tmin is assumed to be smaller or equal tmax
#
proc determineTimeScale { tmin tmax } {
    set ttmin [clock scan $tmin]
    set ttmax [clock scan $tmax]

    set dt [expr {abs($ttmax-$ttmin)}]

    if { $dt == 0.0 } {
        set dt 86400.0
        set ttmin [expr {$ttmin-$dt}]
        set ttmax [expr {$ttmin+$dt}]
    }

    foreach {limit step} {2.0 0.5 5.0 1.0 10.0 2.0 50.0 7.0 300.0 30.0 1.0e10 365.0} {
        if { $dt/86400.0 < $limit } {
            break
        }
    }

    set nicemin [expr {$step*floor($ttmin/$step)}]
    set nicemax [expr {$step*floor($ttmax/$step)}]

    if { $nicemax < $ttmax } {
        set nicemax [expr {$nicemax+$step}]
    }
    if { $nicemin > $ttmin } {
        set nicemin [expr {$nicemin-$step}]
    }

    set nicemin [expr {int($nicemin)}]
    set nicemax [expr {int($nicemax)}]

    return [list [clock format $nicemin -format "%Y-%m-%d %H:%M:%S"] \
                 [clock format $nicemax -format "%Y-%m-%d %H:%M:%S"] \
                 $step]
}

if 0 {
    #
    # Some simple test cases
    #
    namespace import determineScale
    puts [determineScale 0.1 1.0]
    puts [determineScale 0.001 0.01]
    puts [determineScale -0.2 0.9]
    puts [determineScale -0.25 0.85]
    puts [determineScale -0.25 0.7999]
    puts [determineScale 10001 10010]
    puts [determineScale 10001 10015]
}
if 0 {
    puts [determineTimeScale "2007-01-15" "2007-01-16"]
    puts [determineTimeScale "2007-03-15" "2007-06-16"]
}

#
# Array linking procedures with methods
#
set methodProc(xyplot,title)             DrawTitle
set methodProc(xyplot,xtext)             DrawXtext
set methodProc(xyplot,ytext)             DrawYtext
set methodProc(xyplot,vtext)             DrawVtext
set methodProc(xyplot,plot)              DrawData
set methodProc(xyplot,dot)               DrawDot
set methodProc(xyplot,dotconfig)         DotConfigure
set methodProc(xyplot,interval)          DrawInterval
set methodProc(xyplot,trend)             DrawTrendLine
set methodProc(xyplot,vector)            DrawVector
set methodProc(xyplot,vectorconfig)      VectorConfigure
set methodProc(xyplot,rchart)            DrawRchart
set methodProc(xyplot,grid)              DrawGrid
set methodProc(xyplot,contourlines)      DrawIsolines
set methodProc(xyplot,contourfill)       DrawShades
set methodProc(xyplot,contourbox)        DrawBox
set methodProc(xyplot,saveplot)          SavePlot
set methodProc(xyplot,dataconfig)        DataConfig
set methodProc(xyplot,xconfig)           XConfig
set methodProc(xyplot,yconfig)           YConfig
set methodProc(xyplot,xticklines)        DrawXTicklines
set methodProc(xyplot,yticklines)        DrawYTicklines
set methodProc(xyplot,background)        BackgroundColour
set methodProc(xyplot,legendconfig)      LegendConfigure
set methodProc(xyplot,legend)            DrawLegend
set methodProc(xyplot,removefromlegend)  RemoveFromLegend
set methodProc(xyplot,legendisolines)    DrawLegendIsolines
set methodProc(xyplot,legendshades)      DrawLegendShades
set methodProc(xyplot,balloon)           DrawBalloon
set methodProc(xyplot,balloonconfig)     ConfigBalloon
set methodProc(xyplot,plaintext)         DrawPlainText
set methodProc(xyplot,plaintextconfig)   ConfigPlainText
set methodProc(xyplot,bindvar)           BindVar
set methodProc(xyplot,bindcmd)           BindCmd
set methodProc(xyplot,rescale)           RescalePlot
set methodProc(xyplot,box-and-whiskers)  DrawBoxWhiskers
set methodProc(xyplot,xband)             DrawXband
set methodProc(xyplot,yband)             DrawYband
set methodProc(xyplot,labeldot)          DrawLabelDot
set methodProc(xyplot,bindplot)          BindPlot
set methodProc(xyplot,bindlast)          BindLast
set methodProc(xyplot,contourlinesfunctionvalues)      DrawIsolinesFunctionValues
set methodProc(xyplot,plotfunc)          DrawFunction
set methodProc(xyplot,drawobject)        DrawObject
set methodProc(xyplot,object)            DrawObject
set methodProc(xyplot,plotlist)          DrawDataList
set methodProc(xyplot,plotarea)          GetPlotArea
set methodProc(xyplot,canvas)            GetCanvas
set methodProc(xlogyplot,title)          DrawTitle
set methodProc(xlogyplot,xtext)          DrawXtext
set methodProc(xlogyplot,ytext)          DrawYtext
set methodProc(xlogyplot,vtext)          DrawVtext
set methodProc(xlogyplot,plot)           DrawData
set methodProc(xlogyplot,dot)            DrawDot
set methodProc(xlogyplot,labeldot)       DrawLabelDot
set methodProc(xlogyplot,dotconfig)      DotConfigure
set methodProc(xlogyplot,interval)       DrawLogInterval
set methodProc(xlogyplot,trend)          DrawLogTrendLine
set methodProc(xlogyplot,saveplot)       SavePlot
set methodProc(xlogyplot,dataconfig)     DataConfig
set methodProc(xlogyplot,xconfig)        XConfigXlogY
set methodProc(xlogyplot,yconfig)        YConfigXLogY
set methodProc(xlogyplot,xticklines)     DrawXTicklines
set methodProc(xlogyplot,yticklines)     DrawYTicklines
set methodProc(xlogyplot,background)     BackgroundColour
set methodProc(xlogyplot,legendconfig)   LegendConfigure
set methodProc(xlogyplot,legend)         DrawLegend
set methodProc(xlogyplot,removefromlegend) RemoveFromLegend
set methodProc(xlogyplot,balloon)        DrawBalloon
set methodProc(xlogyplot,balloonconfig)  ConfigBalloon
set methodProc(xlogyplot,plaintext)      DrawPlainText
set methodProc(xlogyplot,plaintextconfig) ConfigPlainText
set methodProc(xlogyplot,canvas)         GetCanvas
set methodProc(logxyplot,title)          DrawTitle
set methodProc(logxyplot,xtext)          DrawXtext
set methodProc(logxyplot,ytext)          DrawYtext
set methodProc(logxyplot,vtext)          DrawVtext
set methodProc(logxyplot,plot)           DrawData
set methodProc(logxyplot,dot)            DrawDot
set methodProc(logxyplot,labeldot)       DrawLabelDot
set methodProc(logxyplot,dotconfig)      DotConfigure
set methodProc(logxyplot,interval)       DrawLogInterval
set methodProc(logxyplot,trend)          DrawLogTrendLine
set methodProc(logxyplot,saveplot)       SavePlot
set methodProc(logxyplot,dataconfig)     DataConfig
set methodProc(logxyplot,xconfig)        XConfigLogXY
set methodProc(logxyplot,yconfig)        YConfigLogXY
set methodProc(logxyplot,xticklines)     DrawXTicklines
set methodProc(logxyplot,yticklines)     DrawYTicklines
set methodProc(logxyplot,background)     BackgroundColour
set methodProc(logxyplot,legendconfig)   LegendConfigure
set methodProc(logxyplot,legend)         DrawLegend
set methodProc(logxyplot,removefromlegend) RemoveFromLegend
set methodProc(logxyplot,balloon)        DrawBalloon
set methodProc(logxyplot,balloonconfig)  ConfigBalloon
set methodProc(logxyplot,plaintext)      DrawPlainText
set methodProc(logxyplot,plaintextconfig)   ConfigPlainText
set methodProc(logxyplot,canvas)         GetCanvas
set methodProc(logxlogyplot,title)          DrawTitle
set methodProc(logxlogyplot,xtext)          DrawXtext
set methodProc(logxlogyplot,ytext)          DrawYtext
set methodProc(logxlogyplot,vtext)          DrawVtext
set methodProc(logxlogyplot,plot)           DrawData
set methodProc(logxlogyplot,dot)            DrawDot
set methodProc(logxlogyplot,labeldot)       DrawLabelDot
set methodProc(logxlogyplot,dotconfig)      DotConfigure
set methodProc(logxlogyplot,interval)       DrawLogInterval
set methodProc(logxlogyplot,trend)          DrawLogTrendLine
set methodProc(logxlogyplot,saveplot)       SavePlot
set methodProc(logxlogyplot,dataconfig)     DataConfig
set methodProc(logxlogyplot,xconfig)        XConfigLogXLogY
set methodProc(logxlogyplot,yconfig)        YConfigLogXLogY
set methodProc(logxlogyplot,xticklines)     DrawXTicklines
set methodProc(logxlogyplot,yticklines)     DrawYTicklines
set methodProc(logxlogyplot,background)     BackgroundColour
set methodProc(logxlogyplot,legendconfig)   LegendConfigure
set methodProc(logxlogyplot,legend)         DrawLegend
set methodProc(logxlogyplot,removefromlegend) RemoveFromLegend
set methodProc(logxlogyplot,balloon)        DrawBalloon
set methodProc(logxlogyplot,balloonconfig)  ConfigBalloon
set methodProc(logxlogyplot,plaintext)      DrawPlainText
set methodProc(logxlogyplot,plaintextconfig) ConfigPlainText
set methodProc(logxlogyplot,canvas)         GetCanvas
set methodProc(piechart,title)              DrawTitle
set methodProc(piechart,plot)               DrawPie
set methodProc(piechart,saveplot)           SavePlot
set methodProc(piechart,balloon)            DrawBalloon
set methodProc(piechart,balloonconfig)      ConfigBalloon
set methodProc(piechart,explode)            PieExplodeSegment
set methodProc(piechart,plaintext)          DrawPlainText
set methodProc(piechart,plaintextconfig)    ConfigPlainText
set methodProc(piechart,colours)            SetColours
set methodProc(piechart,drawobject)         DrawObject
set methodProc(piechart,object)             DrawObject
set methodProc(piechart,canvas)             GetCanvas
set methodProc(spiralpie,title)             DrawTitle
set methodProc(spiralpie,plot)              DrawSpiralPie
set methodProc(spiralpie,saveplot)          SavePlot
set methodProc(spiralpie,balloon)           DrawBalloon
set methodProc(spiralpie,balloonconfig)     ConfigBalloon
set methodProc(spiralpie,plaintext)         DrawPlainText
set methodProc(spiralpie,plaintextconfig)   ConfigPlainText
set methodProc(spiralpie,colours)           SetColours
set methodProc(spiralpie,drawobject)        DrawObject
set methodProc(spiralpie,object)            DrawObject
set methodProc(spiralpie,canvas)            GetCanvas
set methodProc(polarplot,title)             DrawTitle
set methodProc(polarplot,plot)              DrawData
set methodProc(polarplot,saveplot)          SavePlot
set methodProc(polarplot,dataconfig)        DataConfig
set methodProc(polarplot,background)        BackgroundColour
set methodProc(polarplot,legendconfig)      LegendConfigure
set methodProc(polarplot,legend)            DrawLegend
set methodProc(polarplot,removefromlegend)  RemoveFromLegend
set methodProc(polarplot,balloon)           DrawBalloon
set methodProc(polarplot,balloonconfig)     ConfigBalloon
set methodProc(polarplot,plaintext)         DrawPlainText
set methodProc(polarplot,plaintextconfig)   ConfigPlainText
set methodProc(polarplot,labeldot)          DrawLabelDot
set methodProc(polarplot,canvas)            GetCanvas
set methodProc(histogram,title)             DrawTitle
set methodProc(histogram,xtext)             DrawXtext
set methodProc(histogram,ytext)             DrawYtext
set methodProc(histogram,vtext)             DrawVtext
set methodProc(histogram,plot)              DrawHistogramData
set methodProc(histogram,plotcumulative)    DrawHistogramCumulative
set methodProc(histogram,saveplot)          SavePlot
set methodProc(histogram,dataconfig)        DataConfig
set methodProc(histogram,xconfig)           XConfig
set methodProc(histogram,yconfig)           YConfig
set methodProc(histogram,yticklines)        DrawYTicklines
set methodProc(histogram,background)        BackgroundColour
set methodProc(histogram,legendconfig)      LegendConfigure
set methodProc(histogram,legend)            DrawLegend
set methodProc(histogram,removefromlegend)  RemoveFromLegend
set methodProc(histogram,balloon)           DrawBalloon
set methodProc(histogram,balloonconfig)     ConfigBalloon
set methodProc(histogram,plaintext)         DrawPlainText
set methodProc(histogram,plaintextconfig)   ConfigPlainText
set methodProc(histogram,canvas)            GetCanvas
set methodProc(horizbars,title)             DrawTitle
set methodProc(horizbars,xtext)             DrawXtext
set methodProc(horizbars,ytext)             DrawYtext
set methodProc(horizbars,vtext)             DrawVtext
set methodProc(horizbars,plot)              DrawHorizBarData
set methodProc(horizbars,xticklines)        DrawXTicklines
set methodProc(horizbars,background)        BackgroundColour
set methodProc(horizbars,saveplot)          SavePlot
set methodProc(horizbars,colours)           SetColours
set methodProc(horizbars,colors)            SetColours
set methodProc(horizbars,xconfig)           XConfig
set methodProc(horizbars,config)            ConfigBar
set methodProc(horizbars,legendconfig)      LegendConfigure
set methodProc(horizbars,legend)            DrawLegend
set methodProc(horizbars,removefromlegend)  RemoveFromLegend
set methodProc(horizbars,balloon)           DrawBalloon
set methodProc(horizbars,balloonconfig)     ConfigBalloon
set methodProc(horizbars,plaintext)         DrawPlainText
set methodProc(horizbars,plaintextconfig)   ConfigPlainText
set methodProc(horizbars,drawobject)        DrawObject
set methodProc(horizbars,object)            DrawObject
set methodProc(horizbars,canvas)            GetCanvas
set methodProc(vertbars,title)              DrawTitle
set methodProc(vertbars,xtext)              DrawXtext
set methodProc(vertbars,ytext)              DrawYtext
set methodProc(vertbars,vtext)              DrawVtext
set methodProc(vertbars,plot)               DrawVertBarData
set methodProc(vertbars,background)         BackgroundColour
set methodProc(vertbars,yticklines)         DrawYTicklines
set methodProc(vertbars,saveplot)           SavePlot
set methodProc(vertbars,colours)            SetColours
set methodProc(vertbars,colors)             SetColours
set methodProc(vertbars,yconfig)            YConfig
set methodProc(vertbars,config)             ConfigBar
set methodProc(vertbars,legendconfig)       LegendConfigure
set methodProc(vertbars,legend)             DrawLegend
set methodProc(vertbars,removefromlegend)   RemoveFromLegend
set methodProc(vertbars,balloon)            DrawBalloon
set methodProc(vertbars,balloonconfig)      ConfigBalloon
set methodProc(vertbars,plaintext)          DrawPlainText
set methodProc(vertbars,plaintextconfig)    ConfigPlainText
set methodProc(vertbars,drawobject)         DrawObject
set methodProc(vertbars,object)             DrawObject
set methodProc(vertbars,canvas)             GetCanvas
set methodProc(timechart,title)             DrawTitle
set methodProc(timechart,period)            DrawTimePeriod
set methodProc(timechart,milestone)         DrawTimeMilestone
set methodProc(timechart,vertline)          DrawTimeVertLine
set methodProc(timechart,saveplot)          SavePlot
set methodProc(timechart,background)        BackgroundColour
set methodProc(timechart,balloon)           DrawBalloon
set methodProc(timechart,balloonconfig)     ConfigBalloon
set methodProc(timechart,plaintext)         DrawPlainText
set methodProc(timechart,plaintextconfig)   ConfigPlainText
set methodProc(timechart,hscroll)           ConnectHorizScrollbar
set methodProc(timechart,vscroll)           ConnectVertScrollbar
set methodProc(timechart,canvas)            GetCanvas
set methodProc(ganttchart,title)            DrawTitle
set methodProc(ganttchart,period)           DrawGanttPeriod
set methodProc(ganttchart,task)             DrawGanttPeriod
set methodProc(ganttchart,milestone)        DrawGanttMilestone
set methodProc(ganttchart,vertline)         DrawGanttVertLine
set methodProc(ganttchart,saveplot)         SavePlot
set methodProc(ganttchart,color)            GanttColor
set methodProc(ganttchart,colour)           GanttColor
set methodProc(ganttchart,font)             GanttFont
set methodProc(ganttchart,connect)          DrawGanttConnect
set methodProc(ganttchart,summary)          DrawGanttSummary
set methodProc(ganttchart,background)       BackgroundColour
set methodProc(ganttchart,balloon)          DrawBalloon
set methodProc(ganttchart,balloonconfig)    ConfigBalloon
set methodProc(ganttchart,plaintext)        DrawPlainText
set methodProc(ganttchart,plaintextconfig)  ConfigPlainText
set methodProc(ganttchart,hscroll)          ConnectHorizScrollbar
set methodProc(ganttchart,vscroll)          ConnectVertScrollbar
set methodProc(ganttchart,canvas)           GetCanvas
set methodProc(stripchart,title)            DrawTitle
set methodProc(stripchart,xtext)            DrawXtext
set methodProc(stripchart,ytext)            DrawYtext
set methodProc(stripchart,vtext)            DrawVtext
set methodProc(stripchart,plot)             DrawStripData
set methodProc(stripchart,saveplot)         SavePlot
set methodProc(stripchart,dataconfig)       DataConfig
set methodProc(stripchart,xconfig)          XConfig
set methodProc(stripchart,yconfig)          YConfig
set methodProc(stripchart,yticklines)       DrawYTicklines
set methodProc(stripchart,background)       BackgroundColour
set methodProc(stripchart,legendconfig)     LegendConfigure
set methodProc(stripchart,legend)           DrawLegend
set methodProc(stripchart,removefromlegend) RemoveFromLegend
set methodProc(stripchart,balloon)          DrawBalloon
set methodProc(stripchart,balloonconfig)    ConfigBalloon
set methodProc(stripchart,plaintext)        DrawPlainText
set methodProc(stripchart,plaintextconfig)  ConfigPlainText
set methodProc(stripchart,drawobject)       DrawObject
set methodProc(stripchart,object)           DrawObject
set methodProc(stripchart,canvas)           GetCanvas
set methodProc(isometric,title)             DrawTitle
set methodProc(isometric,xtext)             DrawXtext
set methodProc(isometric,ytext)             DrawYtext
set methodProc(isometric,vtext)             DrawVtext
set methodProc(isometric,plot)              DrawIsometricData
set methodProc(isometric,saveplot)          SavePlot
set methodProc(isometric,background)        BackgroundColour
set methodProc(isometric,balloon)           DrawBalloon
set methodProc(isometric,balloonconfig)     ConfigBalloon
set methodProc(isometric,plaintext)         DrawPlainText
set methodProc(isometric,plaintextconfig)   ConfigPlainText
set methodProc(isometric,canvas)            GetCanvas
set methodProc(3dplot,title)                DrawTitle
set methodProc(3dplot,plotfunc)             Draw3DFunction
set methodProc(3dplot,plotdata)             Draw3DData
set methodProc(3dplot,plotline)             Draw3DLineFrom3Dcoordinates
set methodProc(3dplot,gridsize)             GridSize3D
set methodProc(3dplot,ribbon)               Draw3DRibbon
set methodProc(3dplot,saveplot)             SavePlot
set methodProc(3dplot,colour)               SetColours
set methodProc(3dplot,color)                SetColours
set methodProc(3dplot,xconfig)              XConfig
set methodProc(3dplot,yconfig)              YConfig
set methodProc(3dplot,zconfig)              ZConfig
set methodProc(3dplot,plotfuncont)          Draw3DFunctionContour
set methodProc(3dplot,background)           BackgroundColour
set methodProc(3dplot,canvas)               GetCanvas
set methodProc(3dbars,title)                DrawTitle
set methodProc(3dbars,plot)                 Draw3DBar
set methodProc(3dbars,yconfig)              YConfig
set methodProc(3dbars,saveplot)             SavePlot
set methodProc(3dbars,config)               Config3DBar
set methodProc(3dbars,balloon)              DrawBalloon
set methodProc(3dbars,balloonconfig)        ConfigBalloon
set methodProc(3dbars,plaintext)            DrawPlainText
set methodProc(3dbars,plaintextconfig)      ConfigPlainText
set methodProc(3dbars,canvas)               GetCanvas
set methodProc(radialchart,title)           DrawTitle
set methodProc(radialchart,plot)            DrawRadial
set methodProc(radialchart,saveplot)        SavePlot
set methodProc(radialchart,balloon)         DrawBalloon
set methodProc(radialchart,plaintext)       DrawPlainText
set methodProc(radialchart,plaintextconfig) ConfigPlainText
set methodProc(radialchart,canvas)          GetCanvas
set methodProc(txplot,title)                DrawTitle
set methodProc(txplot,xtext)                DrawXtext
set methodProc(txplot,ytext)                DrawYtext
set methodProc(txplot,vtext)                DrawVtext
set methodProc(txplot,plot)                 DrawTimeData
set methodProc(txplot,interval)             DrawInterval
set methodProc(txplot,saveplot)             SavePlot
set methodProc(txplot,dataconfig)           DataConfig
set methodProc(txplot,xconfig)              XConfig
set methodProc(txplot,yconfig)              YConfig
set methodProc(txplot,xticklines)           DrawXTicklines
set methodProc(txplot,yticklines)           DrawYTicklines
set methodProc(txplot,background)           BackgroundColour
set methodProc(txplot,legendconfig)         LegendConfigure
set methodProc(txplot,legend)               DrawLegend
set methodProc(txplot,removefromlegend)     RemoveFromLegend
set methodProc(txplot,balloon)              DrawTimeBalloon
set methodProc(txplot,balloonconfig)        ConfigBalloon
set methodProc(txplot,plaintext)            DrawTimePlainText
set methodProc(txplot,plaintextconfig)      ConfigPlainText
set methodProc(txplot,canvas)               GetCanvas
set methodProc(3dribbon,title)              DrawTitle
set methodProc(3dribbon,saveplot)           SavePlot
set methodProc(3dribbon,line)               Draw3DLine
set methodProc(3dribbon,area)               Draw3DArea
set methodProc(3dribbon,background)         BackgroundColour
set methodProc(3dribbon,canvas)             GetCanvas
set methodProc(boxplot,title)               DrawTitle
set methodProc(boxplot,xtext)               DrawXtext
set methodProc(boxplot,ytext)               DrawYtext
set methodProc(boxplot,vtext)               DrawVtext
set methodProc(boxplot,plot)                DrawBoxData
set methodProc(boxplot,saveplot)            SavePlot
set methodProc(boxplot,dataconfig)          DataConfig
set methodProc(boxplot,xconfig)             XConfig
set methodProc(boxplot,yconfig)             YConfig
set methodProc(boxplot,xticklines)          DrawXTicklines
set methodProc(boxplot,yticklines)          DrawYTicklines
set methodProc(boxplot,background)          BackgroundColour
set methodProc(boxplot,legendconfig)        LegendConfigure
set methodProc(boxplot,legend)              DrawLegend
set methodProc(boxplot,removefromlegend)    RemoveFromLegend
set methodProc(boxplot,balloon)             DrawBalloon
set methodProc(boxplot,balloonconfig)       ConfigBalloon
set methodProc(boxplot,plaintext)           DrawPlainText
set methodProc(boxplot,plaintextconfig)     ConfigPlainText
set methodProc(boxplot,drawobject)          DrawObject
set methodProc(boxplot,object)              DrawObject
set methodProc(boxplot,canvas)              GetCanvas
set methodProc(windrose,plot)               DrawWindRoseData
set methodProc(windrose,saveplot)           SavePlot
set methodProc(windrose,title)              DrawTitle
set methodProc(windrose,canvas)             GetCanvas
set methodProc(targetdiagram,title)         DrawTitle
set methodProc(targetdiagram,xtext)         DrawXtext
set methodProc(targetdiagram,ytext)         DrawYtext
set methodProc(targetdiagram,vtext)         DrawVtext
set methodProc(targetdiagram,plot)          DrawTargetData
set methodProc(targetdiagram,saveplot)      SavePlot
set methodProc(targetdiagram,background)    BackgroundColour
set methodProc(targetdiagram,legendconfig)  LegendConfigure
set methodProc(targetdiagram,legend)        DrawLegend
set methodProc(targetdiagram,removefromlegend) RemoveFromLegend
set methodProc(targetdiagram,balloon)       DrawBalloon
set methodProc(targetdiagram,balloonconfig) ConfigBalloon
set methodProc(targetdiagram,plaintext)     DrawPlainText
set methodProc(targetdiagram,plaintextconfig) ConfigPlainText
set methodProc(targetdiagram,dataconfig)    DataConfig
set methodProc(targetdiagram,canvas)        GetCanvas
set methodProc(3dribbonplot,title)          DrawTitle
set methodProc(3dribbonplot,plot)           Draw3DRibbon
set methodProc(3dribbonplot,saveplot)       SavePlot
set methodProc(3dribbonplot,xconfig)        XConfig
set methodProc(3dribbonplot,yconfig)        YConfig
set methodProc(3dribbonplot,zconfig)        ZConfig
set methodProc(3dribbonplot,background)     BackgroundColour
set methodProc(3dribbonplot,canvas)         GetCanvas
set methodProc(performance,title)           DrawTitle
set methodProc(performance,xtext)           DrawXtext
set methodProc(performance,ytext)           DrawYtext
set methodProc(performance,vtext)           DrawVtext
set methodProc(performance,plot)            DrawPerformanceData
set methodProc(performance,dot)             DrawDot
set methodProc(performance,saveplot)        SavePlot
set methodProc(performance,dataconfig)      DataConfig
set methodProc(performance,xconfig)         XConfig
set methodProc(performance,yconfig)         YConfig
set methodProc(performance,xticklines)      DrawXTicklines
set methodProc(performance,yticklines)      DrawYTicklines
set methodProc(performance,background)      BackgroundColour
set methodProc(performance,legendconfig)    LegendConfigure
set methodProc(performance,legend)          DrawLegend
set methodProc(performance,removefromlegend) RemoveFromLegend
set methodProc(performance,balloon)         DrawBalloon
set methodProc(performance,balloonconfig)   ConfigBalloon
set methodProc(performance,plaintext)       DrawPlainText
set methodProc(performance,plaintextconfig) ConfigPlainText
set methodProc(performance,canvas)          GetCanvas
set methodProc(table,title)                 DrawTitle
set methodProc(table,row)                   DrawRow
set methodProc(table,separator)             DrawSeparator
set methodProc(table,cellconfigure)         ConfigureTableCell
set methodProc(table,formatcommand)         SetFormatCommand
set methodProc(table,cellcoordinates)       TableCellCoordinates
set methodProc(table,worldcoordinates)      TableWorldCoordinates
set methodProc(table,topixels)              TableWorldToPixels
set methodProc(table,canvas)                GetCanvas

#
# Auxiliary parameters
#
set torad [expr {3.1415926/180.0}]

set options       {-colour -color  -symbol -type -filled -fillcolour \
                   -boxwidth -width -radius -whisker -whiskerwidth \
                   -mediancolour -medianwidth -style}
set option_keys   {-colour -colour -symbol -type -filled -fillcolour -boxwidth \
                   -width -radius -whisker -whiskerwidth -mediancolour \
                   -medianwidth -style}
set option_values {-colour       {...}
                   -symbol       {plus cross circle up down dot upfilled downfilled}
                   -type         {line symbol both rectangle}
                   -filled       {no up down}
                   -fillcolour   {...}
                   -mediancolour {...}
                   -medianwidth  {...}
                   -boxwidth     {...}
                   -width        {...}
                   -radius       {...}
                   -whisker      {IQR iqr extremes none}
                   -whiskerwidth {...}
                   -style        {filled spike symbol plateau stair}
                  }

set axis_options       {-format -ticklength -ticklines -scale -minorticks \
                        -labeloffset -axisoffset}
set axis_option_clear  { 0       0           0          1      0           0            0         }
set axis_option_config { 0       1           0          0      1           1            1         }
set axis_option_values {-format      {...}
                        -ticklength  {...}
                        -ticklines   {0 1}
                        -scale       {...}
                        -minorticks  {...}
                        -labeloffset {...}
                        -axisoffset  {...}
                       }

array set pattern {lines {} dots1 {1 4} dots2 {1 8} dots3 {1 12} dots4 {1 16} dots5 {4 24}}

