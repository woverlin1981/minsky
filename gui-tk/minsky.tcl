#  @copyright Steve Keen 2012
#  @author Russell Standish
#  This file is part of Minsky.
#
#  Minsky is free software: you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  Minsky is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with Minsky.  If not, see <http://www.gnu.org/licenses/>.
#

# disable tear-off menus

set fname ""
set workDir [pwd]

# On mac-build versions, fontconfig needs to find its config file,
# which is packaged up in the Minsky.app directory

if {$tcl_platform(os)=="Darwin" && [file exists $minskyHome/../Resources/fontconfig/fonts.conf]} {
        set env(FONTCONFIG_FILE) $minskyHome/../Resources/fontconfig/fonts.conf
}


# default canvas size. Overridden by previously resized window size
# saved in .minskyrc
set canvasWidth 600
set canvasHeight 800
set backgroundColour lightGray
set preferences(nRecentFiles) 10
set recentFiles {}

# select Arial Unicode MS by default, as this gives decent Unicode support
switch $tcl_platform(os) {
    "Darwin" -
    "windows" {minsky.defaultFont "Arial Unicode MS"}
}

# read in .rc file, which differs on Windows and unix
set rcfile ""
if {$tcl_platform(platform)=="unix"} {
  set rcfile "$env(HOME)/.minskyrc"
} elseif {$tcl_platform(platform)=="windows"} {
  set rcfile "$env(USERPROFILE)/.minskyrc"
}
if [file exists $rcfile] {
  catch {source $rcfile}
}

# for some reason (MingW I'm looking at you), tcl_library sometimes
# points to Minsky's library directory
if {![file exists [file join $tcl_library init.tcl]] || 
    [file normalize $tcl_library]==[file normalize $minskyHome/library]} {
    set tcl_library $minskyHome/library/tcl
}


# hopefully, we can now rely on TCL/Tk to find its own libraries.
if {![info exists tk_library]} {
  regsub tcl [file tail [info library]] tk tk_library
  set tk_library [file join [file dirname [info library]] $tk_library]
}
if {![file exists [file join $tk_library tk.tcl]]
} {
    set tk_library $minskyHome/library/tk
}

# In a rather bizarre set of events, namely Aqua build, launched via
# launch services, on a non-developer machine, Tk will instantiate a
# second TCL interpreter to host a console. Unfortunately, it uses the
# original heuristics to find the TCL and TK libraries, which fail,
# causing the application to hang. Setting these environment variables
# cuts through that problem. See ticket #675.
set env(TCL_LIBRARY) $tcl_library
set env(TK_LIBRARY) $tk_library

proc setFname {name} {
    global fname workDir
    if [string length $name] {
        set fname $name
        set workDir [file dirname $name]
        catch {wm title . "Minsky: $fname"}
    }
}

# needed for scripts/tests
rename exit tcl_exit

#if argv(1) has .tcl extension, it is a script, otherwise it is data
if {$argc>1} {
    if [string match "*.tcl" $argv(1)] {
        source $argv(1)
    }
}

source $tcl_library/init.tcl

if {$tcl_platform(os)=="Darwin"} {
    if {[catch {GUI}] || [catch {source [file join $tk_library tk.tcl]}]} {
    # pop a message box about installing XQuartz
    exec osascript << "tell application \"System Events\"
    activate
    display dialog \"GUI failed to initialise, try installing XQuartz\"
    end tell"
}
} else {
    GUI
    source [file join $tk_library tk.tcl]
}

source [file join $tk_library bgerror.tcl]
source $minskyHome/library/init.tcl
source $minskyHome/helpRefDb.tcl

disableEventProcessing

# Tk's implementation of bgerror does not mark the error dialog as
# transient, creating a usability problem where a user could hide the
# dialog, and wonder why the application is not responding.
rename ::tk::SetFocusGrab ::tk::SetFocusGrab_
proc ::tk::SetFocusGrab {grab focus} {
  ::tk::SetFocusGrab_ $grab $focus
  wm attributes $grab -topmost 1
  wm transient $grab .
}

catch {console hide}

proc setBackgroundColour bgc {
    global backgroundColour
    set backgroundColour $bgc
    tk_setPalette $bgc
    # tk_setPalette doesn't understand ttk widgets
    ttk::style configure TNotebook -background $backgroundColour
    ttk::style configure TNotebook.Tab -background $backgroundColour
    ttk::style map TNotebook.Tab -background "selected $bgc active $bgc"
}

option add *Menu.tearOff 0
wm deiconify .
tk appname [file rootname [file tail $argv(0)]]
wm title . "Minsky: $fname" 
setBackgroundColour $backgroundColour
tk_focusFollowsMouse

if {[tk windowingsystem]=="win32"} {
    # redirect the mousewheel event to the actual window that should
    # receive the event - see ticket #114 
    bind . <MouseWheel> {
        switch [winfo containing %X %Y] {
            .wiring.canvas {
                if {%D>=0} {
                    # on Winblows, min val of |%D| is 120, so just use sign
                    zoomAt %x %y 1.1
                } {
                    zoomAt %x %y [expr 1.0/1.1]
                } 
            }
        }
    }
}

source $minskyHome/library/tooltip.tcl
namespace import tooltip::tooltip

source $minskyHome/library/obj-browser.tcl

# Macs have a weird numbering of mouse buttons, so lets virtualise B2 & B3
# see http://wiki.tcl.tk/14728
if {[tk windowingsystem] == "aqua"} {
    event add <<contextMenu>> <Button-2> <Control-Button-1>
    event add <<middleMouse>> <Button-3>
    event add <<middleMouse-Motion>> <B3-Motion>
    event add <<middleMouse-ButtonRelease>> <B3-ButtonRelease>
} else {
    event add <<contextMenu>> <Button-3>
    event add <<middleMouse>> <Button-2>
    event add <<middleMouse-Motion>> <B2-Motion>
    event add <<middleMouse-ButtonRelease>> <B2-ButtonRelease>
}

use_namespace minsky

proc deiconify {widget} {
    wm deiconify $widget
    after idle "wm deiconify $widget; raise $widget; focus -force $widget"
}

#labelframe .menubar -relief raised
menu .menubar -type menubar

if {[tk windowingsystem] == "aqua"} {
    menu .menubar.apple
    .menubar.apple add command -label "About Minsky" -command aboutMinsky
    .menubar add cascade -menu .menubar.apple
    set meta Command
    set meta_menu Cmd

# handle opening of files once Minsky is in flight
    proc ::tk::mac::OpenDocument {args} {
        # only support opening a single document at a time
        if {[llength $args]>0} {openNamedFile [lindex $args 0]}
    }
    proc ::tk::mac::ShowPreferences {} {showPreferences}
    proc ::tk::mac::ShowHelp {} {help Introduction}
}

menu .menubar.file
.menubar add cascade -menu .menubar.file -label File -underline 0

menu .menubar.edit
.menubar add cascade -menu .menubar.edit -label Edit -underline 0


menu .menubar.ops
.menubar add cascade -menu .menubar.ops -label Insert -underline 0

menu .menubar.options
.menubar add cascade -menu .menubar.options -label Options -underline 0
.menubar.options add command -label "Preferences" -command showPreferences

# add rows to this table to add new preferences
# valid types are "text", "bool" and "{ enum label1 val1 label2 val2 ... }"
#   varName              Label                    DefaultVal    type
set preferencesVars {
    godleyDE             "Godley Table Double Entry"     1      bool
    godleyDisplay        "Godley Table Show Values"      1      bool
    godleyDisplayStyle       "Godley Table Output Style"    sign  { enum
        "DR/CR" DRCR
        "+/-" sign } 
    nRecentFiles          "Number of recent files to display" 10 text
    wrapLaTeXLines        "Wrap long equations in LaTeX export" 1 bool
}
lappend preferencesVars defaultFont "Font" [defaultFont] font

foreach {var text default type} $preferencesVars {
    # don't override value set in the rc file
    if {![info exists preferences($var)]} {
        set preferences($var) $default
    }
}
            
proc showPreferences {} {
    global preferences_input preferences preferencesVars
    foreach var [array names preferences] {
	set preferences_input($var) $preferences($var)
    }

    if {![winfo exists .preferencesForm]} {
        toplevel .preferencesForm
        wm resizable .preferencesForm 0 0

        set row 0
        
        grid [label .preferencesForm.label$row -text "Preferences"] -column 1 -columnspan 999 -pady 10
        incr row 10

        # pad the left and right
        grid [frame .preferencesForm.f1] -column 1 -row 1 -rowspan 999 -padx 10
        grid [frame .preferencesForm.f2] -column 999 -row 1 -rowspan 999 -padx 10
        

        foreach {var text default type} $preferencesVars {
            set rowdict($text) $row

            grid [label .preferencesForm.label$row -text $text] -column 10 -row $row -sticky e -pady 5
            
            switch $type {
                text {
                    grid [entry  .preferencesForm.text$row -width 20 -textvariable preferences_input($var)] -column 20 -row $row -sticky ew -columnspan 999
                }
                bool {
                    grid [checkbutton .preferencesForm.cb$row -variable preferences_input($var)] -row $row -column 20 -sticky w
                }
                font {
                    grid [ttk::combobox .preferencesForm.font -textvariable preferences_input($var) -values [lsort [listFonts]] -state readonly] -row $row -column 20 -sticky w
                    bind .preferencesForm.font <<ComboboxSelected>> {
                        defaultFont [.preferencesForm.font get]
                        canvas.requestRedraw
                    }
                }
                default {
                    if {[llength $type] > 1} {
                        switch [lindex $type 0] {
                            enum {
                                set column 20
                                foreach {valtext val} [lrange $type 1 end] {
                                    grid [radiobutton .preferencesForm.rb${row}v$column  -text $valtext -variable preferences_input($var) -value $val] -row $row -column $column
                                    incr column 
                                }
                            }
                        }
                    } else { error "unknown preferences widget $type" }
                }
            }
            
            incr row 10
        }
        
        set preferences(initial_focus) ".preferencesForm.cb$rowdict(Godley Table Double Entry)"
        
        frame .preferencesForm.buttonBar
        button .preferencesForm.buttonBar.ok -text OK -command {setPreferenceParms; closePreferencesForm;updateGodleysDisplay}
        button .preferencesForm.buttonBar.cancel -text cancel -command {closePreferencesForm}
        pack .preferencesForm.buttonBar.ok [label .preferencesForm.buttonBar.spacer -width 2] .preferencesForm.buttonBar.cancel -side left -pady 10
        grid .preferencesForm.buttonBar -column 1 -row 999 -columnspan 999
        
        bind .preferencesForm <Key-Return> {invokeOKorCancel .preferencesForm.buttonBar}

        wm title .preferencesForm "Preferences"

    }

    deiconify .preferencesForm
    update idletasks
    ::tk::TabToWindow $preferences(initial_focus)
    tkwait visibility .preferencesForm
    grab set .preferencesForm
    wm transient .preferencesForm .
}

