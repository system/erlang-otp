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

/***************************************************************************
 *
 *  Compatibility with the old erl_interface library that had some
 *  undocumented functions.
 *
 ***************************************************************************/

#include "eidef.h"

#include "erl_interface.h"
#include "ei_resolve.h"
#include "ei_connect_int.h"
#include "ei_epmd.h"

struct hostent *erl_gethostbyname(const char *name)
{
    return ei_gethostbyname(name);
}


void erl_init_resolve(void)
{
    return ei_init_resolve();
}


struct hostent *erl_gethostbyaddr(const char *addr, int len, int type)
{
    return ei_gethostbyaddr(addr, len, type);
}


struct hostent *erl_gethostbyname_r(const char *name, 
				    struct hostent *hostp, 
				    char *buffer, 
				    int buflen, 
				    int *h_errnop)
{
    return ei_gethostbyname_r(name,hostp,buffer,buflen,h_errnop);
}


struct hostent *erl_gethostbyaddr_r(const char *addr,
				    int length, 
				    int type, 
				    struct hostent *hostp,
				    char *buffer,  
				    int buflen, 
				    int *h_errnop)
{
    return ei_gethostbyaddr_r(addr,length,type,hostp,buffer,buflen,h_errnop);
}


int erl_distversion(int fd)
{
    return ei_distversion(fd);
}

int erl_epmd_connect(struct in_addr *inaddr)
{
    return ei_epmd_connect_tmo(inaddr,0);
}

int erl_epmd_port(struct in_addr *inaddr, const char *alive, int *dist)
{
    return ei_epmd_port(inaddr, alive, dist);
}



/*  FIXME !!!!!
erl_epmd_port ei_epmd_port
erl_mutex_lock ei_mutex_lock
erl_malloc erl_free ????
erl_publish erl_unpublish
< extern int erl_epmd_connect(struct in_addr *inaddr);
< extern int erl_epmd_publish(int port, const char *alive);
< extern int erl_epmd_port(struct in_addr *inaddr, const char *alive, int *dist);

< int erl_unpublish(const char *alive)
---
> int ei_unpublish_alive(const char *alive)

erl_self
erl_getfdcookie
*/
