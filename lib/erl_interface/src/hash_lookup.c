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
#include <string.h>
#include "eihash.h"

extern void *ei_hash_lookup(ei_hash *tab, const char *key)
{
  int h, rh;
  ei_bucket *b=NULL;

  rh = tab->hash(key);
  h =  rh % tab->size;
  
  b=tab->tab[h];
  while (b) {
    if ((rh == b->rawhash) && (!strcmp(key,b->key)))
      return (void *)b->value;
    b=b->next;
  }
  return NULL;
}

