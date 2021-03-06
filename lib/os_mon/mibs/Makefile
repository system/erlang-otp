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

# ----------------------------------------------------
# Application version
# ----------------------------------------------------
include ../vsn.mk
VSN=$(OS_MON_VSN)

# ----------------------------------------------------
# Release directory specification
# ----------------------------------------------------
RELSYSDIR = $(RELEASE_PATH)/lib/os_mon-$(VSN)

# ----------------------------------------------------
# Target Specs
# ----------------------------------------------------

MIB_FILES= OTP-OS-MON-MIB.mib 
FUNCS_FILES = OTP-OS-MON-MIB.funcs

BIN_TARGETS= $(MIB_FILES:%.mib=$(SNMP_BIN_TARGET_DIR)/%.bin)
HRL_TARGETS= $(MIB_FILES:%.mib=$(SNMP_HRL_TARGET_DIR)/%.hrl)
V1_MIB_FILES= $(MIB_FILES:%.mib=v1/%.mib.v1)

TARGET_FILES= $(SNMP_BIN_TARGET_DIR)/OTP-REG.bin \
  $(SNMP_BIN_TARGET_DIR)/OTP-TC.bin \
  $(SNMP_BIN_TARGET_DIR)/OTP-MIB.bin \
  $(BIN_TARGETS) $(HRL_TARGETS) $(V1_MIB_FILES)

# ----------------------------------------------------
# FLAGS
# ----------------------------------------------------
SNMP_FLAGS =  -I $(SNMP_BIN_TARGET_DIR)

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

debug opt: $(TARGET_FILES)

clean:
	rm -f $(TARGET_FILES)
	rm -f core

docs:

OTP_MIBDIR = $(shell if test -d ../../otp_mibs; then echo otp_mibs; \
		      else echo sasl; fi)

$(SNMP_BIN_TARGET_DIR)/OTP-REG.bin:     $(ERL_TOP)/lib/$(OTP_MIBDIR)/mibs/OTP-REG.mib
	$(ERLC) -pa $(SNMP_TOOLKIT)/ebin -I $(SNMP_TOOLKIT)/priv/mibs $(SNMP_FLAGS) -o $(SNMP_BIN_TARGET_DIR) $<

$(SNMP_BIN_TARGET_DIR)/OTP-TC.bin:     $(ERL_TOP)/lib/$(OTP_MIBDIR)/mibs/OTP-TC.mib
	$(ERLC) -pa $(SNMP_TOOLKIT)/ebin -I $(SNMP_TOOLKIT)/priv/mibs $(SNMP_FLAGS) -o $(SNMP_BIN_TARGET_DIR) $<

$(SNMP_BIN_TARGET_DIR)/OTP-MIB.bin:     $(ERL_TOP)/lib/$(OTP_MIBDIR)/mibs/OTP-MIB.mib
	$(ERLC) -pa $(SNMP_TOOLKIT)/ebin -I $(SNMP_TOOLKIT)/priv/mibs $(SNMP_FLAGS) -o $(SNMP_BIN_TARGET_DIR) $<

v1/%.mib.v1: %.mib
	$(ERL_TOP)/lib/snmp/bin/snmp-v2tov1 -o $@ $<


# ----------------------------------------------------
# Release Target
# ---------------------------------------------------- 
include $(ERL_TOP)/make/otp_release_targets.mk

release_spec: opt
	$(INSTALL_DIR) $(RELSYSDIR)/mibs
	$(INSTALL_DIR) $(RELSYSDIR)/mibs/v1
	$(INSTALL_DATA) $(MIB_FILES) $(FUNCS_FILES) $(RELSYSDIR)/mibs
	$(INSTALL_DATA) $(V1_MIB_FILES) $(RELSYSDIR)/mibs/v1
	$(INSTALL_DIR) $(RELSYSDIR)/include
	$(INSTALL_DATA) $(HRL_TARGETS) $(RELSYSDIR)/include
	$(INSTALL_DIR) $(RELSYSDIR)/priv/mibs
	$(INSTALL_DATA) $(BIN_TARGETS) $(RELSYSDIR)/priv/mibs

release_docs_spec:
