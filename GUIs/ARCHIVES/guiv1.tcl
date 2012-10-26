set platform "pc"

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

if {[string match $platform "mac"]} {
    set file C:/Users/flb.EECS/Desktop/eZ430-RF2500/GUI/capture.txt"
    set width [lindex $screensize 0]
    set height [expr [lindex $screensize 1] - 100]
} elseif {[string match $platform "pc"]} {
    set file "C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/GUI/capture.txt"
    set width [lindex $screensize 0]
    set height [expr [lindex $screensize 1] - 100]
} elseif {[string match $platform "macos"]} {
}

proc create_graph {xmn xmx} {
    global receiverlinecolor senderlinecolor voltagelinecolor
    global backgroundcolor
    global width height
    global xtick ymin ymax ytick rymin rymax rytick
    global showvoltage

    destroy .c
    destroy .f

    canvas .c -background white -width $width -height $height
    pack   .c -fill both

    frame .f
    button .f.stop -text "Stop" -command {set state "stop"}
    pack .f.stop -side left
    button .f.go -text "Go" -command {set state "go"}
    pack .f.go -side left
    button .f.exit -text "Exit" -command {set state "exit"}
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

proc plotpoint {} {
    global state
    global file
    global timestamp
    global series
    global xmin xmax xspan
    global showvoltage

    puts "state = $state"

    if {[string match $state "stop"]} {
        after 1000 plotpoint
        return
    }

    if {[string match $state "exit"]} {
        exit
    }

    set fd [open $file]

    seek $fd -50 end
    if {[gets $fd one] != 24 || [gets $fd other] != 24} {
        puts "bad string length"
        after 1000 plotpoint
        return
    }

    if {![regexp "^\\$" $one] || ![regexp "^\\$" $other]} {
        puts "bad string format: one = $one, other = $other"
        after 1000 plotpoint
        return
    }

    close $fd

    if {[string match "\$HUB0*" $one] && [string match "\$0002*" $other]} { 
        set receiver [split $one ',']
        set sender [split $other ',']
    } elseif {[string match "\$0002*" $one] && [string match "\$HUB0*" $other]} {
        set sender [split $one ',']
        set receiver [split $other ',']
    } else {
        puts "consecutive samples from same node"
        after 1000 plotpoint
        return
    }

    set receivertemp [string trim [lindex $receiver 1] " F"]
    set receivervoltage [lindex $receiver 2]
    set sendertemp  [string trim [lindex $sender 1] " F"]
    set sendervoltage [lindex $sender 2]
    set senderstrength [lindex $sender 3]

    if {![string is double -strict $receivertemp]} {
        puts "bad basestation temp"
        after 1000 plotpoint
        return
    }

    if {![string is double -strict $sendertemp]} {
        puts "bad sendor temp"
        after 1000 plotpoint
        return
    }

    if {![string is double -strict $senderstrength]} {
        puts "bad sender RSSI"
        after 1000 plotpoint
        return
    }

    set timestamp [expr $timestamp + 1]

    if {[expr $timestamp == $xmax]} {
        puts timestamp
        set xmin $timestamp
        set xmax [expr $xmin + $xspan] 
        set series [create_graph $xmin $xmax]
    }

    set leftside [lindex $series 0]
    $leftside plot receiver $timestamp $receivertemp
    $leftside plot sender $timestamp $sendertemp

    if {$showvoltage} {
        set rightside [lindex $series 1]
        $rightside plot voltage $timestamp $sendervoltage
    }

    puts "sender = $sendertemp, $sendervoltage, $senderstrength"
    puts "receiver = $receivertemp, $receivervoltage"
    puts "timestamp = $timestamp"
    puts ""

    after 1000 plotpoint
}

set timestamp 0
set state go

set series [create_graph $xmin $xmax]

after 1000 plotpoint

#while {$run} {
#    if {[string match $a "go"]} {
#        after 1000 plotpoint
#        vwait doneflag
#    } else {
#        after 1000
#    }
#}

