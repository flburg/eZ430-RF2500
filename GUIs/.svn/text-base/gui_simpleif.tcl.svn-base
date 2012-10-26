##
## These may need to be set
##
set platform "pc"
set comport    3
set baudrate   57600
set parity     n
set databits   8
set stopbits   1
##

package require Plotchart

set showvoltage 0

set screensize [wm maxsize .]

set backgroundcolor "#df8080"
set receiverlinecolor "#ffffff"
set senderlinecolor "#000000"
set voltagelinecolor "#00ff00"

set xspan 100.0
set xmin 0.0
set xmax $xspan
set xtick [expr $xspan / 10]

set ymin 70.0
set ymax 100.0
set ytick 1.0

set rymin 1.0
set rymax 4.0
set rytick 0.1

set logfile "log_gui.txt"

if {[string match $platform "mac"]} {
    set width [lindex $screensize 0]
    set height [expr [lindex $screensize 1] - 100]
} elseif {[string match $platform "pc"]} {
    set width [lindex $screensize 0]
    set height [expr [lindex $screensize 1] - 100]
} else {
    set width [lindex $screensize 0]
    set height [expr [lindex $screensize 1] - 100]
}

proc create_graph {xmn xmx} {
    global receiverlinecolor senderlinecolor voltagelinecolor
    global backgroundcolor
    global width height
    global xtick ymin ymax ytick rymin rymax rytick
    global showvoltage
    global logfd

    destroy .c
    destroy .f

    canvas .c -background white -width $width -height $height
    pack   .c -fill both

    frame .f
    button .f.stop -text "Stop" -command {set state "stop"}
    pack .f.stop -side left
    button .f.go -text "Go" -command {set state "go"}
    pack .f.go -side left
    button .f.exit -text "Exit" -command {close $logfd; exit}
    pack .f.exit -side left
    pack .f

    set s [::Plotchart::createXYPlot .c [list $xmn $xmx $xtick] [list $ymin $ymax $ytick]]

    set r ""
    if {$showvoltage} {
        set r [::Plotchart::createRightAxis .c [list $rymin $rymax $rytick]]
        $r ytext "Voltage"
        $r dataconfig voltage -colour $voltagelinecolor -width 3
        $s legend voltage "sensor voltage"
    }

    $s title "Real-Time Temperature Plot"
    $s xtext "seconds"
    $s ytext "degrees F"
    $s background "gradient" $backgroundcolor "right"
    # transparent legend background
    $s legendconfig -background ""

    $s dataconfig receiver -colour $receiverlinecolor -width 3
    $s legend receiver "basestation temp"

    $s dataconfig sender -colour $senderlinecolor -width 3
    $s legend sender "sensor temp"

    return [list $s $r]
}

proc plotpoint {node temp volt rssi} {
    global timestamp
    global series
    global xmin xmax xspan
    global showvoltage

    set leftside [lindex $series 0]

    if {![string match "\$HUB0*" $node]} { 
        $leftside plot sender $timestamp $temp

        if {$showvoltage} {
            set rightside [lindex $series 1]
            $rightside plot voltage $timestamp $volt
        }

        # Hub sets the time base.
        set timestamp [expr $timestamp + 1]
    } elseif {![string match "\$0002*" $node]} {
        $leftside plot receiver $timestamp $temp
    } else {
        puts "bad parse: $node"
        return -1
    }

    if {[expr $timestamp == $xmax]} {
        puts timestamp
        set xmin $timestamp
        set xmax [expr $xmin + $xspan] 
        set series [create_graph $xmin $xmax]
    }

    puts "node = $node, temp = $temp, $volt, $rssi"
    puts "timestamp = $timestamp"
    puts ""

    return $timestamp
}

proc read_port {comfd logfd} {
    global state

    if {[string match $state "stop"]} {
        return
    }

    if {[gets $comfd line] != 24} {
        return
    }

    if {![regexp "^\\$" $line]} {
        puts "bad string format: $line"
        return
    }

    set buf [split $line ',']
    set node [lindex $buf 0]
    set temp [string trim [lindex $buf 1] " F"]
    set voltage [lindex $buf 2]
    set rssi [lindex $buf 3]

    if {![string is double -strict $temp]} {
        puts "bad temp: $node $temp $voltage $rssi"
        return
    }
    if {![string is double -strict $rssi]} {
        puts "bad RSSI: $node $temp $voltage $rssi"
        return
    }

    set time [plotpoint $node $temp $voltage $rssi]

    if {$time != -1} {
        puts $logfd "$time $node $temp $voltage $rssi"
        flush $logfd
    }
}

proc open_com {} {
    global comport
    global logfile
    global baudrate
    global parity
    global databits
    global stopbits
    global logfd

    set logfd [open $logfile w+]

    set comfd [open com$comport: r+]
    fconfigure $comfd -mode $baudrate,$parity,$databits,$stopbits \
      -blocking 0 -translation auto -buffering none -buffersize 12

    fileevent $comfd readable [list read_port $comfd $logfd]
}

set timestamp 0
set state go

set series [create_graph $xmin $xmax]

open_com

#after 1000 plotpoint

#while {$run} {
#    if {[string match $a "go"]} {
#        after 1000 plotpoint
#        vwait doneflag
#    } else {
#        after 1000
#    }
#}

