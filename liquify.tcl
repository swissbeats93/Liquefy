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
	variable segname
	set segname LIQ

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
	::liquify::set_defaults
	wm title $w "Setup Molecular Liquid"

	set twidth 50 ;# text box width
	set nwidth 5 ;# number box width

	# Note: all options passed to Tk have to be qualified with namespace
	# or they refer to global vars
	
	# Frame containing PBD and PSF input fields
	# PDB File
	grid [labelframe $w.f1 -text "Load Molecule"] \
		-columnspan 2 -rowspan 1 -sticky news

	set row 0
	foreach n {pdb psf top} {
		set bigname [string toupper $n]
		set l [label $w.f1.$n-l1 -text "$bigname File"]
		set e [entry $w.f1.$n-e1 -width $twidth -textvariable ::liquify::options($n)] 
		set cmd "set ::liquify::options($n) \[tk_getOpenFile\]"
		set b [button $w.f1.$n-b1 -text "Browse" -command $cmd]
		grid $l -column 0 -row $row -sticky e
		grid $e -column 1 -row $row -sticky ew
		grid $b -column 2 -row $row -sticky w
		incr row
	}
	
	# Frame containing box dimensions
	grid [labelframe $w.f2 -text "Box Dimensions"] -column 0 -row 1 \
		-sticky news
	
	set row 0
	foreach n {x y z} {
		set e [entry $w.f2.$n-e1 -textvariable ::liquify::options($n) -width $nwidth \
		-validate key -vcmd {string is int %P}]
		#	-validate key -vcmd {string is int %P}]
		set l [label $w.f2.$n-l1 -text "$n"]
		grid $l -column 0 -row $row -sticky e
		grid $e -column 1 -row $row -sticky w
		incr row
	}

	set l [label $w.f2.l4 -text "Use Cube"]
	set c [checkbutton $w.f2.c1 -variable ::liquify::options(cube)]
	grid $l -column 2 -row 0 -sticky e
	grid $c -column 3 -row 0 -sticky w

	# Frame containing runtime options
	grid [labelframe $w.f4 -text "Runtime Options"] -column 1 -row 1 \
		-sticky news

	set l [label $w.f4.l1 -text "Failed iteration cutoff"]
	set s [spinbox $w.f4.s1 -textvariable ::liquify::options(niter) \
		-from 100 -to 1000 -increment 50 -width $nwidth -validate key \
		-vcmd {string is int %P}]
	grid $l -column 0 -row 0 -sticky e
	grid $s -column 1 -row 0 -sticky w

	set l [label $w.f4.l2 -text "Use early rejection"]
	set c [checkbutton $w.f4.c1 -variable ::liquify::options(reject)]
	grid $l -column 0 -row 1 -sticky e
	grid $c -column 1 -row 1 -sticky w

	set l [label $w.f4.l3 -text "Sphere packing estimate"]
	set e [entry $w.f4.e1 -textvariable ::liquify::options(density) \
	-width $nwidth -validate key -vcmd {string is double %P}]
	grid $l -column 0 -row 2 -sticky e
	grid $e -column 1 -row 2 -sticky w

	# Save new PDB and PSF files
	grid [labelframe $w.f3 -text "Save New Data"] \
		-columnspan 2 -rowspan 1 -sticky news
	
	set l [label $w.f3.l1 -text "Location"] 
	set e [entry $w.f3.e1 -textvariable ::liquify::options(savedir) -width $twidth] 
	set cmd "set ::liquify::options(savedir) \[tk_chooseDirectory\]"
	set b [button $w.f3.b1 -text "Browse" -command $cmd]
	grid $l -column 0 -row 0 -sticky e
	grid $e -column 1 -row 0 -sticky ew
	grid $b -column 2 -row 0 -sticky w

	set l [label $w.f3.l2 -text "Name"]
	set e [entry $w.f3.e2 -textvariable ::liquify::options(savefile) -width $twidth]
	set cmd "::liquify::save_reload"
	set b [button $w.f3.b2 -text "Save PBD/PSF" -command $cmd]
	grid $l -column 0 -row 1 -sticky e
	grid $e -column 1 -row 1 -sticky ew
	#grid $b -column 2 -row 1
	
	# Frame containing generate and reset buttons
	grid [labelframe $w.f5 -text "Populate Box"] \
		-columnspan 2 -rowspan 1 -sticky ns

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
proc ::liquify::save_reload {name} {
	# TODO catch errors
	writepdb $name.pdb
	writepsf $name.psf

	mol delete [molinfo top]
	mol load psf $name.psf pdb $name.pdb
}

