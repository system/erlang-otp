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
#include "eidef.h"
#include "eiext.h"
#include "putget.h"

int ei_decode_char(const char *buf, int *index, char *p)
{
  const char *s = buf + *index;
  const char *s0 = s;
  long n;
  int arity;

  switch (get8(s)) {
  case ERL_SMALL_INTEGER_EXT:
    n = get8(s);
    break;
    
  case ERL_INTEGER_EXT:
    n = get32be(s);
    if (n < 0 || n > 255)
      return -1;
    break;
    
  case ERL_SMALL_BIG_EXT:
    arity = get8(s);
    goto decode_big;
  case ERL_LARGE_BIG_EXT:
    arity = get32be(s);
  decode_big:
    {
      int sign = get8(s);
      int i;

      if (sign) return -1;	/* Char is always > 0 */

      n = get8(s);		/* First byte is our value */

      for (i = 1; i < arity; i++) {
	if (*(s++) != 0) return -1; /* All but first byte have to be 0 */
      }
    }
    break;
    
  default:
    return -1;
  }

  if (p) *p = n;
  *index += s-s0;
  
  return 0; 
}
