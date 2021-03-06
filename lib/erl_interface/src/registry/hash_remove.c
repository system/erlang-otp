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
#include "hash.h"

/* free a hash bucket. If the bucket contained a long key (more that
 * EI_SMALLKEY) the bucket is thrown away (really freed). If the
 * bucket contained a short key, then it can be saved on the freelist
 * for later use. Buckets with short keys have (key == keybuf).
 */
void ei_hash_bfree(ei_hash *tab, ei_bucket *b)
{
  if (!b) return;

  /* we throw away buckets with long keys (i.e. non-standard buckets) */
  if (b->key != b->keybuf) {
    /* fprintf(stderr,"freeing bucket with long key (%s)\n",b->key); */
    free(b);
  }
    
  else {
    /* others we save on (tab-local) freelist */
    /* fprintf(stderr,"saving bucket with short key (%s)\n",b->key); */
    b->next = tab->freelist;
    tab->freelist = b;
  }

  return;
}

void *ei_hash_remove(ei_hash *tab, const char *key) 
{
  ei_bucket *b=NULL, *tmp=NULL;
  const void *oldval=NULL;
  int h, rh;

  rh = tab->hash(key);
  h =  rh % tab->size;

  /* is it in the first position? */
  if ((b=tab->tab[h])) {
    if ((rh == b->rawhash) && (!strcmp(key,b->key))) {
      tab->tab[h] = b->next;
      oldval = b->value;
      ei_hash_bfree(tab,b);

      tab->nelem--;
      if (!tab->tab[h]) tab->npos--;
    }
    else {
      /* is it later in the chain? */
      while (b->next) {
	if ((rh == b->next->rawhash) && (!strcmp(key,b->next->key))) {
	  tmp = b->next;
	  b->next = tmp->next;
	  oldval = tmp->value;
	  ei_hash_bfree(tab,tmp);

	  tab->nelem--;
	  break;
	}
	b=b->next;
      }
    }
  }
  return (void *)oldval;
}

