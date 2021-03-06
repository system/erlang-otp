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
#include <stdlib.h>
#include "reg.h"


/* make a new ei_reg_obj object. If the freelist for this registry is
 * not empty, an object will be returned from there. Otherwise one
 * will be created with malloc().
 */
ei_reg_obj *ei_reg_make(ei_reg *reg, int attr)
{
  ei_reg_obj *new=NULL;

  if (reg->freelist) {
    new = reg->freelist;
    reg->freelist = new->next;
    /* fprintf(stderr,"%s:%d: found %p on freelist\n",__FILE__,__LINE__,new); */
  }
  else {
    new = malloc(sizeof(*new));
    /* fprintf(stderr,"%s:%d: allocated %p\n",__FILE__,__LINE__,new); */
  }

  if (new) {
    new->attr=attr | EI_DIRTY;
    new->size=0;
    new->next = NULL;
  }
  return new;
}