#
# Start populating the box
#
proc ::liquify::populate {} {
	variable PI
	variable options
	variable base_coords

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
	set base_coords [$atoms get {resname name x y z}] ;# Use for relative atom coords
	set diam [vecdist {*}[measure minmax $atoms]] ;# Estimate molecular diameter
	set radius [expr $diam / 2.0] ;# Molecular radius
	set resnames [lsort -unique [$atoms get resname]] ;# Residue names
	mol delete [molinfo top] ;# Remove molecule
	# Estimate number of molecules based on geometry
	set vol_box [expr $options(x) * $options(y) * $options(z)]
	set vol_sphere [expr 4.0 * $PI * ($radius**3) / 3.0]
	set num_mols [expr ($vol_box * $options(density)) / $vol_sphere]
	set num_mols [expr round($num_mols)]
	# Residue names can only be 1-5 characters
	# could start adding new segments XXX
	if {$num_mols > 99999} {
		vmdcon -warn "Too many molecules (>99999) would mess up resid. Halting."
		return 1
	}

	# Replicate parent molecule
	::liquify::generate_blanks $num_mols $resnames

	# It seems necessary to write to file and reload XXX
	::liquify::save_reload $options(savefile)

	# Scatter molecules randomly around in the box
	vmdcon -info "Attempting to scatter $num_mols molecules..."
	::liquify::scatter_molecules $diam
	vmdcon -info "...done"

	::liquify::save_reload $options(savefile)

	# Use pbctools to draw periodic box
	pbc set "$options(x) $options(y) $options(z)" -all
	pbc box -center origin ;# draw box

	# Represent molecules in Licorice style
	mol modstyle 0 top Licorice 0.300000 10.000000 10.000000

	vmdcon -info "Finished molecule replication"

	# Save XSC file containing cell basis vectors
	vmdcon -info "Writing xsc file..."
	if ![::liquify::write_xsc] {
		vmdcon -err "Write to xsc file failed. Halting"
		return 1
	}
	vmdcon -info "...done"
}

#
# Make n "blank" copies of parent molecule
# blank -> unassigned coordinates
# 
proc ::liquify::generate_blanks {n resnames} {
	#variable options
	variable segname

	segment $segname {
		first NONE
		last NONE
		for {set i 0} {$i < $n} {incr i} {
			foreach resname $resnames {
				residue $i $resname
			}
		}
	}
}

#
# Set random coordinates for every molecule present
# Separation by resid
#
proc ::liquify::scatter_molecules {diam} {
	variable options
	variable base_coords
	variable segname

	set allatoms [atomselect top all]
	set resids [lsort -integer -unique [$allatoms get resid]]
	set delete_mols 0
	set placed {}

	# Setup box boundaries
	foreach n {x y z} {
		set max$n [expr $options(x) / 2.0]
		set min$n [expr -[subst \$max$n]]
	}

	# Move one molecule at a time
	foreach resid $resids {
		set atoms [atomselect top "resid $resid"]
		set new_xyz {}
		set pdata {}
		set overlap 1 ;# initially "overlapped"
		set failures 0

		# Skip moving/checking and delete the unplaced molecules
		if {$delete_mols} {
			delatom $segname $resid
			continue
		}

		# Set relative atom coordinates
		$atoms set {resname name x y z} $base_coords

		# Translate and rotate a molecule
		while {$overlap} {
			incr failures
			set new_xyz {}
			
			if {$failures > $options(niter)} {
				vmdcon -info "Reached max iterations for placing molecules at residue: $resid"
				set delete_mols 1
				delatom $segname $resid
				break
			}
			
			foreach n {x y z} {
				$atoms move [transaxis $n [::liquify::random_angle]]
			}
			# Store translation in case it needs to be reversed
			set offset [::liquify::random_xyz]
			$atoms move [transoffset $offset]
			set pdata [join [$atoms get {segid resid name x y z}]]
			# Center of geometry - calculate before wrapping atoms for PBC	
			set cog [measure center $atoms]

			# Adjust any atoms for PBC
			foreach {segid resid radius name x y z} \
				[join [$atoms get {segid resid radius name x y z}]] {
				#puts "$segid $resid $radius $name $x $y $z"
				foreach n {x y z} {
					set val [subst $$n]
					if {$val < [subst \$min$n]} {
						set $n [expr $val + $options($n)]
					} elseif {$val > [subst \$max$n]} {
						set $n [expr $val - $options($n)]
					}
				}
				lappend new_xyz [list $segid $resid $radius $name $x $y $z]
			}

			set overlap [::liquify::check_overlap $new_xyz $placed $cog $diam]
	
			# If atoms overlapped, move atoms back to try again next loop
			if {$overlap} {
				$atoms set {resname name x y z} $base_coords
			}

		}

		# If successfully placed molecules, give psfgen new coordinate
		# information XXX
		if {!$delete_mols} {
			foreach {segid resid name x y z} $pdata {
				coord $segid $resid $name "$x $y $z"
			}

			lappend placed $resid
		}
	}
}

#
# Check the atomic overlap between two molecules.  Args refers to molecule being
# scattered, atoms2 etc refer to already placed molecules.
#
proc ::liquify::check_overlap {pdata placed cog diam} {
	variable options

	# Only bother checking segments which have been "placed"
	foreach res $placed {
		set atoms2 [atomselect top "resid $res"]
		set cog2 [measure center $atoms2]
		set dr [vecdist $cog $cog2]
		
		# Use early rejection to prevent uncessesary checks
		if {$options(reject) && $dr >= $diam} {
			continue
		}

		# Molecular spheres overlap, check every atom pair
		set cdata [join [$atoms2 get {name radius x y z}]]
		foreach {segid resid radius name x y z} [join $pdata] {
			foreach {name2 radius2 x2 y2 z2} $cdata {
				set rcut [expr $radius + $radius2] ;# atomic radii may vary
				set dist [vecdist "$x $y $z" "$x2 $y2 $z2"]
				if {$dist < $rcut} {
					# Atomic overlap, reject move
					return 1
				}
			}
		}
	}
	return 0 ;# No atomic overlap, accept move
}

#
# Clear all input and loaded molecules
#
proc ::liquify::reset {} {
	variable options
	::liquify::clear_mols
	::liquify::set_defaults
}

#
#
#
proc ::liquify::write_xsc {} {
	variable options
	if ![file isdirectory $options(savedir)] {
		vmdcon -err "$options(savedir) is not a valid directory!"
		return 0
	}
	set fname "$options(savedir)/$options(savefile).xsc"
	if [catch {open $fname w} xsc_file] {
		vmdcon -err "Could not write to $fname"
		return 0
	}
	puts $xsc_file {#NAMD extended system configuration\n}
	puts $xsc_file {#$LABELS step a_x a_y a_z b_x b_y b_z c_x c_y c_z o_x o_y o_z\n}
	puts $xsc_file "100 $options(x) 0 0 0 $options(y) 0 0 0 $options(z) 0 0 0\n"
	close $xsc_file
	return 1
}
#
# Reset input fields to default TODO remove
#
proc ::liquify::set_defaults {} {
	variable options
	set options(niter) 150
	set options(pdb) "/home/leif/research/data/thiophene/thiophene.pdb"
	set options(psf) "/home/leif/research/data/thiophene/thiophene.psf"
	set options(top) "/home/leif/research/data/thiophene/thiophene.rtf"
	set options(savedir) $::env(PWD)
	set options(savefile) myliquid
	set options(cube) 0
	set options(reject) 1
	set options(density) 0.74 ;# hexagonal close packing for spheres
	foreach n {x y z} {
		set options($n) 30
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
	vmdcon -info "Input validation..."
}
