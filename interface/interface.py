#!/usr/bin/python
'''
Created on Aug 9, 2013

@author: netdar
'''


#import netifaces
import subprocess
import os
import re
import socket
import fcntl
import struct
import array
import sys
import time
import argparse

# read the file /proc/net/dev
netdev = open('/proc/net/dev','r')
ifaceshort=[]
# put the content to list
ifacelist = netdev.read().split("\n")
ifacelist.pop(0)
ifacelist.pop(0)
for line in ifacelist:
    #print line,
    ifaceshort.append(re.sub("^ *","",re.sub(":.*","",line)))
    

netdev.close()



def get_ip_address(ifname):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(
        s.fileno(),
        0x8915,  # SIOCGIFADDR
        struct.pack('256s', ifname[:15])
    )[20:24])

#BLACKLIST:   don't forget the : at the end, because eth10 would match eth1 otherwise
#BLACKLIST="em1:bond0:"
BLACKLIST=":"

parser = argparse.ArgumentParser(description='This is a demo.')
parser.add_argument("--debug", action="store_true", help="Activate debugging and print all output")
parser.add_argument("--speed", metavar='N', type=str, help='Desired port speed for all interfaces. If you have 10GbaseT nic, and 1GbaseT switch, this is required.')
parser.set_defaults(debug=False)
args = parser.parse_args()

DEBUGMODE=args.debug
GLOBALSPEED=0

if args.speed:
    GLOBALSPEED=args.speed

TIME=time.ctime()


STATUS=[]

FINISHED=1
COLOR="GREEN"

#different ways to get the if list
#netifaces.interfaces()
#/usr/sbin/ifconfig -s | /usr/bin/awk '!/Iface/{print $1}'


#for interface in reversed(netifaces.interfaces()):
for interface in reversed(ifaceshort):

#for interface in ifs:
    if interface+":" in BLACKLIST: continue
    SPEED=None
    del SPEED
    DUPLEX=None
    del DUPLEX
    ETHTOOLOUT=None
    del ETHTOOLOUT
    SLINKMODE=None
    del SLINKMODE
    HLINKMODE=None
    del HLINKMODE
    SLINKTYPE=None
    del SLINKTYPE
    #LINK=None
    #del LINK
    
    if DEBUGMODE==False:
        ETHTOOLOUT=subprocess.Popen(["sudo","ethtool",interface], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    else:
        ETHTOOLOUT=subprocess.Popen(["sudo","ethtool",interface], stdout=subprocess.PIPE)
    LINK=None    
    for line in ETHTOOLOUT.stdout:
        if "Duplex" in line:
            DUPLEX=line
            DUPLEX.split(":")
        elif "Speed" in line:
            if "Unknown!" in line:
                SPEED="UNKNOWN"
            else:
                SPEED=line
                SPEED.split(":")
        elif "Supported link modes:" in line:
                SLINKMODE=line
                FINISHED=0
                if "Not reported" not in line:
                    SLINKMODE.split(":")
        elif not ":" in line and FINISHED==0:
            SLINKMODE=SLINKMODE+line
        elif ":" in line and FINISHED==0:
            FINISHED=1
        if 'Link detected: no' in line:
            LINK=0
        elif 'Link detected: yes' in line:
            LINK=1

    STATUS.append("\n---------------------------------------------------------\n")
    
    
    #print "IP"+get_ip_address(interface)
    
    try: IP=get_ip_address(interface)
    except: IP="None"
    isbond=0
    IPADDROUT=subprocess.Popen(["ip", "addr" , "show", interface], stdout=subprocess.PIPE,stderr=subprocess.PIPE)

 
    for line in IPADDROUT.stdout:
        if "bond" in line:
            isbond=1
    
    
    if LINK==1 and IP == "None" and isbond==0:
            COLOR="YELLOW"
            STATUS.append("<H3>&yellow Interface: "+interface+ "</H3>        IP:  " + IP  + "\n")
            STATUS.append("        WARNING: attached Interface has no IP configured\n")
    #elif LINK==1 and IP != "None":
  
    elif IP != "None" and LINK==0:
            STATUS.append("<H3>&red Interface: "+interface+ "</H3>        IP:  " +IP  + "\n")
            STATUS.append("        ERROR: configured Interface "+interface+" has no Link\n")
            COLOR="RED"
    elif LINK==0 and IP == "None":
            STATUS.append("<H3>&clear Interface: "+interface+ "</H3>        IP:  " +IP  + "\n")
    else: STATUS.append("<H3>&green Interface: "+interface+ "</H3>        IP:  " +IP  + "\n")
        
    if 'LINK' in locals():
        if LINK==0:
            STATUS.append("&clear      Link detected: no\n")
        elif LINK==1:
            STATUS.append("&green      Link detected: yes\n")
    if 'SPEED' in locals():
        
        if SPEED != "UNKNOWN":
            SPEED=re.sub("[^0-9]","",SPEED)
            STATUS.append("        Configured speed:"+SPEED+"\n")
    if 'DUPLEX' in locals():
        STATUS.append(DUPLEX)
    if 'SLINKMODE' in locals():
        STATUS.append(SLINKMODE+"\n")
        if "Not reported" not in SLINKMODE:
            SLINKMODE=SLINKMODE.split(" ")
            SLINKMODE=SLINKMODE[len(SLINKMODE)-2]
            HLINKMODE="        Highest link mode: Not reported"
            HLINKMODE=re.sub("[^0-9]","",SLINKMODE)
            HLINKTYPE=re.sub("[0-9]*.*/(.*)",'\\1',SLINKMODE)
            STATUS.append("        Highest link mode:" + HLINKMODE + " " + HLINKTYPE+"\n")
            if SPEED != "UNKNOWN":
			    # There was no global --speed set, compare fastest possbible. 
                if GLOBALSPEED != 0 and GLOBALSPEED != SPEED:
                    STATUS.append("&red      Speed for this interface does not match desired speed: "+ SPEED + "!=" + GLOBALSPEED + "\n")
                    COLOR="RED"    
				# There was no global --speed set, compare fastest possbible. 
                elif GLOBALSPEED == 0 and HLINKMODE > SPEED:
                    STATUS.append("&yellow      Higher link mode possible for this interface"+"\n")
                    COLOR="YELLOW"    
    if "bond" in interface:
        bondfile=open("/proc/net/bonding/"+interface,"r")
    #bondfile=open("/tmp/bond0","r")
        for line in bondfile.readlines():       
            if 'MII Status: up' in line:
                STATUS.append("&green    "+line)
            elif 'MII Status: down' in line:
                COLOR="RED"
                STATUS.append("&red    "+line)
            else:
                STATUS.append(line)
                
    STATUS.append('\n---------------------------------------------------------\n')
    STATUS.append('\n\n')
    
PSTATUS=""
for line in STATUS:
    PSTATUS=PSTATUS+line
    
    if DEBUGMODE==True: print line,



if os.environ.has_key('XYMON'):
    _cmd_line=os.environ['XYMON']+" "+os.environ['XYMONSERVERS']+" \"status "+os.environ['MACHINE']+".interface"+" "+COLOR+" "+ TIME + PSTATUS +'"'
    if DEBUGMODE==True: print _cmd_line
    os.system(_cmd_line)
else:
    sys.stderr.write("ERROR: set XYMON, XYMONSERVERS and MACHINE environment variable to point to your installation\n")
    sys.exit(1)
    

