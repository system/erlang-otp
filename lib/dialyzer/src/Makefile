#=============================================================================
#
#    File:  lib/dialyzer/src/Makefile
# Authors:  Kostis Sagonas and Tobias Lindahl
#
#=============================================================================

include $(ERL_TOP)/make/target.mk
include $(ERL_TOP)/make/$(TARGET)/otp.mk

# ----------------------------------------------------
# Application version
# ----------------------------------------------------
include ../vsn.mk
VSN=$(DIALYZER_VSN)

# ----------------------------------------------------
# Release directory specification
# ----------------------------------------------------
RELSYSDIR = $(RELEASE_PATH)/lib/dialyzer-$(VSN)

# ----------------------------------------------------
# Orientation information
# ----------------------------------------------------
DIALYZER_DIR = $(ERL_TOP)/lib/dialyzer

# ----------------------------------------------------
# Target Specs
# ----------------------------------------------------
MODULES =  \
	dialyzer \
	dialyzer_analysis_callgraph \
	dialyzer_callgraph \
	dialyzer_cl \
	dialyzer_cl_parse \
	dialyzer_codeserver \
	dialyzer_contracts \
	dialyzer_dataflow \
	dialyzer_dep \
	dialyzer_gui \
	dialyzer_options \
	dialyzer_plt \
	dialyzer_succ_typings \
	dialyzer_typesig \
	dialyzer_utils

HRL_FILES= dialyzer.hrl dialyzer_callgraph.hrl
ERL_FILES= $(MODULES:%=%.erl)
INSTALL_FILES= $(MODULES:%=$(EBIN)/%.$(EMULATOR)) $(APP_TARGET) $(APPUP_TARGET)
TARGET_FILES= $(INSTALL_FILES)

APP_FILE= dialyzer.app
APP_SRC= $(APP_FILE).src
APP_TARGET= $(EBIN)/$(APP_FILE)

APPUP_FILE= dialyzer.appup
APPUP_SRC= $(APPUP_FILE).src
APPUP_TARGET= $(EBIN)/$(APPUP_FILE)

# ----------------------------------------------------
# FLAGS
# ----------------------------------------------------
ERL_COMPILE_FLAGS += +warn_unused_import +warn_obsolete_guard +warn_untyped_record +warn_missing_spec

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

debug opt: $(TARGET_FILES)

docs:

clean:
	rm -f $(TARGET_FILES)
	rm -f core

# ----------------------------------------------------
# Special Build Targets
# ----------------------------------------------------

$(EBIN)/dialyzer_cl_parse.$(EMULATOR): dialyzer_cl_parse.erl ../vsn.mk
	erlc -W  $(ERL_COMPILE_FLAGS) -DVSN="\"v$(VSN)\"" -o$(EBIN) dialyzer_cl_parse.erl

$(EBIN)/dialyzer_plt.$(EMULATOR): dialyzer_plt.erl ../vsn.mk
	erlc -W  $(ERL_COMPILE_FLAGS) -DVSN="\"v$(VSN)\"" -o$(EBIN) dialyzer_plt.erl

$(EBIN)/dialyzer_gui.$(EMULATOR): dialyzer_gui.erl ../vsn.mk
	erlc -W  $(ERL_COMPILE_FLAGS) -DVSN="\"v$(VSN)\"" -o$(EBIN) dialyzer_gui.erl

$(APP_TARGET): $(APP_SRC) ../vsn.mk
	sed -e 's;%VSN%;$(VSN);' $< > $@

$(APPUP_TARGET): $(APPUP_SRC) ../vsn.mk
	sed -e 's;%VSN%;$(VSN);' $< > $@

# ---------------------------------------------------------------------
# dependencies -- I wish they were somehow automatically generated
# ---------------------------------------------------------------------

$(EBIN)/dialyzer.beam: dialyzer.hrl
$(EBIN)/dialyzer_analysis_callgraph.beam: dialyzer.hrl
$(EBIN)/dialyzer_callgraph.beam: dialyzer_callgraph.hrl
$(EBIN)/dialyzer_cl.beam: dialyzer.hrl
$(EBIN)/dialyzer_cl_parse.beam: dialyzer.hrl
$(EBIN)/dialyzer_codeserver.beam: dialyzer.hrl
$(EBIN)/dialyzer_contracts.beam: dialyzer.hrl dialyzer_callgraph.hrl
$(EBIN)/dialyzer_dataflow.beam: dialyzer.hrl dialyzer_callgraph.hrl
$(EBIN)/dialyzer_dep.beam: dialyzer.hrl
$(EBIN)/dialyzer_gui.beam: dialyzer.hrl
$(EBIN)/dialyzer_options.beam: dialyzer.hrl
$(EBIN)/dialyzer_plt.beam: dialyzer.hrl
$(EBIN)/dialyzer_succ_typings.beam: dialyzer.hrl dialyzer_callgraph.hrl
$(EBIN)/dialyzer_typesig.beam: dialyzer.hrl dialyzer_bif_constraints.inc
$(EBIN)/dialyzer_utils.beam: dialyzer.hrl

# ----------------------------------------------------
# Release Target
# ---------------------------------------------------- 
include $(ERL_TOP)/make/otp_release_targets.mk

release_spec: opt
	$(INSTALL_DIR) $(RELSYSDIR)/src
	$(INSTALL_DATA) $(ERL_FILES) $(HRL_FILES) $(EXTRA_FILES) \
		$(RELSYSDIR)/src
	$(INSTALL_DIR) $(RELSYSDIR)/ebin
	$(INSTALL_DATA) $(INSTALL_FILES) $(RELSYSDIR)/ebin

release_docs_spec:
