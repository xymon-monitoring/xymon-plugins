#!/bin/sh
# Copyright (C) 2026 spiderr
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <https://www.gnu.org/licenses/>.

COLUMN=rhn		# Name of the column
COLOR=green		# By default, everything is OK

RHNVERIFY=$(sudo /usr/bin/rhncfg-client verify|/usr/bin/grep -v "^[ ]\+\/" 2>&1)

outputLines=$(echo "$RHNVERIFY"|wc -l)

if [ $outputLines -eq 1 ]; then
	MSG="Configuration is clean."
else
	RHNDIFF=$(sudo /usr/bin/rhncfg-client diff -d  2>&1)
	MSG="Configuration dffers with server. $outputLines"
	COLOR=red
fi

# Tell Xymon about it
$XYMON $XYMONSERVERS "status $MACHINE.$COLUMN $COLOR `date`

Spacewalk status

${MSG}

${RHNVERIFY}

${RHNDIFF}
"

exit 0
