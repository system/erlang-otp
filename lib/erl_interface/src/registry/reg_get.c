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
#ifdef VXWORKS
#include <vxWorks.h>
#endif

#include <stdarg.h>
#include "reg.h"

/* this is the general "get" function. Values are copied into a buffer
 * provided by the caller, and the return value indicates success or
 * failure. This function can get all types except directorys. The user
 * must specify the type of data he is expecting, or 0 if he doesn't
 * care. On success, the data type is returned. If the requested data
 * type does not match the data found, EI_TYPE is returned. 
 */
int ei_reg_getval(ei_reg *reg, const char *key, int flags, ...)
{
  ei_hash *tab;
  ei_reg_obj *obj=NULL;
  va_list ap;
  int rval;
  int objtype;
  
  if (!key || !reg) return -1; /* return EI_BADARG; */
  tab = reg->tab;
  if (!(obj=ei_hash_lookup(tab,key))) return -1; /* return EI_NOTFOUND; */
  if (obj->attr & EI_DELET) return -1; /* return EI_NOTFOUND; */

  /* if type was specified then it must match object */
  objtype = ei_reg_typeof(obj);
  if (flags && (flags != objtype)) return -1; /* return EI_TYPE; */

  va_start(ap,flags);

  switch ((rval = objtype)) {
  case EI_INT: {
    long *ip;

    if (!(ip = va_arg(ap,long*))) rval = -1; /* EI_BADARG; */
    else *ip = obj->val.i;
    break;
  }
  case EI_FLT: {
    double *fp;

    if (!(fp = va_arg(ap,double*))) rval = -1; /*  EI_BADARG; */
    else *fp = obj->val.f;
    break;
  }
  case EI_STR: {
    char **sp;

    if (!(sp = va_arg(ap,char**))) rval = -1; /* EI_BADARG; */
    else *sp = obj->val.s;
    break;
  }
  case EI_BIN: {
    void **pp;
    int *size;

    if (!(pp = va_arg(ap,void**))) rval = -1; /* EI_BADARG; */
    else *pp = obj->val.p;
    if ((size=va_arg(ap,int*))) *size=obj->size;
    break;
  }
  default:
    /* can't (should never) happen */
    rval = -1;
    /* rval = EI_UNKNOWN; */
  }

  /* clean up & return */
  va_end(ap);
  return rval;
}
