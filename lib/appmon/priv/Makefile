# ``The contents of this file are subject to the Erlang Public License,
# Version 1.1, (the "License"); you may not use this file except in
# compliance with the License. You should have received a copy of the
# Erlang Public License along with this software. If not, it can be
# retrieved via the world wide web at http://www.erlang.org/.
# 
# Software distributed under the License is distributed on an "AS IS"
# basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
# the License for the specific language governing rights and limitations
# under the License.
# 
# The Initial Developer of the Original Code is Ericsson Utvecklings AB.
# Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
# AB. All Rights Reserved.''
# 
#     $Id$
#
include $(ERL_TOP)/make/target.mk
include $(ERL_TOP)/make/$(TARGET)/otp.mk

include ../vsn.mk
VSN = $(APPMON_VSN)

# ----------------------------------------------------
# Release directory specification
# ----------------------------------------------------
RELSYSDIR = $(RELEASE_PATH)/lib/appmon-$(VSN)

#
# Macros
#
HELP_FILES = \
	appmon_help.txt

TOOLBAR_FILES = \
	appmon.tool \
	appmon.gif \
	start_info.html \
	main_frame.html \
	info_frames.html \
	blank.html

#
# Rules
#

debug opt:

docs:

clean:


# ----------------------------------------------------
# Release Target
# ---------------------------------------------------- 
include $(ERL_TOP)/make/otp_release_targets.mk

release_spec: opt
	$(INSTALL_DIR) $(RELSYSDIR)/priv
	$(INSTALL_DATA) $(HELP_FILES) $(TOOLBAR_FILES) $(RELSYSDIR)/priv

release_docs_spec:

FORCE:
