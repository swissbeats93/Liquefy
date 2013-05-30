#
#
#
# liquidgen plugin for VMD
# Setup a Molecular Liquid Simulation 
#
#
#
#
#

package provide liquify 1.0
package require psfgen
package require pbctools

# Setup namespace to prevent plugin conflicts
namespace eval ::liquify {
	#namespace export liquify
	
	# window handler
	variable w
	set w [toplevel .liquify]

	# Simulation parameters
	variable options

	# Constants
	variable PI
	#set PI $math::constants::pi
	set PI 3.1415926
}

# Build a window to allow user input of parameters
# $w will be passed by global liquify_tk to VMD
proc ::liquify::build_gui {} {
	variable w
	variable options
	wm title $w "Setup Molecular Liquid"

	set twidth 50 ;# text box width
	set nwidth 10 ;# number box width

	# Note: all options passed to Tk have to be qualified with namespace
	# or they refer to global vars
	
	# Frame containing PBD and PSF input fields
	# PDB File
	grid [labelframe $w.f1 -text "Load Molecule"] -columnspan 2 -rowspan 1

	set row 0
	foreach n {pdb psf top} {
		set bigname [string toupper $n]
		set l [label $w.f1.$n-l1 -text "$bigname File"]
		set e [entry $w.f1.$n-e1 -width $twidth -textvariable ::liquify::options($n)] 
		set cmd "set ::liquify::options($n) \[tk_getOpenFile\]"
		set b [button $w.f1.$n-b1 -text "Browse" -command $cmd]
		grid $l -column 0 -row $row
		grid $e -column 1 -row $row
		grid $b -column 2 -row $row
		incr row
	}
	
	# Frame containing box dimensions
	grid [labelframe $w.f2 -text "Box Dimensions"] -column 0 -row 1
	
	set row 0
	foreach n {x y z} {
		set e [entry $w.f2.$n-e1 -textvariable ::liquify::options($n) -width $nwidth \
		-validate key -vcmd {string is int %P}]
		#	-validate key -vcmd {string is int %P}]
		set l [label $w.f2.$n-l1 -text "$n"]
		grid $l -column 0 -row $row
		grid $e -column 1 -row $row
		incr row
	}

	set l [label $w.f2.l4 -text "Use Cube"]
	set c [checkbutton $w.f2.c1 -variable ::liquify::options(cube)]
	grid $l -column 2 -row 0
	grid $c -column 3 -row 0

	# Frame containing number iterations
	grid [labelframe $w.f4 -text "Runtime Options"] -column 1 -row 1

	set l [label $w.f4.l1 -text "Number of iterations"]
	set s [spinbox $w.f4.s1 -textvariable ::liquify::options(niter) \
		-from 100 -to 1000 -increment 50 -width $nwidth -validate key \
		-vcmd {string is int %P}]
	grid $l -column 0 -row 0
	grid $s -column 1 -row 0

	set l [label $w.f4.l2 -text "Use early rejection"]
	set c [checkbutton $w.f4.c1 -variable ::liquify::options(reject)]
	grid $l -column 0 -row 1
	grid $c -column 1 -row 1

	set l [label $w.f4.l3 -text "Density estimate\n(molecules/vol)"]
	set e [entry $w.f4.e1 -textvariable ::liquify::options(density) \
	-width $nwidth -validate key -vcmd {string is double %P}]
	grid $l -column 0 -row 2
	grid $e -column 1 -row 2

	# Save new PDB and PSF files
	# Click button save -> prompt for directory and name
	grid [labelframe $w.f3 -text "Save New Data"] -columnspan 2 -rowspan 1
	
	set l [label $w.f3.l1 -text "Location"] 
	set e [entry $w.f3.e1 -textvariable ::liquify::options(savedir) -width $twidth] 
	set cmd "set ::liquify::options(savedir) \[tk_chooseDirectory\]"
	set b [button $w.f3.b1 -text "Browse" -command $cmd]
	grid $l -column 0 -row 0
	grid $e -column 1 -row 0
	grid $b -column 2 -row 0

	set l [label $w.f3.l2 -text "Name"]
	set e [entry $w.f3.e2 -textvariable ::liquify::options(savefile) -width $twidth]
	set cmd "::liquify::save_files"
	set b [button $w.f3.b2 -text "Save PBD/PSF" -command $cmd]
	grid $l -column 0 -row 1
	grid $e -column 1 -row 1
	grid $b -column 2 -row 1
	
	# Frame containing generate and reset buttons
	grid [labelframe $w.f5 -text "Populate Box"] -columnspan 2 -rowspan 1

	set cmd "::liquify::populate"
	set b [button $w.f5.b1 -text "Fill!" -command $cmd]
	grid $b -column 0 -row 0

	set cmd "::liquify::reset"
	set b [button $w.f5.b2 -text "Reset" -command $cmd]
	grid $b -column 1 -row 0
}

#
# Save new PDB and PSF files
# 
proc ::liquify::save_files {name} {
	# TODO catch errors
	writepdb $name.pdb
	writepsf $name.psf
}

