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

#ifndef ERL_MTRACE_H__
#define ERL_MTRACE_H__

#include "erl_alloc_types.h"

#if (defined(ERTS___AFTER_MORECORE_HOOK_CAN_TRACK_MALLOC) \
     || defined(ERTS_BRK_WRAPPERS_CAN_TRACK_MALLOC))
#undef ERTS_CAN_TRACK_MALLOC
#define ERTS_CAN_TRACK_MALLOC
#endif

#define ERTS_MTRACE_SEGMENT_ID ERTS_ALC_A_INVALID

extern int erts_mtrace_enabled;

void erts_mtrace_pre_init(void);
void erts_mtrace_init(char *receiver, char *nodename);
void erts_mtrace_install_wrapper_functions(void);
void erts_mtrace_stop(void);
void erts_mtrace_exit(Uint32 exit_value);

void erts_mtrace_crr_alloc(void*, ErtsAlcType_t, ErtsAlcType_t, Uint);
void erts_mtrace_crr_realloc(void*, ErtsAlcType_t, ErtsAlcType_t, void*, Uint);
void erts_mtrace_crr_free(ErtsAlcType_t, ErtsAlcType_t, void*);


void erts_mtrace_update_heap_size(void); /* Implemented in
					  * ../sys/common/erl_mtrace_sys_wrap.c
					  */

#endif /* #ifndef ERL_MTRACE_H__ */