.menubar.options add command -label "Background Colour" -command {
    set bgc [tk_chooseColor -initialcolor $backgroundColour]
    if {$bgc!=""} {
        set backgroundColour $bgc
        setBackgroundColour $backgroundColour
    }
}

menu .menubar.rungeKutta
.menubar.rungeKutta add command -label "Runge Kutta" -command {
    foreach {var text} $rkVars { set rkVarInput($var) [$var] }
    set implicitSolver [implicit]
    deiconifyRKDataForm
    update idletasks
    ::tk::TabToWindow $rkVarInput(initial_focus)
    tkwait visibility .rkDataForm
    grab set .rkDataForm
    wm transient .rkDataForm .
} -underline 0 
.menubar add cascade -label "Runge Kutta" -menu .menubar.rungeKutta

# special platform specific menus
menu .menubar.help
if {[tk windowingsystem] != "aqua"} {
    .menubar.help add command -label "Minsky Documentation" -command {help Introduction}
}
.menubar add cascade -label Help -menu .menubar.help

bind . <F1> topLevelHelp
bind .menubar.file <F1> {help File}


# placement of menu items in menubar
. configure -menu .menubar 

# controls toolbar 

labelframe .controls
label .controls.statusbar -text "t: 0 Δt: 0"

# classic mode
set classicMode 0

if {$classicMode} {
    button .controls.run -text run -command runstop
    button .controls.reset -text reset -command reset
    button .controls.step -text step -command {step}
} else {
    image create photo runButton -file "$minskyHome/icons/Play.gif" 
    image create photo stopButton -file "$minskyHome/icons/Pause.gif"
    image create photo resetButton -file "$minskyHome/icons/Rewind.gif"
    image create photo stepButton -file "$minskyHome/icons/Last.gif"
    # iconic mode
    button .controls.run -image runButton -height 25 -width 25 -command runstop
    button .controls.reset -image resetButton -height 25 -width 25 -command reset
    button .controls.step -image stepButton -height 25 -width 25  -command {step}
    tooltip .controls.run "Run/Stop"
    tooltip .controls.reset "Reset simulation"
    tooltip .controls.step "Step simulation"
}

# enable auto-repeat on step button
bind .controls.step <ButtonPress-1> {set buttonPressed 1; autoRepeatButton .controls.step}
bind . <ButtonRelease-1> {set buttonPressed 0}

# self submitting script that continues while a button is pressed
proc invokeButton button {
    global buttonPressed
    if {$buttonPressed} {
        $button invoke
        update
        autoRepeatButton $button
    }
}

proc autoRepeatButton button {
    after 500 invokeButton $button
}

label .controls.slowSpeed -text "slow"
label .controls.fastSpeed -text "fast"
scale .controls.simSpeed -variable delay -command setSimulationDelay -to 0 -from 12 -length 150 -label "Simulation Speed" -orient horizontal -showvalue 0

# keyboard accelerator introducer, which is different on macs
set meta Control
set meta_menu Ctrl



pack .controls.run .controls.reset .controls.step .controls.slowSpeed .controls.simSpeed .controls.fastSpeed -side left
pack .controls.statusbar -side right -fill x

grid .controls -row 0 -column 0 -columnspan 1000 -sticky ew

menu .menubar.file.recent

# File menu
.menubar.file add command -label "About Minsky" -command aboutMinsky
.menubar.file add command -label "New System" -command newSystem  -underline 0 -accelerator $meta_menu-N
.menubar.file add command -label "Open" -command openFile -underline 0 -accelerator $meta_menu-O
.menubar.file add cascade -label "Recent Files"  -menu .menubar.file.recent
.menubar.file add command -label "Library"  -command "openURL https://github.com/highperformancecoder/minsky-models"

.menubar.file add command -label "Save" -command save -underline 0 -accelerator $meta_menu-S
.menubar.file add command -label "SaveAs" -command saveAs 
.menubar.file add command -label "Insert File as Group" -command insertFile

.menubar.file add command -label "Export Canvas" -command exportCanvas

proc exportCanvas {} {
    global workDir type fname preferences

    set f [tk_getSaveFile -filetypes {
        {"SVG" svg TEXT} {"PDF" pdf TEXT} {"Postscript" eps TEXT} {"LaTeX" tex TEXT} {"Matlab" m TEXT}} \
               -initialdir $workDir -typevariable type -initialfile [file rootname [file tail $fname]]]  
    if {$f==""} return
    if [string match -nocase *.svg "$f"] {
        minsky.renderCanvasToSVG "$f"
    } elseif [string match -nocase *.pdf "$f"] {
        minsky.renderCanvasToPDF "$f"
    } elseif {[string match -nocase *.ps "$f"] || [string match -nocase *.eps "$f"]} {
        minsky.renderCanvasToPS "$f"
    } elseif {[string match -nocase *.tex "$f"]} {
        latex "$f" $preferences(wrapLaTeXLines)
    } elseif {[string match -nocase *.m "$f"]} {
        matlab "$f"
    } else {
        switch -glob $type {
            "*(svg)" {minsky.renderCanvasToSVG  "$f.svg"}
            "*(pdf)" {minsky.renderCanvasToPDF "$f.pdf"}
            "*(eps)" {minsky.renderCanvasToPS "$f.eps"}
            "*(tex)" {latex "$f.tex" $preferences(wrapLaTeXLines)}
            "*(m)" {matlab "$f.m"}
        }
    }
}

.menubar.file add checkbutton -label "Log simulation" -variable simLogging \
    -command {
        openLogFile [tk_getSaveFile -defaultextension .dat -initialdir $workDir]
    }
.menubar.file add checkbutton -label "Recording" -command toggleRecording -variable eventRecording
.menubar.file add checkbutton -label "Replay recording" -command replay -variable recordingReplay 
    
.menubar.file add command -label "Quit" -command exit -underline 0 -accelerator $meta_menu-Q
.menubar.file add separator
.menubar.file add command  -foreground #5f5f5f -label "Debugging Use"
.menubar.file add command -label "Redraw" -command canvas.requestRedraw
.menubar.file add command -label "Object Browser" -command obj_browser
.menubar.file add command -label "Select items" -command selectItems
.menubar.file add command -label "Command" -command cli

.menubar.edit add command -label "Undo" -command "undo 1" -accelerator $meta_menu-Z
.menubar.edit add command -label "Redo" -command "undo -1" -accelerator $meta_menu-Y
.menubar.edit add command -label "Cut" -command cut -accelerator $meta_menu-X
.menubar.edit add command -label "Copy" -command minsky.copy -accelerator $meta_menu-C
.menubar.edit add command -label "Paste" -command {paste} -accelerator $meta_menu-V
.menubar.edit add command -label "Group selection" -command "minsky.createGroup" -accelerator $meta_menu-G

menu .menubar.file.itemTypes
proc selectItems {} {
    .menubar.file.itemTypes delete 0 end
    foreach i [wiringGroup.types] {
        .menubar.file.itemTypes add command -label $i \
            -command "filterOnType $i; obj_browser wiringGroup.filteredItems.*"
    }
    .menubar.file.itemTypes post [winfo pointerx .] [winfo pointery .]
}

proc undo {delta} {
    # do not record changes to state from the undo command
    doPushHistory 0
    minsky.undo $delta
    doPushHistory 1
}


proc cut {} {
    minsky.cut
}

wm protocol . WM_DELETE_WINDOW exit
# keyboard accelerators
bind . <$meta-s> save
bind . <$meta-o> openFile
bind . <$meta-n> newSystem
bind . <$meta-q> exit
bind . <$meta-y> "undo -1"
bind . <$meta-z> "undo 1"
bind . <$meta-x> {minsky.cut}
bind . <$meta-c> {minsky.copy}
bind . <$meta-v> {paste}
bind . <$meta-g> {minsky.createGroup}

# tabbed manager
ttk::notebook .tabs
ttk::notebook::enableTraversal .tabs
grid .tabs -column 0 -row 10 -sticky news
grid columnconfigure . 0 -weight 1
grid rowconfigure . 10 -weight 1

source $minskyHome/godley.tcl
source $minskyHome/wiring.tcl
source $minskyHome/plots.tcl
source $minskyHome/group.tcl

# add the tabbed windows
.tabs add .wiring -text "Wiring"

image create cairoSurface renderedEquations -surface minsky.equationDisplay
#-file $minskyHome/icons/plot.gif
ttk::frame .equations 
label .equations.canvas -image renderedEquations -height $canvasHeight -width $canvasWidth
pack .equations.canvas -fill both -expand 1
.tabs add .equations -text equations
.tabs select 0

proc panCanvases {offsx offsy} {
    model.moveTo $offsx $offsy
    equationDisplay.offsx $offsx
    equationDisplay.offsy $offsy
    set x0 [expr (10000-$offsx)/20000.0]
    .hscroll set $x0 [expr $x0+[winfo width .wiring.canvas]/20000.0]
    set y0 [expr (10000-$offsy)/20000.0]
    .vscroll set $y0 [expr $y0+[winfo height .wiring.canvas]/20000.0]
    canvas.requestRedraw
    equationDisplay.requestRedraw
}

ttk::sizegrip .sizegrip
proc scrollCanvases {xyview args} {
    switch [lindex $args 0] {
        moveto {
            set offs [expr 10000 - 20000 * [lindex $args 1]]
            switch $xyview {
                xview {panCanvases $offs [model.y]}
                yview {panCanvases [model.x] $offs}
            }
        }
        scroll {
            switch [lindex $args 2] {
                units {set incr [expr [lindex $args 1]*100]}
                pages {set incr [expr [lindex $args 1]*800]}
            }
            switch $xyview {
                xview {panCanvases [expr [model.x]+$incr] [model.y]}
                yview {panCanvases [model.x] [expr [model.y]+$incr]}
            }
        }
    }
}
scrollbar .vscroll -orient vertical -command "scrollCanvases yview"
scrollbar .hscroll -orient horiz -command "scrollCanvases xview"
panCanvases 0 0

# adjust cursor for pan mode
if {[tk windowingsystem] == "aqua"} {
    set panIcon closedhand
} else {
    set panIcon fleur
}

# equations pan mode
.equations.canvas configure -cursor $panIcon
bind .equations.canvas <Button-1> {set panOffsX [expr %x-[model.x]]; set panOffsY [expr %y-[model.y]]}
bind .equations.canvas <B1-Motion> {panCanvases [expr %x-$panOffsX] [expr %y-$panOffsY]}

grid .sizegrip -row 999 -column 999
grid .vscroll -column 999 -row 10 -rowspan 989 -sticky ns
grid .hscroll -row 999 -column 0 -columnspan 999 -sticky ew

image create photo zoomOutImg -file $minskyHome/icons/zoomOut.gif
button .controls.zoomOut -image zoomOutImg -height 24 -width 37 \
    -command {zoom 0.91}
tooltip .controls.zoomOut "Zoom Out"

image create photo zoomInImg -file $minskyHome/icons/zoomIn.gif
button .controls.zoomIn -image zoomInImg -height 24 -width 37 \
    -command {zoom 1.1}
tooltip .controls.zoomIn "Zoom In"

image create photo zoomOrigImg -file $minskyHome/icons/zoomOrig.gif
button .controls.zoomOrig -image zoomOrigImg -height 24 -width 37 \
    -command {
        if {[model.zoomFactor]>0} {zoom [expr 1/[model.zoomFactor]]} else {model.setZoom 1}
        recentreCanvas
    }
tooltip .controls.zoomOrig "Reset Zoom/Origin"
pack .controls.zoomOut .controls.zoomIn .controls.zoomOrig -side left

set delay [simulationDelay]
set running 0

proc runstop {} {
  global running classicMode
  if {$running} {
    set running 0
    doPushHistory 1
    if {$classicMode} {
            .controls.run configure -text run
        } else {
            .controls.run configure -image runButton
        }
  } else {
      set running 1
      doPushHistory 0
      if {$classicMode} {
          .controls.run configure -text stop
      } else {
          .controls.run configure -image stopButton
      }
      step
      simulate
  }
}

proc step {} {
    global recordingReplay eventRecordR
    if {$recordingReplay} {
        if {[gets $eventRecordR cmd]>=0} {
            eval $cmd
            update
        } else {
            runstop
            close $eventRecordR
            set recordingReplay 0
        }
    } else {
        # run simulation
        global running
        set lastt [t]
        if {[catch minsky.step errMsg options] && $running} {runstop}
        .controls.statusbar configure -text "t: [t] Δt: [format %g [expr [t]-$lastt]]"
        updateGodleysDisplay
        update
        return -options $options $errMsg
    }
}


proc simulate {} {
    uplevel #0 {
      if {$running} {
          if {$recordingReplay} {
              # don't slow down recording quite so much (lots of mouse
              # movements)
              after [expr $delay/25+0] {step; simulate}
          } else {
              set d [expr int(pow(10,$delay/4.0))]
              after $d {
                  if {$running} {
                      if [reset_flag] runstop else {
                          step
                          simulate
                      }
                  }
              }
          }
        }
    }
}

proc reset {} {
    global running recordingReplay eventRecordR simLogging
    set running 0
    if {$recordingReplay} {
        seek $eventRecordR 0 start
    } else {
        set tstep 0
        set simLogging 0
        closeLogFile
        # delay throwing exception to allow display to be updated
        set err [catch minsky.reset result]
        .controls.statusbar configure -text "t: 0 Δt: 0"
        .controls.run configure -image runButton

        global oplist lastOp
        set oplist [opOrder]
        updateGodleysDisplay
        set lastOp -1
        return -code $err $result
    }
}

proc setSimulationDelay {delay} {
    # on loading a model, slider is adjusted, which causes
    # simulationDelay to be set unnecessarily, marking the model
    # dirty
    if {$delay != [simulationDelay]} {
        pushFlags
        simulationDelay $delay
        popFlags
    }
}


proc populateRecentFiles {} {
    global recentFiles preferences
    .menubar.file.recent delete 0 end
    if {[llength $recentFiles]>$preferences(nRecentFiles)} {
        set recentFiles [lreplace $recentFiles $preferences(nRecentFiles) end]
    }
    foreach f $recentFiles {
        .menubar.file.recent add command -label "[file tail $f]" \
            -command "openNamedFile \"[regsub -all {\\} $f /]\""
    }
}
populateRecentFiles

# load/save 

proc openFile {} {
    global fname workDir preferences
    set ofname [tk_getOpenFile -multiple 1 -filetypes {
	    {Minsky {.mky}} {XML {.xml}} {All {.*}}} -initialdir $workDir]
    if [string length $ofname] {openNamedFile $ofname}
}

proc openNamedFile {ofname} {
    global fname workDir preferences
    newSystem
    setFname $ofname

    eval minsky.load $fname
    doPushHistory 0
    pushFlags
    recentreCanvas
    

#    foreach g [godleyItems.#keys] {
#        godley.get $g
#        set preferences(godleyDE) [godley.table.doubleEntryCompliant]
#    }

   .controls.simSpeed set [simulationDelay]
    # setting preferences(godleyDE) and simulationDelay causes the edited (dirty) flag to be set
    popFlags
    doPushHistory 1
}

proc insertFile {} {
    global workDir
    set fname [tk_getOpenFile -multiple 1 -filetypes {
	    {Minsky {.mky}} {XML {.xml}} {All {.*}}} -initialdir $workDir]
    insertNewGroup [insertGroupFromFile $fname]
}

proc insertNewGroup {gid} {
    newGroupItem $gid

    global moveOffsgroup$gid.x moveOffsgroup$gid.y

    group.get $gid
    moveSet $gid [group.x] [group.y] 
    move $gid [get_pointer_x .old_wiring.canvas] [get_pointer_y .old_wiring.canvas]

    bind .old_wiring.canvas <Enter> "move $gid %x %y"
    bind .old_wiring.canvas <Motion> "move $gid %x %y"
    bind .old_wiring.canvas <Button-1> \
        "bind .old_wiring.canvas <Motion> {}
         bind .old_wiring.canvas <Enter> {}
         bind .old_wiring.canvas <Button-1>{}
         # redo this here, as binding on a group undoes it
#         initGroupList $gid
         move $gid %x %y
         checkAddGroup $gid %x %y
#         setInteractionMode"
}

# adjust canvas so that -ve coordinates appear on canvas
proc recentreCanvas {} {
    canvas.recentre
    equationDisplay.offsx 0
    equationDisplay.offsy 0
    equationDisplay.requestRedraw
}

proc save {} {
    global fname
    if {![string length $fname]} {
	    setFname [tk_getSaveFile -defaultextension .mky]}            
    if [string length $fname] {
        minsky.save $fname
    }
}

proc saveAs {} {
    global fname workDir
    setFname [tk_getSaveFile -defaultextension .mky -initialdir $workDir]
    if [string length $fname] {
        minsky.save $fname
    }
}

proc newSystem {} {
    if [edited] {
        switch [tk_messageBox -message "Save?" -type yesnocancel] {
            yes save
            no {}
            cancel {return -level [info level]}
        }
    }
    reset
    model.clear
    deleteSubsidiaryTopLevels
    clearHistory
    model.setZoom 1
    recentreCanvas
    global fname
    set fname ""
    wm title . "Minsky: New System"
}

proc toggleImplicitSolver {} {
    global implicitSolver
    implicit $implicitSolver
}

# invokes OK or cancel button with given window, depending on current focus
proc invokeOKorCancel {window} {
    if [string equal [focus] "$window.cancel"] {
            $window.cancel invoke
        } else {
            $window.ok invoke
        }
}

set rkVars {
    stepMin   "Min Step Size"
    stepMax   "Max Step Size"
    nSteps     "no. steps per iteration"
    epsAbs     "Absolute error"
    epsRel     "Relative error"
    order      "Solver order (1,2 or 4)"
}

proc deiconifyRKDataForm {} {
    if {![winfo exists .rkDataForm]} {
        global rkVarInput rkVars
        toplevel .rkDataForm
        wm resizable .rkDataForm 0 0

        set row 0

        grid [label .rkDataForm.label$row -text "Runge-Kutta parameters"] -column 1 -columnspan 999 -pady 10
        incr row 10

        foreach {var text} $rkVars {
            set rowdict($text) $row
            grid [label .rkDataForm.label$row -text $text] -column 10 -row $row -sticky e
            grid [entry  .rkDataForm.text$row -width 20 -textvariable rkVarInput($var)] -column 20 -row $row -sticky ew
            incr row 10
        }
        grid [label .rkDataForm.implicitlabel -text "Implicit solver"] -column 10 -row $row -sticky e
        grid [checkbutton  .rkDataForm.implicitcheck -variable implicitSolver -command toggleImplicitSolver] -column 20 -row $row -sticky ew

        set rkVarInput(initial_focus) ".rkDataForm.text$rowdict(Min Step Size)"
        frame .rkDataForm.buttonBar
        button .rkDataForm.buttonBar.ok -text OK -command {setRKparms; closeRKDataForm}
        button .rkDataForm.buttonBar.cancel -text cancel -command {closeRKDataForm}
        pack .rkDataForm.buttonBar.ok [label .rkDataForm.buttonBar.spacer -width 2] .rkDataForm.buttonBar.cancel -side left -pady 10
        grid .rkDataForm.buttonBar -column 1 -row 999 -columnspan 999
        
        bind .rkDataForm <Key-Return> {invokeOKorCancel .rkDataForm.buttonBar}

        wm title .rkDataForm "Runge-Kutta parameters"
        # help bindings
        bind .rkDataForm  <F1>  {help RungeKutta}
        global helpTopics
        set helpTopics(.rkDataForm) RungeKutta
        bind .rkDataForm  <<contextMenu>> {helpContext %X %Y}
    } else {
        deiconify .rkDataForm
    }
}

proc closeRKDataForm {} {
    grab release .rkDataForm
    wm withdraw .rkDataForm
}

proc setRKparms {} {
    global rkVars rkVarInput
    foreach {var text} $rkVars { $var $rkVarInput($var) }
}


proc closePreferencesForm {} {
    grab release .preferencesForm
    wm withdraw .preferencesForm
}

proc setPreferenceParms {} {
    global preferencesVars preferences preferences_input

    foreach var [array names preferences_input] {
	set preferences($var) $preferences_input($var)
    }
    defaultFont $preferences(defaultFont)
}




# context sensitive help topics associations
set helpTopics(.#menubar) Menu
set helpTopics(.menubar.file) File
set helpTopics(.menubar.edit) Edit
set helpTopics(.menubar.ops) Insert
set helpTopics(.menubar.options) Options
set helpTopics(.controls.run) RunButtons
set helpTopics(.controls.reset) RunButtons
set helpTopics(.controls.step) RunButtons
set helpTopics(.controls.simSpeed) Speedslider
set helpTopics(.controls.statusbar) SimTime
set helpTopics(.controls.zoomOut) ZoomButtons
set helpTopics(.controls.zoomIn) ZoomButtons
set helpTopics(.controls.zoomOrig)  ZoomButtons
# TODO - the following association interferes with canvas item context menus
# set helpTopics(.wiring.canvas) DesignCanvas


menu .contextHelp -tearoff 0
foreach win [array names helpTopics] {
    bind $win <<contextMenu>> {helpContext %X %Y}
}

# for binding to F1
proc topLevelHelp {} {
    helpFor [winfo pointerx .] [winfo pointery .]
}

# for binding to context menus
proc helpContext {x y} {
    .contextHelp delete 0 end
    .contextHelp add command -label Help -command "helpFor $x $y"
    tk_popup .contextHelp $x $y
}

# implements context sensistive help
proc helpFor {x y} {
    global helpTopics
    set win [winfo containing $x $y]
    if {$win==".wiring.canvas"} {
        canvasHelp
    } elseif [info exists helpTopics($win)] {
        help $helpTopics($win)
    } else {
        help Introduction
    }
}

proc canvasHelp {} {
    set x [get_pointer_x .wiring.canvas]
    set y [get_pointer_y .wiring.canvas]
    if [getItemAt $x $y] {
        help [minsky.canvas.item.classType]
    } elseif [getWireAt $x $y] {
        help wire
    } else {help DesignCanvas}
}

proc openURL {URL} {
    global tcl_platform
    if {[tk windowingsystem]=="win32"} {
        shellOpen $URL
    } elseif {$tcl_platform(os)=="Darwin"} {
        exec open $URL
    } else {
        # try a few likely suspects
        foreach browser {firefox konqueror seamonkey opera} {
            set browserNotFound [catch {exec firefox $URL &}]
            if {!$browserNotFound} break
        }
        if $browserNotFound {
            tk_messageBox -detail "Unable to find a working web browser, 
please consult $URL" -type ok -icon warning
        }
    }
}

proc help {topic} {
    global minskyHome externalLabel
    # replace "Introduction" to framed toplevel document
    # TODO - see if it is possible to wrap the deep links with a framed service
    if {$topic=="Introduction"} {
        set URL  "file://$minskyHome/library/help/minsky.html"
    } else {
        set URL  "file://$minskyHome/library/help/minsky.html?minsky$externalLabel($topic)#$topic"
    }
    openURL $URL
}

proc aboutMinsky {} {
    if {![winfo exists .aboutMinsky]} {
        toplevel .aboutMinsky
        wm resizable .aboutMinsky 0 0
        label .aboutMinsky.text

        button .aboutMinsky.ok -text OK -command {
            grab release .aboutMinsky
            wm withdraw .aboutMinsky
        }
        pack .aboutMinsky.text .aboutMinsky.ok
    }
    .aboutMinsky.text configure -text "
   Minsky [minskyVersion]\n
   EcoLab [ecolabVersion]\n
   Tcl/Tk [info tclversion]

   Minsky is FREE software, distributed under the 
   GNU General Public License. It comes with ABSOLUTELY NO WARRANTY. 
   See http://www.gnu.org/licenses/ for details
   " 
    deiconify .aboutMinsky 

    # wierd trick to resize toplevel windows:
    update idletasks
    wm geometry .aboutMinsky

    tkwait visibility .aboutMinsky
    grab set .aboutMinsky
    wm transient .aboutMinsky .
}

# delete subsidiary toplevel such as godleys and plots
proc deleteSubsidiaryTopLevels {} {
    global globals

    canvas.defaultRotation 0
    set globals(godley_tables) {}

    foreach w [info commands .godley*] {destroy $w}
    foreach w [info commands .plot*] {destroy $w}
    foreach image [image names] {
        if [regexp ".plot.*|godleyImage.*|groupImage.*|varImage.*|opImage.*|plot_image.*" $image] {
                image delete $image
            }
    }
}

proc exit {} {
    # check if the model has been saved yet
    if [edited] {
        switch [tk_messageBox -message "Save before exiting?" -type yesnocancel] {
            yes save
            no {}
            cancel {return -level [info level]}
        }
    }

    #persist coverage database to disk (if coverage testing performed)
    if [llength [info commands cov.close]] cov.close
    # disable coverage testing
    proc traceProc {args} {}

    # if we have a valid rc file location, write out the directory of
    # the last file loaded
    global rcfile workDir backgroundColour preferences recentFiles
    if {$rcfile!=""} {
        set rc [open $rcfile w]
        puts $rc "set workDir $workDir"
        puts $rc "set canvasWidth [winfo width .wiring.canvas]"
        puts $rc "set canvasHeight [winfo height .wiring.canvas]"
        puts $rc "set backgroundColour $backgroundColour"
        foreach p [array names preferences] {
            puts $rc "set preferences($p) \{$preferences($p)\}"
        }
        puts $rc {minsky.defaultFont $preferences(defaultFont)}
        puts $rc "set recentFiles \{$recentFiles\}"
        close $rc
    }
    # why is this needed?
    proc bgerror x {} 
    exit_ecolab
}

proc setFname {name} {
    global fname workDir recentFiles preferences
    if [string length $name] {
        set fname $name
        set workDir [file dirname $name]
        if {[lsearch $recentFiles $fname]==-1} {
            #add to recent files list
            if {[llength $recentFiles]>=$preferences(nRecentFiles)} {
                set recentFiles [lreplace $recentFiles 0 0]
            }
            lappend recentFiles $fname
            populateRecentFiles
        }
        # this strange piece of merde proved the only way I could test
        # for the presence of a close brace
        if {[regexp "\}$" $fname] && ![regexp "\}$" $workDir]} {
            set workDir "$workDir\}"
        }
        catch {wm title . "Minsky: $fname"}
    }
}

# commands to redirect to wiringGroup (via unknown mechanism)
set getters {wire op constant integral data var plot godley group switchItem item items wires}
foreach i $getters {
    foreach j [info commands $i.*] {rename $j {}}
}
    
rename unknown ecolab_unknown
proc unknown {procname args} {
    #delegate in case a getter hasn't correctly called its get
    global getters
    if [regexp ^wiringGroup\. $procname] {
        # delegate to minsky (ie global group)
        eval [regsub ^wiringGroup $procname minsky] $args
    } elseif [regexp ^([join $getters |])\. $procname] {
        eval wiringGroup.$procname $args
    } else {
        eval ecolab_unknown $procname $args
    }
}

pushFlags
if {$argc>1 && ![string match "*.tcl" $argv(1)]} {
    # ignore any exceptions thrown during load, in case it can be repaired later
    catch {minsky.load $argv(1)}
    doPushHistory 0
    setFname $argv(1)
    # we have loaded a Minsky model, so must refresh the canvas
    recentreCanvas
    if [findObject GodleyIcon] {
        # set the DE preference from one of the godley table, if present
        set preferences(godleyDE) [minsky.canvas.item.table.doubleEntryCompliant]
    }
    set delay [simulationDelay]
    pushHistory
    doPushHistory 1
    # force update canvas size to ensure model is displayed correctly
    update
    canvas.requestRedraw
}

#return 
proc ifDef {var} {
    upvar $var v
    if {$v!="??"} {
        return "-$var $v "
    } else {
        return ""
    }
}

proc addEvent {event window button height state width x y delta keysym subwindow} {
    global eventRecord eventRecording
    if {$eventRecording && [info exists eventRecord] && [llength [file channels $eventRecord]]} {
        set rec "event generate $window $event "
        foreach option {button height state width x y delta keysym} {
            # for some reason, the logic misses this one
            if {($event=="<Key>" || $event=="<KeyRelease>") && $option=="delta"} continue
            append rec [ifDef $option]
        }
        puts $eventRecord $rec
    }
}

proc startRecording {filename} {
    if {[string length $filename]>0} {
        minsky.startRecording $filename
        recentreCanvas
    }
}

proc stopRecording {} {
    minsky.stopRecording
}

proc toggleRecording {} {
    global eventRecording workDir
    if $eventRecording {
        startRecording [tk_getSaveFile -defaultextension .tcl -initialdir $workDir]
    } else {
        stopRecording
    }
}

# flag indicating we're in recording replay mode
set recordingReplay 0

proc replay {} {
    global recordingReplay eventRecordR workDir running
    if {$recordingReplay} {
        # ensures consistent IDs are allocated
        set fname [tk_getOpenFile -defaultextension .tcl -initialdir $workDir]
        if {[string length $fname]>0} {
            newSystem
            set eventRecordR [open $fname r]
            if {!$running} runstop
        } elseif {$running} {runstop}
    } 
}

## checks that the latest state has been pushed to history every second or so
#proc checkHistory {} {
#    global running
#    if {!$running} checkPushHistory
#    after 1000 checkHistory
#}
#after 1000 checkHistory

proc attachTraceProc {namesp} {
    foreach p [info commands $namesp*] {
        if {$p ne "::traceProc"} {
            trace add execution $p enterstep traceProc
        }
    }
    # recursively process child namespaces
    foreach n [namespace children $namesp] {
        attachTraceProc ${n}::
    }
}

# check whether coverage analysis is required
if [info exists env(MINSKY_COV)] {
#    trace add execution proc leave enableTraceProc
    proc traceProc {args} {
        array set frameInfo [info frame -2]
        if  {$frameInfo(type)=="proc"} {
            cov.add $frameInfo(proc) $frameInfo(line)
        }
        if  {$frameInfo(type)=="source"} {
            cov.add $frameInfo(file) $frameInfo(line)
        }
    }
# open coverage database, and set cache size
    Coverage cov
    cov.init $env(MINSKY_COV) w
    cov.max_elem 10000
# attach trace execuation to all created procs
    attachTraceProc ::
}


# a hook to allow code to be run after Minsky has initialised itself
if {[llength [info commands afterMinskyStarted]]>0} {
    afterMinskyStarted
}

disableEventProcessing
popFlags