#
# Start populating the box
#
proc ::liquify::populate {} {
	variable PI
	variable options

	vmdcon -info "Reset display field..."

	# Remove any molecules currently loaded
	::liquify::clear_mols
	vmdcon -info "Populating..."

	# Add new molecule
	vmdcon -info "Loading PBD file \{$options(pdb)\}..."
	if [catch {mol new $options(pdb) type pdb} err] {
		vmdcon -info "Halting box fill!"
		return 1
	}
	vmdcon -info "...done"
	# Load structure information into new molecule
	vmdcon -info "Loading PSF data into new molecule..."
	if [catch {mol addfile $options(psf) type psf} err] {
		vmdcon -info "Halting box fill!"
		return 1
	}
	vmdcon -info "...done"
	topology $options(top)

	# Check box dimensions
	# values will be ints (entry validation)
	if $options(cube) {
		foreach i {y z} {
			set options($i) $options(x)
		}
	}
	foreach i {x y z} {
		if {$options($i) <= 0} {
			vmdcon -err "Box dimensions must be greater than 0!"
			vmdcon -info "Halting box fill!"
			return 1
		}
	}
	
	# Retrive info from parent molecule
	set atoms [atomselect top all] ;# Select all atoms
	set diam [vecdist {*}[measure minmax $atoms]] ;# Estimate molecular diameter
	set radius [expr $diam / 2.0] ;# Molecular radius
	set resnames [lsort -unique [$atoms get resname]] ;# Residue names
	mol delete [molinfo top]
	# Estimate number of molecules based on geometry
	set vol_box [expr $options(x) * $options(y) * $options(z)]
	set vol_sphere [expr 4.0 * $PI * ($radius**3) / 3.0]
	set num_mols [expr ($vol_box * $options(density)) / $vol_sphere]
	set num_mols [expr round($num_mols)]
	# TODO Need to find a way around this
	if {$num_mols > 999} {
		vmdcon -warn "Too many molecules (>999) would mess up segname. Halting."
		return 1
	}

	# Replicate parent molecule
	::liquify::generate_blanks $num_mols $resnames

	# It seems necessary to write to file and reload XXX
	::liquify::save_files tmp

	mol delete [molinfo top]
	mol load psf tmp.psf pdb tmp.pdb

	# Scatter molecules randomly around in the box
	::liquify::scatter_molecules $radius $com

	# Use pbctools to draw periodic box
	pbc set "$options(x) $options(y) $options(z)" -all
	pbc box -center origin ;# draw box

	::liquify::save_files tmp

	vmdcon -info "Finished molecule replication"
}

#
# Make n "blank" copies of parent molecule
# blank -> unassigned coordinates
# 
proc ::liquify::generate_blanks {n resnames} {
	variable options

	for {set i 0} {$i < $n} {incr i} {
		set segname S[format %03i $i]
		segment $segname {
			first NONE
			last NONE
			foreach resname $resnames {
				residue 1 $resname
			}
		}
		coordpdb $options(pdb) $segname
	}
}

#
# Set random coordinates for every molecule present
# Separation by segname
#
proc ::liquify::scatter_molecules {diam} {
	variable options
	# radius: estimated molecule radius

	set allatoms [atomselect top all]
	set segnames [lsort -unique [$allatoms get segname]]

	foreach segname $segnames {
		set atoms [atomselect top "segname $segname"]
		set com [measure center $atoms weight mass] ;# Center of mass
		set old_xyz [join [$atoms get {name x y z}]]
		set new_xyz {}
		set overlap 1
		set failures 0

		while {overlap} {
			incr failures
			foreach n {x y z} {
				$atoms move [transaxis $n [::liquify::random_angle]]
			}
			$atoms move [transoffset [::liquify::random_xyz]]
			set new_xyz [join [$atoms get {segid resid name x y z}]]
			set overlap 0

			foreach seg $segnames {
				if {$seg == $segname} continue ;# skip self-comparison

				set atoms2 [atomselect top "segname $seg"]
				set com2 [measure center $atoms2 weight mass]
				set dr [vecdist $com $com2]
				if {$options(reject) && $dr >= $diam} {
					puts "dr >= diam: $dr, $diam (no further comparison)"
					continue
				}
				puts "Thorough check for overlap"
				# TODO
			}
		} 

		foreach {segid resid name x y z} $new_xyz {
			coord $segid $resid $name "$x $y $z"
		}
	}
}

#
#
#

#
# Clear all input and loaded molecules
#
proc ::liquify::reset {} {
	variable options
	::liquify::clear_mols
	::liquify::set_defaults
}

#
# Reset input fields to default
#
proc ::liquify::set_defaults {} {
	variable options
	set options(niter) 10
	set options(pdb) "/home/leif/src/liquify/thiophene/thiophene.pdb"
	set options(psf) "/home/leif/src/liquify/thiophene/thiophene.psf"
	set options(cube) 0
	set options(reject) 0
	set options(density) 0.74 ;# hexagonal close packing for spheres
	foreach n {x y z} {
		set options($n) 25
	}
}

#
# Return {x y z} list of random points within periodic box
# 
proc ::liquify::random_xyz {} {
	variable options
	set dr {}
	foreach n {x y z} {
		set val [expr ($options($n) * rand()) - ($options($n) / 2.0)]
		lappend dr $val
	}
	return $dr
}

#
#
#
proc ::liquify::random_angle {} {
	return [expr (360.0 * rand())]
}

#
# Unload all molecules
# Reasoning: for setting up liquids -> no other molecules
# can just delete a few after to put in another foreign molecule
# if desired
#
proc ::liquify::clear_mols {} {
	vmdcon -info "Removing [molinfo num] molecules"
	set idlist [molinfo list]
	foreach id $idlist {
		mol delete $id
	}
	resetpsf
	vmdcon -info "...done"
}

#
# VMD menu calls this function when selected
#
proc ::liquify_tk {} {
	::liquify::set_defaults
	::liquify::build_gui
	return $liquify::w
}

#
# Need to validate user input
#
proc ::liquify::validate_input {} {
	variable options
	puts "Input validation..."
}
