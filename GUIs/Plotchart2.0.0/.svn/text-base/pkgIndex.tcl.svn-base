
# @@ Meta Begin
# Package Plotchart 2.0.0
# Meta activestatetags ActiveTcl Public Tklib
# Meta as::build::date 2012-03-31
# Meta as::origin      http://sourceforge.net/projects/tcllib
# Meta category        Plotchart
# Meta description     Simple plotting and charting package
# Meta license         BSD
# Meta platform        tcl
# Meta recommend       math::fuzzy
# Meta require         Img
# Meta require         {Tcl 8.4}
# Meta require         Tk
# Meta subject         {polar plots} {coordinate transformations} tables
# Meta subject         {time charts} charts {graphical presentation}
# Meta subject         xy-plots plotting {isometric plots} {bar charts}
# Meta subject         coordinates {pie charts} {3D surfaces} {strip charts}
# Meta subject         {3D bars}
# Meta summary         Plotchart
# @@ Meta End


if {![package vsatisfies [package provide Tcl] 8.4]} return

package ifneeded Plotchart 2.0.0 [string map [list @ $dir] {
            source [file join {@} plotchart.tcl]

        # ACTIVESTATE TEAPOT-PKG BEGIN DECLARE

        package provide Plotchart 2.0.0

        # ACTIVESTATE TEAPOT-PKG END DECLARE
    }]
