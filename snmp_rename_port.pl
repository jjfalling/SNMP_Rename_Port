#!/usr/bin/env perl

#############################################################################
#snmp_rename_port.pl	
#Used to change the name of a cisco port. Or anything really that supports ifDescr and ifAlias
#
#
# ***************************************************************************
# *   Copyright (C) 2012 by Jeremy Falling except where noted.              *
# *                                                                         *
# *   This program is free software; you can redistribute it and/or modify  *
# *   it under the terms of the GNU General Public License as published by  *
# *   the Free Software Foundation; either version 2 of the License, or     *
# *   (at your option) any later version.                                   *
# *                                                                         *
# *   This program is distributed in the hope that it will be useful,       *
# *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
# *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
# *   GNU General Public License for more details.                          *
# *                                                                         *
# *   You should have received a copy of the GNU General Public License     *
# *   along with this program; if not, write to the                         *
# *   Free Software Foundation, Inc.,                                       *
# *   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
# ***************************************************************************

use strict;
use warnings; 
use Net::SNMP;
use Getopt::Long;
use Term::ANSIColor;
use vars qw($opt_d $opt_h $opt_n $opt_p $opt_H $opt_w $PROGNAME);
########################################################################################
#NOTES:
#Exit codes are 0 ok, 1 user error, 2 script error. Very little output is given if you don't 
# specify debugging or an error occurs. This may need to change, who knows
#
#Also, I used red text for any error that requires the user's attention
#
########################################################################################
#Define variables
my $PROGNAME = "snmp_rename_port.pl";

#Define oids we are going to use:
my %if_oids = (
	'ifdescr'      => ".1.3.6.1.2.1.2.2.1.2",
	'ifalias'      => ".1.3.6.1.2.1.31.1.1.1.18",
);

my $null_var; #Anything we don't care about but need a variable for some sort of task, use this
my $opt_help;
my $opt_d;
my $opt_name;
my $opt_port;
my $opt_host;
my $opt_wcom;
my $port_number;
my $value_inter;
my $human_error;
my $exit_request;
my $human_status;

########################################################################################
Getopt::Long::Configure('bundling');
GetOptions
	("h"   => \$opt_help, "help" => \$opt_help,
	 "d"   => \$opt_d, "debug" => \$opt_d,
	 "n=s" => \$opt_name, "name=s" => \$opt_name,
	 "p=s" => \$opt_port, "port=s" => \$opt_port,
	 "H=s" => \$opt_host, "hostname=s" => \$opt_host,
	 "w=s" => \$opt_wcom, "wcommunity=s" => \$opt_wcom);
	

#validate input

if ($opt_help) {

print "

This script can be used to rename a cisco port.

Usage: $PROGNAME -H <host> -n alias -p port -w community [-d] 

-h, --help
   Print this message
-H, --hostname=HOST
   Name or IP address of host to check
-n, --name = \"alias\"
   Alias (name) of the port
-p, --port = port
   Port to change (ex: FastEthernet1/0/2)
-w, --wcommunity=community
   SNMPv1 write community
-d, --debug
   Enable debugging (Are you a human? Yes? Great! you will more then likely want to use this flag to see what is going on. Or not if you are utterly boring....)
   
";
exit (0);
}

unless ($opt_host) {print colored ['red'],"Host name/address not specified\n"; print color("reset"); exit (1)};
my $host = $1 if ($opt_host =~ /([-.A-Za-z0-9]+)/);
unless ($host) {print colored ['red'],"Invalid host: $opt_host\n"; print color("reset"); exit (1)};

unless ($opt_name) {print colored ['red'], "Port alias not specified\n"; print color("reset"); exit (1)};
my $new_name = $opt_name;

unless ($opt_port) {print colored ['red'],"Port not specified\n"; print color("reset"); exit (1)};
my $requested_port = $opt_port;

unless ($opt_wcom) {print colored ['red'],"Write community not specified\n"; print color("reset"); exit (1)};
my $snmp_community = $opt_wcom;

########################################################################################
#start new snmp session
my($snmp,$snmp_error) = Net::SNMP->session(-hostname => $host,
                                           -community => $snmp_community);
                                           
debugOutput("\n**DEBUGGING IS ENABLED**\n");
debugOutput("**DEBUG: Attempting to find the requested port: \"$requested_port\" and rename to: \"$new_name\", please stand by.....");


#walk the interface descriptions
debugOutput("**DEBUG: Walking IF-MIB::ifDescr so we have a list of interfaces (this may take some time...)");
my $snmp_walk_out = $snmp->get_entries( -columns =>  [$if_oids{ifdescr}]);
checkSNMPStatus("Couldn't poll device: ",2);

debugOutput("**DEBUG: Walking IF-MIB::ifDescr succeeded, looking to see if $requested_port exists ");

#See if the requested interface exists
LOOK_FOR_INTERFACE: while ( ($port_number,$value_inter) = each %$snmp_walk_out ) {

	#see if the current value from the hash matches
    if ($value_inter eq $requested_port) {
    	
    	debugOutput("**DEBUG: Found $requested_port in the IF-MIB::ifDescr walk ");
    	debugOutput("**DEBUG: Looking for object id for $requested_port");
    	    	
    	#lets get the port number, basically take the index and remove the oid. Also, chomping seems required for some other snmp things to work right
    	$port_number =~ s/$if_oids{ifdescr}\.//;
    	chomp($port_number);
    	
    	last LOOK_FOR_INTERFACE;
    
    }    
    
}

unless ($port_number) {print "ERROR: Interface $requested_port not found, check your spelling, syntax or reality and try again. \n"; exit 2;}

debugOutput("**DEBUG: Found object id for $requested_port : $port_number");

#we need to re-assign the ifalias value in the if_oid hash since we only now know the interface id. 
my $ifalias_oid = $if_oids{ifalias};
$if_oids{ifalias} = "$ifalias_oid.$port_number";

#get the existing port alias, exit if fails
debugOutput("**DEBUG: Getting old alias for $requested_port");
my $old_port_alias_out = $snmp->get_request( -varbindlist => [ $if_oids{ifalias}]);

#get the existing alias out of the hash and check if its empty
($null_var,my $old_port_alias) = each %$old_port_alias_out;
if ($opt_d) {checkSNMPStatus("ERROR: could not get old interface alias, trying to go on with out it...",)};

##set the new port alias, exit if fails
debugOutput("**DEBUG: setting new alias for $requested_port");
my $snmp_set_status = $snmp->set_request( -varbindlist =>  [$if_oids{ifalias}, OCTET_STRING, $new_name]);
checkSNMPStatus("ERROR: could not set snmp value",2);

#get the new port alias, exit if fails
debugOutput("**DEBUG: confirming new alias for $requested_port");
my $new_port_hash = $snmp->get_request( -varbindlist => [ $if_oids{ifalias}]);

#get the existing alias out of the hash and check if its empty
($null_var,my $new_port_alias) = each %$new_port_hash;
checkSNMPStatus("ERROR: could not confirm snmp value",2);

##If user requested debugging, give summary
debugOutput("\n**DEBUG: Old alias of $requested_port: $old_port_alias");
debugOutput("**DEBUG: New alias of $requested_port: $new_port_alias\n\n");
debugOutput("**DEBUG: DONE. Please confirm with the above output, but the alias should have been changed.\n");

#Otherwise, if no debug was requested, say done and exit with status of 0
unless ($opt_d) {print "Done. Old alias: $old_port_alias | New alias: $new_port_alias ";}

########################################################################################
#Functions!

#This function will do the error checking and reporting when related to SNMP
sub checkSNMPStatus {
	$human_error = $_[0];
	$exit_request = $_[1];
	$snmp_error = $snmp->error();
    
    #check if there was an error, if so, print the requested message and the snmp error. I used the color red to get the user's attention.
    if ($snmp_error) {
		print colored ['red'], "$human_error $snmp_error \n";

		#check to see if the error should cause the script to exit, if so, exit with the requested code
		if ($exit_request) {
			print color("reset");
			exit $exit_request;
		}
	}
}

#This function will be used to give the user output, if they so desire
sub debugOutput {
	$human_status = $_[0];
    if ($opt_d) {
		print "$human_status \n";
		
	}
}


#Well shucks, we made it all the way down here with no errors. Guess we should exit without an error ;)
print color("reset");
exit 0;