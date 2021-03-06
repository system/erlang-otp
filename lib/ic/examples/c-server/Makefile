#<copyright>
# <year>1998-2007</year>
# <holder>Ericsson AB, All Rights Reserved</holder>
#</copyright>
#<legalnotice>
# The contents of this file are subject to the Erlang Public License,
# Version 1.1, (the "License"); you may not use this file except in
# compliance with the License. You should have received a copy of the
# Erlang Public License along with this software. If not, it can be
# retrieved online at http://www.erlang.org/.
#
# Software distributed under the License is distributed on an "AS IS"
# basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
# the License for the specific language governing rights and limitations
# under the License.
#
# The Initial Developer of the Original Code is Ericsson AB.
#</legalnotice>
#
# Point this at your version of OTP
OTPROOT=/usr/local/otp/daily_build/otp_beam_sunos5_r8a.latest

# Type actual IC Version
ICVSN=4.1.1

# Type actual Erl Interface Vesrion
EIVSN=3.3.0

# IDL file(s)
IDLS=random.idl

# Own C-server files
CSRV=server callbacks

# Own C-client files
CCL=client

# Generated C-server files
GCSRVS=rmod_random__s 

# Generated C-server files
GCCLS=rmod_random

# Includes
IFLAGS=-I$(OTPROOT)/lib/ic-$(ICVSN)/include \
       -I$(OTPROOT)/lib/erl_interface-$(EIVSN)/include

LDFLAGS=-L$(OTPROOT)/lib/ic-$(ICVSN)/priv/lib \
	-L$(OTPROOT)/lib/erl_interface-$(EIVSN)/lib

LDLIBS=-lic -lerl_interface -lei -lnsl -lsocket


# Erlang compiler
ERLC=$(OTPROOT)/bin/erlc

# Erlang compiler flags. 
EFLAGS='+{preproc_flags,"-I $(OTPROOT)/usr/include"}' '+{scoped_op_calls,true}'


# C compiler
CC=gcc

# C compiler flags
CFLAGS=-ggdb -O2 -Wall $(IFLAGS)


all: server client erlclient


server: 
	$(ERLC) $(EFLAGS) '+{be,c_server}' $(IDLS)
	$(CC) $(IFLAGS) -c $(CSRV:=.c) $(GCSRVS:=.c)
	$(CC) $(CSRV:=.o) $(GCSRVS:=.o) -o $@ $(LDFLAGS) $(LDLIBS)

client: 
	$(ERLC) $(EFLAGS) '+{be,c_client}' $(IDLS)
	$(CC) $(IFLAGS) -c $(CCL:=.c) $(GCCLS:=.c)
	$(CC) $(CCL:=.o) $(GCCLS:=.o) -o $@ $(LDFLAGS) $(LDLIBS)

erlclient:
	$(ERLC) $(EFLAGS) '+{be,erl_genserv}' $(IDLS)
	$(ERLC) *.erl


clean: 
	/bin/rm -f $(GCCLS:=.o) $(GCCLS:=.c) $(GCSRVS:=.o) $(GCSRVS:=.c) $(CCL:=.o) $(CSRV:=.o) *.jam *.beam oe* *.h *.hrl *~ core server client


