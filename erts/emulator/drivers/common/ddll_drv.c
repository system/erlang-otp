/* ``The contents of this file are subject to the Erlang Public License,
 * Version 1.1, (the "License"); you may not use this file except in
 * compliance with the License. You should have received a copy of the
 * Erlang Public License along with this software. If not, it can be
 * retrieved via the world wide web at http://www.erlang.org/.
 * 
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
 * the License for the specific language governing rights and limitations
 * under the License.
 * 
 * The Initial Developer of the Original Code is Ericsson Utvecklings AB.
 * Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
 * AB. All Rights Reserved.''
 * 
 *     $Id: ddll_drv.c,v 1.4 2000/06/08 21:56:49 tony Exp $
 */
/* 
 * Dynamic driver loader and linker
 */

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include "sys.h"
#include "erl_vm.h"
#include "driver.h"
#include "global.h"
#include "erl_ddll.h"

#define LOAD_DRIVER   'l'
#define UNLOAD_DRIVER 'u'
#define GET_DRIVERS   'g'

/***********************************************************************
 * R e p l i e s
 *
 * The following replies are sent from this driver.
 *
 * Reply		Translated to on Erlang side
 * -----		----------------------------
 * [$o]			ok
 * [$o|List]		{ok, List}
 * [$e|Atom]		{error, Atom}
 * [$E|[Atom, 0, Message]]	{error, {Atom, Message}}
 * [$i|String]		"..."    (This is an item in a list.)
 *
 * List of strings are sent as multiple messages:
 *
 *	[$i|String]
 *	.
 *	.
 *	.
 *	[$i|String]
 *	[$o]
 *
 * This will be represented as {ok, [String1, ..., StringN]} in Erlang.
 ************************************************************************/
#define LOAD_FAILED   2

typedef FUNCTION(DriverEntry*, (*DRV_INITFN), (void*));

static long dyn_start();
static int dyn_stop();
static int handle_command();

struct driver_entry ddll_driver_entry = {
    NULL,			/* init */
    dyn_start,			/* start */
    dyn_stop,			/* stop */
    handle_command,		/* output */
    NULL,			/* ready_input */
    NULL,			/* ready_output */
    "ddll",			/* driver_name */
    NULL,			/* finish */
    NULL			/* handle */
};

static long erlang_port = -1;

static long reply(long port, int success, char *str)
{
    char tmp[200];
    *tmp = success;
    strncpy(tmp + 1, str, 198);
    tmp[199] = 0; /* in case str was more than 198 bytes */
    driver_output(port, tmp, strlen(tmp));
    return 0;
}

static long
error_reply(char* atom, char* string)
{
    char* reply_str;
    int alen;			/* Length of atom. */
    int slen;			/* Length of string. */
    int rlen;			/* Length of reply. */

    alen = strlen(atom);
    slen = strlen(string);
    rlen = 1+alen+1+slen;
    reply_str = sys_alloc(rlen+1);
    reply_str[0] = 'E';
    strcpy(reply_str+1, atom);
    strcpy(reply_str+alen+2, string);
    driver_output(erlang_port, reply_str, rlen);
    sys_free(reply_str);
    return 0;
}

static long dyn_start(long port, char *buf)
{
    if (erlang_port != -1) {
	return -1;			/* Already started! */
    }
    return erlang_port = port;
}

static int dyn_stop()
{
    erlang_port = -1;
    return 0;
}


static int unload(void* arg1, void* arg2)
{
    DE_List* de = (DE_List*) arg1;
    int ix = (int) arg2;
    DE_Handle* dh;
    int j;

    DEBUGF(("ddll_drv: unload: (%d) %s\r\n", ix, de->drv->driver_name));
    /*
     * Kill all ports that depend on this driver.
     */
    for (j = 0; j < erl_max_ports; j++) {
	if (erts_port[j].status != FREE &&
	    erts_port[j].drv_ptr == de->drv) {
	    driver_failure(j, -1);
	}
    }

    /* 
     * Let the driver clean up its mess before unloading it.
     * We ignore errors from the finish funtion and
     * ddll_close().
     */

    dh = de->de_hndl;
    
    if (de->drv->finish) {
	(*(de->drv->finish))();
    }
    DEBUGF(("ddll_drv: unload: lib=%08x\r\n", dh->handle));

    ddll_close(dh->handle);
    sys_free((void*)dh);
    remove_driver_entry(de->drv);

    return reply(ix, 'o', "");
}

static int load(char* full_name, char* driver_name)
{
    DriverEntry *dp;
    DE_Handle* dh;
    void *lib;
    uint32 *initfn;

    DEBUGF(("ddll_drv: load: %s, %s\r\n", full_name, driver_name));

    if ((lib = ddll_open(full_name)) == NULL) {
	return error_reply("open_error", ddll_error());
    }
    DEBUGF(("ddll_drv: load: lib=%08x\r\n", lib));
    /* Some systems still require an underscore at the beginning of the
     * symbol name. If we can't find the name without the underscore, try
     * again with it.
     */
	
    if ((initfn = ddll_sym(lib, "driver_init")) == NULL)
	if ((initfn = ddll_sym(lib, "_driver_init")) == NULL) {
	    ddll_close(lib);
	    return reply(erlang_port, 'e', "no_driver_init");
	}

    /* 
     * Here we go, lets hope the driver write knew what he was doing...
     */
    dh = sys_alloc(sizeof(DE_Handle));
    dh->handle = lib;
    dh->ref_count = 1;
    dh->status = ERL_DE_OK;
    dh->cb = NULL;
    dh->ca[0] = NULL;

    if ((dp = (((DriverEntry *(*)())initfn)(dh))) == NULL) {
	ddll_close(lib);
	sys_free(dh);
	return reply(erlang_port, 'e', "driver_init_failed");
    }
    
    if (strcmp(driver_name, dp->driver_name) != 0) {
	ddll_close(lib);
	sys_free(dh);
	return reply(erlang_port, 'e', "bad_driver_name");
    }

    dp->handle = dh;

    /* insert driver */
    add_driver_entry(dp);

    return reply(erlang_port, 'o', "");
}


/* static reload callback */
static int reload(void* arg1, void* arg2, void* arg3, void* arg4)
{
    char* full_name = (char*) arg1;
    char* driver_name = (char*) arg2;
    int code;

    DEBUGF(("ddll_drv: reload: %s, %s\r\n", full_name, driver_name));

    unload(arg3, arg4);
    code = load(full_name, driver_name);
    driver_free(full_name);
    driver_free(driver_name);
    return code;
}


static int handle_command(long inport, char *buf, int count)
{
    char *driver_name;
    
    /*
     * Do some sanity checking on the commands passed in buf. Make sure the
     * last string is null terminated, and that buf isn't empty.
     */
    
    if (count == 0 || (count > 1 && buf[count-1] != 0)) {
	return driver_failure(erlang_port, 100);
    }
  
    switch (*buf++) {
    case LOAD_DRIVER:
	{
	    char* full_name;
	    DE_List *de;
	    DE_Handle* dh;
	    int j;

	    if (count < 5) {
		return driver_failure(erlang_port, 110);
	    }

	    driver_name = buf;
	    j = strlen(driver_name);
	    if (j == 0 || j+3 >= count) {
		return driver_failure(erlang_port, 111);
	    }

	    full_name = buf+j+1;

	    for (de = driver_list; de != NULL; de = de->next) {
		if (strcmp(de->drv->driver_name, driver_name) == 0) {
		    dh = de->de_hndl;
		    if (dh != NULL) {
			if (dh->status == ERL_DE_UNLOAD) {
			    dh->status = ERL_DE_RELOAD;
			    dh->cb = reload;
			    dh->ca[2] = dh->ca[0];
			    dh->ca[3] = dh->ca[1];
			    dh->ca[0] = driver_alloc(strlen(full_name)+1);
			    dh->ca[1] = driver_alloc(strlen(driver_name)+1);
			    strcpy((char*)dh->ca[0], full_name);
			    strcpy((char*)dh->ca[1], driver_name);
			    return 0;
			}
			else if (dh->status == ERL_DE_RELOAD) {
			    driver_free(dh->ca[0]);
			    driver_free(dh->ca[1]);
			    dh->ca[0] = driver_alloc(strlen(full_name)+1);
			    dh->ca[1] = driver_alloc(strlen(driver_name)+1);
			    strcpy((char*)dh->ca[0], full_name);
			    strcpy((char*)dh->ca[1], driver_name);
			    return 0;
			}
		    }
		    return reply(erlang_port, 'e', "already_loaded");
		}
	    }
	    return load(full_name, driver_name);
	}

    case UNLOAD_DRIVER:
	{
	    DE_List *de;
	    DE_Handle* dh;

	    if (count < 3) {
		return driver_failure(erlang_port, 200);
	    }
	    driver_name = buf;

	    DEBUGF(("ddll_drv: UNLOAD: %s\r\n", driver_name));

	    for (de = driver_list; de != NULL; de = de->next) {
		if (strcmp(de->drv->driver_name, driver_name) == 0) {
		    dh = de->de_hndl;
		    if (dh == NULL)
			return reply(erlang_port, 'e', "linked_in_driver");
		    dh->ref_count--;
		    if (dh->ref_count > 0) {
			DEBUGF(("ddll_drv: UNLOAD: ref_count =%d\r\n",
				dh->ref_count));
			if (dh->status == ERL_DE_OK) {
			    dh->status = ERL_DE_UNLOAD;
			    dh->cb = unload;
			    dh->ca[0] = (void*) de;
			    dh->ca[1] = (void*) erlang_port;
			    return 0;  /* delayed op */
			}
			else if (dh->status == ERL_DE_RELOAD) {
			    dh->status = ERL_DE_UNLOAD;
			    dh->cb = unload;
			    driver_free(dh->ca[0]);
			    driver_free(dh->ca[1]);
			    dh->ca[0] = (void*) de;
			    dh->ca[1] = (void*) erlang_port;
			    return 0;
			}
			else if (dh->status == ERL_DE_UNLOAD)
			    return 0;
		    }
		    else {
			return unload((void*) de, (void*) erlang_port);
		    }
		}
	    }
	    return reply(erlang_port, 'e', "not_loaded");
	}
    
    case GET_DRIVERS:
	{
	    DE_List *pos;

	    for (pos = driver_list; pos != NULL; pos = pos->next) {
		reply(erlang_port, 'i', pos->drv->driver_name);
	    }
	    return reply(erlang_port, 'o', "");
	}
	
    default:
	driver_failure(erlang_port, 999);
    }
    return 0;
}