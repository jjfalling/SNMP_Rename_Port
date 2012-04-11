#!/usr/bin/env perl
#used to change the name of a cisco port. Or anything really that supports ifDescr and ifAlias

use warnings; 
use SNMP_util;
use SNMP_Session;
use Getopt::Long;
use vars qw($opt_d $opt_h $opt_n $opt_p $opt_H $opt_w $opt_r $PROGNAME);
########################################################################################
#NOTES
#exit codes are 0 ok, 1 not ok. No output is given if you dont specify debuging or an error occurs. 
#This may need to change, who knows
#
#
########################################################################################
#Define varriables
my $PROGNAME = "snmp_rename_port.pl";
#IF-MIB::ifDescr.
my $ifdescr_oid=".1.3.6.1.2.1.2.2.1.2";
#IF-MIB::ifAlias.
my $ifalias_oid=".1.3.6.1.2.1.31.1.1.1.18";

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
   Enable debuging (Are you a human? Yes? Great! you will more then likely want to use this flag to see what is going on. Or not if you are utterly boring....)
   
";
exit (0);
}


unless ($opt_host) {print "Host name/address not specified\n"; exit (1)};
my $host = $1 if ($opt_host =~ /([-.A-Za-z0-9]+)/);
unless ($host) {print "Invalid host: $opt_host\n"; exit (1)};

unless ($opt_name) {print "Port alias not specified\n"; exit (1)};
my $new_name = $opt_name;

unless ($opt_port) {print "Port not specified\n"; exit (1)};
my $requested_port = $opt_port;

unless ($opt_wcom) {print "Write community not specified\n"; exit (1)};
my $snmp_community = $opt_wcom;

########################################################################################

if ($opt_d) {print "\n**DEBUGING IS ENABLED**\n";}
if ($opt_d) {print "**DEBUG: Attempting to find the requested port: \"$requested_port\" and rename to: \"$new_name\", please stand by.....\n";}

#walk the interface descriptions
if ($opt_d) {print "**DEBUG: Walking IF-MIB::ifDescr so we have a list of interfaces (this may take some time...)\n";}
@snmp_walk_out = &snmpwalk("$snmp_community\@$host","$ifdescr_oid");
my $snmp_walk_out_length = $#snmp_walk_out;
unless ($snmp_walk_out_length) {print "ERROR: SNMP walk error, zero length array returned\n"; exit 1;}

if ($opt_d) {print "**DEBUG: Walking IF-MIB::ifDescr succeded, looking to see if $requested_port exists \n";}

#grep for the requested port in the snmp walk array
@grepres = grep /$requested_port\b/i, @snmp_walk_out; 
my $grepres_length = $#grepres;
if ($grepres_length != 0) {print "ERROR: Interface $requested_port not found\n"; exit 1;}

if ($opt_d) {print "**DEBUG: Found $requested_port in the IF-MIB::ifDescr walk \n";}

#get the interger port number for the requested port
if ($opt_d) {print "**DEBUG: Looking for object id for $requested_port\n";}
$newval = $grepres[0];
$newval =~ /^(\d+):(.*)$/;
$port_number = $1;
chomp($port_number);

#if interface was not found, exit
unless ($port_number) {print "\n\nERROR: Interface not found! Check your input and try again \n\n"; exit 1;}
if ($opt_d) {print "**DEBUG: Found object id for $requested_port\n";}

#get the existing port alias, exit if fails
if ($opt_d) {print "**DEBUG: Getting old alias for $requested_port\n";}
my $old_port_alias = &snmpget("$snmp_community\@$host","$ifalias_oid.$port_number");


#set the new port alias, exit if fails
if ($opt_d) {print "**DEBUG: Success, setting new alias for $requested_port\n";}
my $snmp_set_status = &snmpset("$snmp_community\@$host","$ifalias_oid.$port_number",'string',"$new_name");
unless ($snmp_set_status) {print "\n\nERROR: could not set snmp value \n\n"; exit 1;}

#get the new port alias, exit if fails
if ($opt_d) {print "**DEBUG: Success, confirming new alias for $requested_port\n";}
my $new_port_alias = &snmpget("$snmp_community\@$host","$ifalias_oid.$port_number");
unless ($new_port_alias) {print "\n\nERROR: could not get snmp value \n\n"; exit 1;}

#if user requested debugging, give summary, otherwise exit with status of 0
if ($opt_d) {print "\n**DEBUG: Old alias of $requested_port: $old_port_alias\n";}
if ($opt_d) {print "**DEBUG: New alias of $requested_port: $new_port_alias\n\n";}
if ($opt_d) {print "**DEBUG: DONE. Please confirm with the above output, but the alias should have been changed.\n\n";}


exit 0;