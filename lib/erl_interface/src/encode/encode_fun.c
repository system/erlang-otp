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
#include <string.h>
#include "eidef.h"
#include "eiext.h"
#include "putget.h"

int ei_encode_fun(char *buf, int *index, const erlang_fun *p)
{
    int ix = *index;

    if (p->arity == -1) {
	/* ERL_FUN_EXT */
	if (buf != NULL) {
	    char* s = buf + ix;
	    put8(s, ERL_FUN_EXT);
	    put32be(s, p->n_free_vars);
	}
	ix += sizeof(char) + 4;
	if (ei_encode_pid(buf, &ix, &p->pid) < 0)
	    return -1;
	if (ei_encode_atom(buf, &ix, p->module) < 0)
	    return -1;
	if (ei_encode_long(buf, &ix, p->index) < 0)
	    return -1;
	if (ei_encode_long(buf, &ix, p->uniq) < 0)
	    return -1;
	if (buf != NULL)
	    memcpy(buf + ix, p->free_vars, p->free_var_len);
	ix += p->free_var_len;
    } else {
	char *size_p;
	/* ERL_NEW_FUN_EXT */
	if (buf != NULL) {
	    char* s = buf + ix;
	    put8(s, ERL_NEW_FUN_EXT);
	    size_p = s;
	    s += 4;
	    put8(s, p->arity);
	    memcpy(s, p->md5, sizeof(p->md5));
	    s += sizeof(p->md5);
	    put32be(s, p->index);
	    put32be(s, p->n_free_vars);
	} else
	    size_p = NULL;
	ix += 1 + 4 + 1 + sizeof(p->md5) + 4 + 4;
	if (ei_encode_atom(buf, &ix, p->module) < 0)
	    return -1;
	if (ei_encode_long(buf, &ix, p->old_index) < 0)
	    return -1;
	if (ei_encode_long(buf, &ix, p->uniq) < 0)
	    return -1;
	if (ei_encode_pid(buf, &ix, &p->pid) < 0)
	    return -1;
	if (buf != NULL)
	    memcpy(buf + ix, p->free_vars, p->free_var_len);
	ix += p->free_var_len;
	if (size_p != NULL) {
	    int sz = buf + ix - size_p;
	    put32be(size_p, sz);
	}
    }
    *index = ix;
    return 0;
}

