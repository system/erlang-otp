include $(ERL_TOP)/make/target.mk
include $(ERL_TOP)/make/$(TARGET)/otp.mk
include $(ERL_TOP)/erts/vsn.mk

VERSION_HEADER = erlang.nsh
MAKENSIS = makensis
MAKENSISFLAGS = /V2
CUSTOM_MODERN=custom_modern.exe

# This is not the way we usually do in our makefiles, 
# but making release is the ONLY thing we do with this one,
# Its not called during ordinary recursive make.
all: release

opt debug depend:
	@echo Nothing to do for "'"$@"'" on $(TARGET)

clean:
	rm -f $(VERSION_HEADER)

include $(ERL_TOP)/make/otp_release_targets.mk

TARGET_DIR = $(RELEASE_PATH)
WTESTROOT=$(shell (cygpath -d $(RELEASE_PATH) 2>/dev/null || cygpath -w $(RELEASE_PATH)))
WTARGET_DIR=$(shell (cygpath -d $(TARGET_DIR) 2>/dev/null || cygpath -d $(TARGET_DIR)))

REDIST_FILE=$(shell (sh ./find_redist.sh || echo ""))
REDIST_DLL_VERSION=$(shell (sh ./dll_version_helper.sh || echo ""))

release_spec:
	@NSIS_VER=`makensis /hdrinfo | head -1 | awk '{print $$2}'`; \
	case $$NSIS_VER in \
	v2.0b*) \
	  echo '!define MUI_VERSION "$(SYSTEM_VSN)"' > $(VERSION_HEADER);\
	  echo '!define ERTS_VERSION "$(VSN)"' >> $(VERSION_HEADER);\
	  echo '!define TESTROOT "$(WTESTROOT)"' >> $(VERSION_HEADER);\
	  echo '!define OUTFILEDIR "$(WTARGET_DIR)"' >> $(VERSION_HEADER);\
	  if [ -f $(RELEASE_PATH)/docs/doc/index.html ];\
	  then\
		echo '!define HAVE_DOCS 1' >> $(VERSION_HEADER); \
	  fi;\
	  $(MAKENSIS) erlang.nsi;;\
	v2.*) \
	  echo '!define OTP_VERSION "$(SYSTEM_VSN)"' > $(VERSION_HEADER);\
	  echo '!define ERTS_VERSION "$(VSN)"' >> $(VERSION_HEADER);\
	  echo '!define TESTROOT "$(WTESTROOT)"' >> $(VERSION_HEADER);\
	  echo '!define OUTFILEDIR "$(WTARGET_DIR)"' >> $(VERSION_HEADER);\
	  if [ -f $(CUSTOM_MODERN) ];\
	  then \
		echo '!define HAVE_CUSTOM_MODERN 1' >> $(VERSION_HEADER); \
	  fi;\
	  if [ '!' -z "$(REDIST_FILE)" -a '!' -z "$(REDIST_DLL_VERSION)" ];\
	  then \
		cp $(REDIST_FILE) $(RELEASE_PATH)/vcredist_x86.exe;\
		echo '!define HAVE_REDIST_FILE 1'  >> $(VERSION_HEADER); \
		echo '!define REDIST_DLL_VERSION "$(REDIST_DLL_VERSION)"' >> $(VERSION_HEADER);\
	  fi;\
	  if [ -f $(RELEASE_PATH)/docs/doc/index.html ];\
	  then \
		echo '!define HAVE_DOCS 1' >> $(VERSION_HEADER); \
	  fi;\
	  echo "Running $(MAKENSIS) $(MAKENSISFLAGS) erlang20.nsi";\
	  $(MAKENSIS) $(MAKENSISFLAGS) erlang20.nsi;;\
	*) \
	  echo 'Unsupported NSIS version';;\
	esac	

release_docs release_docs_spec docs:

