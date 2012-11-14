To create a stand-alone exe from a tcltk script that uses plotchart:

1) Make sure there are no source commands in your script (must be all in one file).

2) Import plotchart_flat.tcl into your script (cat plotchart_flat.tcl >> yourfile.tcl)

3) Run freewrap using this command line:

     <path to freewrap.exe> tclscript.tcl -o outputtckscript.exe <-i iconfile>

   Example:

     C:\Users\flb.bwrclt61-1\Desktop\eZ430-RF2500\GUIs\wrap\freewrap.exe gui_unified_exe.tcl -o gui_unified.exe <-i iconfile>


