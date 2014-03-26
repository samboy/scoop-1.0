#!/bin/sh
# get-scoop.sh
# By Dylan Griffiths <Inoshiro@kuro5hin.org>
# Gets you the latest snapshot of Scoop with one command.
# Warning: You need CVS installed and in the current path.
cd ..
cvs -z3 -d:pserver:anonymous@cvs.scoop.sourceforge.net:/cvsroot/scoop update
