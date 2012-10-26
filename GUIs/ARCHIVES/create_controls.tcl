set paramnames [list temperature voltage pressure rssi]
set paramstate [list 0 0 0 0]
set minimums [list 50 2.0 0 0]
set maximums [list 90 4.0 500 50]

proc create_controls {} {
    global paramnames nparamstate
    global minimums maximums
    global state 
    global logfd

    catch {destroy .controls}

    frame .controls
    pack .controls
    
    set w .controls.datafields
    
    frame $w -bg blue
    pack $w -side top
    
    frame $w.headers
    pack $w.headers -side top -fill x -padx 2m -pady 2m
    
    label $w.headers.track -bg red -fg white -text "Track" -justify center -width 12
    pack $w.headers.track -side left
    
    label $w.headers.ymin -bg red -fg white -text "YMin" -justify center -width 10
    pack $w.headers.ymin -side left

    label $w.headers.ymax -bg red -fg white -text "YMax" -justify center -width 10
    pack $w.headers.ymax -side left
    
    foreach param $paramnames {
        frame $w.$param 
        pack $w.$param -side top -fill x

	global ${param}on
        checkbutton $w.$param.b -variable ${param}on -text $param -width 12 -anchor w
        pack $w.$param.b -side left

	global ${param}min
	set ${param}min [lindex $minimums [lsearch $paramnames $param]]
        entry $w.$param.mn -textvariable ${param}min -width 10
        pack $w.$param.mn -side left

	global ${param}max
	set ${param}max [lindex $maximums [lsearch $paramnames $param]]
        entry $w.$param.mx -textvariable ${param}max -width 10
        pack $w.$param.mx -side left
    }
    
    set w .controls.buttons

    frame $w
    pack $w -side top -pady 3m

    button $w.stop -text "Stop" -command {set state "stop"} -relief raised
    pack $w.stop -side left -padx 2m

    button $w.go -text "Go" -command {set state "go"} -relief raised
    pack $w.go -side left -padx 2m

    button $w.exit -text "Exit" -command {close $logfd; exit} -relief raised
    pack $w.exit -side left -padx 2m
}


