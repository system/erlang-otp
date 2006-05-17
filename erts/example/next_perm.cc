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
 *     $Id$
 */

/*
 * Purpose: A driver using libpq to connect to Postgres
 * from erlang, a sample for the driver documentation
 */

#include <erl_driver.h>

#include <algorithm>
#include <vector>

using namespace std;

#include <iostream>
#define L     cerr << __LINE__ << "\r\n";

/* Driver interface declarations */
static ErlDrvData start(ErlDrvPort port, char*);
static void output(ErlDrvData drv_data, char *buf, int len);
static void ready_async(ErlDrvData, ErlDrvThreadData);

static ErlDrvEntry next_perm_driver_entry = {
    NULL,			/* init */
    start,
    NULL, 			/* stop */
    output,			
    NULL,			/* ready_input */
    NULL,			/* ready_output */ 
    "next_perm",                /* the name of the driver */
    NULL,			/* finish */
    NULL,			/* handle */
    NULL,			/* control */
    NULL,			/* timeout */
    NULL,			/* outputv */
    ready_async,
    NULL,			/* flush */
    NULL,			/* call */
    NULL			/* event */
};

/* INITIALIZATION AFTER LOADING */

/* 
 * This is the init function called after this driver has been loaded.
 * It must *not* be declared static. Must return the address to 
 * the driver entry.
 */

#ifdef __cplusplus
extern "C" {		// shouldn't this be in the DRIVER_INIT macro?
#endif
DRIVER_INIT(next_perm)
{
    return &next_perm_driver_entry;
}
#ifdef __cplusplus
}
#endif

/* DRIVER INTERFACE */
static ErlDrvData start(ErlDrvPort port, char *)
{ 
    if (port == NULL)
	return ERL_DRV_ERROR_GENERAL;
    return (ErlDrvData)port;
}


struct our_async_data {
    bool prev;
    vector<int> data;
    our_async_data(ErlDrvPort p, int command, const char* buf, int len);
};

our_async_data::our_async_data(ErlDrvPort p, int command,
			       const char* buf, int len)
    : prev(command == 2),
      data((int*)buf, (int*)buf + len / sizeof(int))
{
}

static void do_perm(void* async_data);

static void output(ErlDrvData drv_data, char *buf, int len)
{
    if (*buf < 1 || *buf > 2) return;
    ErlDrvPort port = reinterpret_cast<ErlDrvPort>(drv_data);
    void* async_data = new our_async_data(port, *buf, buf+1, len);
    driver_async(port, NULL, do_perm, async_data, NULL);
}

static void do_perm(void* async_data)
{
    our_async_data* d = reinterpret_cast<our_async_data*>(async_data);
    if (d->prev)
	prev_permutation(d->data.begin(), d->data.end());
    else
	next_permutation(d->data.begin(), d->data.end());
}

static void ready_async(ErlDrvData drv_data, ErlDrvThreadData async_data)
{
    ErlDrvPort port = reinterpret_cast<ErlDrvPort>(drv_data);
    our_async_data* d = reinterpret_cast<our_async_data*>(async_data);
    int n = d->data.size(), result_n = n*2 + 5;
    ErlDrvTermData* result = new ErlDrvTermData[result_n], * rp = result;
    *rp++ = ERL_DRV_PORT;
    *rp++ = driver_mk_port(port);
    for (vector<int>::iterator i = d->data.begin();
	 i != d->data.end(); ++i) {
	*rp++ = ERL_DRV_INT;
	*rp++ = *i;
    }
    *rp++ = ERL_DRV_NIL;
    *rp++ = ERL_DRV_LIST;
    *rp++ = n+2;
    driver_output_term(port, result, result_n);    
    delete[] result;
    delete d;
}
