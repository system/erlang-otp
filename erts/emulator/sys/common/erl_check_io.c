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
 * Description:	Check I/O
 *
 * Author: 	Rickard Green
 */

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#define ERL_CHECK_IO_C__
#define ERTS_WANT_BREAK_HANDLING
#ifndef WANT_NONBLOCKING
#  define WANT_NONBLOCKING
#endif
#include "sys.h"
#include "global.h"
#include "erl_check_io.h"
#ifndef ERTS_SYS_CONTINOUS_FD_NUMBERS
#include "hash.h"
#endif

#define ERTS_EV_FLG_IGNORE		(((short) 1) << 0)

#define ERTS_EV_TYPE_NONE		((short) 0)
#define ERTS_EV_TYPE_DRV_SEL		((short) 1)
#define ERTS_EV_TYPE_DRV_EV		((short) 2)

#define ERTS_DRV_EV_STATE_EXTRA_SIZE 128

#if defined(ERTS_KERNEL_POLL_VERSION)
#  define ERTS_CIO_EXPORT(FUNC) FUNC ## _kp
#elif defined(ERTS_NO_KERNEL_POLL_VERSION)
#  define ERTS_CIO_EXPORT(FUNC) FUNC ## _nkp
#else
#  define ERTS_CIO_EXPORT(FUNC) FUNC
#endif

#define ERTS_CIO_HAVE_DRV_EVENT \
  (ERTS_POLL_USE_POLL && !ERTS_POLL_USE_KERNEL_POLL)

#define ERTS_CIO_POLL_CTL	ERTS_POLL_EXPORT(erts_poll_control)
#define ERTS_CIO_POLL_WAIT	ERTS_POLL_EXPORT(erts_poll_wait)
#define ERTS_CIO_POLL_INTR 	ERTS_POLL_EXPORT(erts_poll_interrupt)
#define ERTS_CIO_POLL_INTR_TMD	ERTS_POLL_EXPORT(erts_poll_interrupt_timed)
#define ERTS_CIO_NEW_POLLSET 	ERTS_POLL_EXPORT(erts_poll_create_pollset)
#define ERTS_CIO_FREE_POLLSET	ERTS_POLL_EXPORT(erts_poll_destroy_pollset)
#define ERTS_CIO_POLL_MAX_FDS	ERTS_POLL_EXPORT(erts_poll_max_fds)
#define ERTS_CIO_POLL_INIT	ERTS_POLL_EXPORT(erts_poll_init)
#define ERTS_CIO_POLL_INFO	ERTS_POLL_EXPORT(erts_poll_info)

static ErtsPollSet pollset;

typedef struct {
#ifndef ERTS_SYS_CONTINOUS_FD_NUMBERS
    HashBucket hb;
#endif
    ErtsSysFdType fd;
    union {
	ErtsDrvEventDataState *event;
	ErtsDrvSelectDataState *select;
    } driver;
    ErtsPollEvents events;
    short flags;
    short type;
} ErtsDrvEventState;

struct erts_fd_list {
    struct erts_fd_list *next;
    ErtsSysFdType fd;
};

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
static int max_fds = -1;
#endif
static erts_smp_mtx_t drv_ev_state_mtx;

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS

static int drv_ev_state_len;
static ErtsDrvEventState *drv_ev_state;

#else
static Hash drv_ev_state_tab;
static int num_state_prealloc;
static ErtsDrvEventState *state_prealloc_first;

static ERTS_INLINE ErtsDrvEventState *hash_get_drv_ev_state(ErtsSysFdType fd)
{
    ErtsDrvEventState tmpl;
    tmpl.fd = fd;
    return  (ErtsDrvEventState *) hash_get(&drv_ev_state_tab, (void *) &tmpl);
}

static ERTS_INLINE ErtsDrvEventState *hash_new_drv_ev_state(ErtsSysFdType fd)
{
    ErtsDrvEventState tmpl;
    tmpl.fd = fd;
    tmpl.driver.select = NULL;
    tmpl.events = 0;
    tmpl.flags = 0;
    tmpl.type = ERTS_EV_TYPE_NONE;
    return  (ErtsDrvEventState *) hash_put(&drv_ev_state_tab, (void *) &tmpl);
}

static ERTS_INLINE void hash_erase_drv_ev_state(ErtsDrvEventState *state)
{
    hash_erase(&drv_ev_state_tab, (void *) state);
}

#endif

static erts_smp_atomic_t in_poll_wait;

struct erts_fd_list *ignored_list;

static void stale_drv_select(Eterm id, ErtsDrvEventState *state, int mode);
static void select_steal(ErlDrvPort ix, ErtsDrvEventState *state, 
			 int mode, int on);
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
static void select_large_fd_error(ErlDrvPort, ErtsSysFdType, int, int);
#endif
#if ERTS_CIO_HAVE_DRV_EVENT
static void event_steal(ErlDrvPort ix, ErtsDrvEventState *state, 
			ErlDrvEventData event_data);
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
static void event_large_fd_error(ErlDrvPort, ErtsSysFdType, ErlDrvEventData);
#endif
#endif

static ERTS_INLINE Eterm
drvport2id(ErlDrvPort dp)
{
    Port *pp = erts_drvport2port(dp);
    if (pp)
	return pp->id;
    else {
	ASSERT(0);
	return am_undefined;
    }
}

ERTS_QUALLOC_IMPL(fd_list, struct erts_fd_list, 64, ERTS_ALC_T_FD_LIST)

static ERTS_INLINE void
check_ignore(ErtsDrvEventState *state, ErtsPollEvents new_evs, ErtsPollEvents old_evs)
{

    if (!new_evs
	&& old_evs
	&& !(state->flags & ERTS_EV_FLG_IGNORE)
	&& erts_smp_atomic_read(&in_poll_wait)) {
	struct erts_fd_list *fdlp = fd_list_alloc();
	fdlp->fd = state->fd;
	fdlp->next = ignored_list;
	ignored_list = fdlp;
	state->flags |= ERTS_EV_FLG_IGNORE;
    }

}

static ERTS_INLINE void
reset_ignores(void)
{
    struct erts_fd_list *fdlp = ignored_list;

    while (fdlp) {
	struct erts_fd_list *ffdlp = fdlp;
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
	drv_ev_state[(int) fdlp->fd].flags &= ~ERTS_EV_FLG_IGNORE;
#else
	{
	    ErtsDrvEventState *state = hash_get_drv_ev_state(fdlp->fd);
	    if (state != NULL) 
		state->flags &= ~ERTS_EV_FLG_IGNORE;
	}
#endif
	fdlp = fdlp->next;
	fd_list_free(ffdlp);
    }
    ignored_list = NULL;
}

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
static void
grow_drv_ev_state(int min_ix)
{
    int i;
    int new_len = min_ix + 1 + ERTS_DRV_EV_STATE_EXTRA_SIZE;
    if (new_len > max_fds)
	new_len = max_fds;
    drv_ev_state = (drv_ev_state_len
		     ? erts_realloc(ERTS_ALC_T_DRV_EV_STATE,
				    drv_ev_state,
				    sizeof(ErtsDrvEventState)*new_len)
		     : erts_alloc(ERTS_ALC_T_DRV_EV_STATE,
				  sizeof(ErtsDrvEventState)*new_len));
    for (i = drv_ev_state_len; i < new_len; i++) {
	drv_ev_state[i].fd = (ErtsSysFdType) i;
	drv_ev_state[i].driver.select = NULL;
	drv_ev_state[i].events = 0;
	drv_ev_state[i].flags = 0;
	drv_ev_state[i].type = ERTS_EV_TYPE_NONE;
    }
    drv_ev_state_len = new_len;
}
#endif

static ERTS_INLINE void
abort_task(Eterm id, ErtsPortTaskHandle *pthp, short type)
{
    if (is_nil(id)) {
	ASSERT(type == ERTS_EV_TYPE_NONE
	       || !erts_port_task_is_scheduled(pthp));
    }
    else if (erts_port_task_is_scheduled(pthp)) {
	erts_port_task_abort(pthp);
	ASSERT(erts_is_port_alive(id));
    }
}

static ERTS_INLINE void
abort_tasks(ErtsDrvEventState *state, int mode)
{
    switch (mode) {
    case 0: check_type:
	switch (state->type) {
#if ERTS_CIO_HAVE_DRV_EVENT
	case ERTS_EV_TYPE_DRV_EV:
	    abort_task(state->driver.event->port,
		       &state->driver.event->task,
		       ERTS_EV_TYPE_DRV_EV);
	    return;
#endif
	case ERTS_EV_TYPE_NONE:
	    return;
	default:
	    ASSERT(state->type == ERTS_EV_TYPE_DRV_SEL);
	    /* Fall through */
	}
    case DO_READ|DO_WRITE:
    case DO_WRITE:
	ASSERT(state->type == ERTS_EV_TYPE_DRV_SEL);
	abort_task(state->driver.select->outport,
		   &state->driver.select->outtask,
		   state->type);
	if (mode == DO_WRITE)
	    break;
    case DO_READ:
	ASSERT(state->type == ERTS_EV_TYPE_DRV_SEL);
	abort_task(state->driver.select->inport,
		   &state->driver.select->intask,
		   state->type);
	break;
    default:
	goto check_type;
    }
}

static void
deselect(ErtsDrvEventState *state, int mode)
{
    ErtsPollEvents old_events = state->events;
    ErtsPollEvents rm_events;
    ERTS_SMP_LC_ASSERT(erts_smp_lc_mtx_is_locked(&drv_ev_state_mtx));
    ASSERT(state->events);

    abort_tasks(state, mode);

    if (!mode)
	rm_events = state->events;
    else {
	rm_events = 0;
	ASSERT(state->type == ERTS_EV_TYPE_DRV_SEL);
	if (mode & DO_READ) {
	    state->driver.select->inport = NIL;
	    rm_events |= ERTS_POLL_EV_IN;
	}
	if (mode & DO_WRITE) {
	    state->driver.select->outport = NIL;
	    rm_events |= ERTS_POLL_EV_OUT;
	}
    }

    state->events = ERTS_CIO_POLL_CTL(pollset, state->fd, rm_events, 0);

    if (!(state->events)) {
	switch (state->type) {
	case ERTS_EV_TYPE_DRV_SEL:
	    ASSERT(!erts_port_task_is_scheduled(&state->driver.select->intask));
	    ASSERT(!erts_port_task_is_scheduled(&state->driver.select->outtask));
	    erts_free(ERTS_ALC_T_DRV_SEL_D_STATE,
		      state->driver.select);
	    break;
#if ERTS_CIO_HAVE_DRV_EVENT
	case ERTS_EV_TYPE_DRV_EV:
	    ASSERT(!erts_port_task_is_scheduled(&state->driver.event->task));
	    erts_free(ERTS_ALC_T_DRV_EV_D_STATE,
		      state->driver.event);
	    break;
#endif
	case ERTS_EV_TYPE_NONE:
	    break;
	default:
	    ASSERT(0);
	    break;
	}
	    
	state->driver.select = NULL;
	state->flags = 0;
	state->type = ERTS_EV_TYPE_NONE;
    }
    check_ignore(state, state->events, old_events);
}

int
ERTS_CIO_EXPORT(driver_select)(ErlDrvPort ix,
			       ErlDrvEvent e,
			       int mode,
			       int on)
{
    Eterm id = drvport2id(ix);
    ErtsSysFdType fd = (ErtsSysFdType) e;
    ErtsPollEvents ctl_events = (ErtsPollEvents) 0;
    ErtsPollEvents new_events, old_events;
    ErtsDrvEventState *state;

    ERTS_SMP_LC_ASSERT(erts_drvport2port(ix)
		       && erts_lc_is_port_locked(erts_drvport2port(ix)));

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (fd < 0)
	return -1;

    if (fd >= max_fds) {
	select_large_fd_error(ix, fd, mode, on);
	return -1;
    }
#endif

    erts_smp_mtx_lock(&drv_ev_state_mtx);

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (fd >= drv_ev_state_len)
	grow_drv_ev_state(fd);
    state = &drv_ev_state[(int) fd];
#else
    /* Could use hash_new directly, but want to keep the normal case fast */
    state = hash_get_drv_ev_state(fd);
    if (state == NULL) {
	state = hash_new_drv_ev_state(fd);
    }
#endif
    
#if ERTS_CIO_HAVE_DRV_EVENT
    if (state->type == ERTS_EV_TYPE_DRV_EV)
	select_steal(ix, state, mode, on);;
#endif

    if (mode & DO_READ) {
	if (state->type == ERTS_EV_TYPE_DRV_SEL) {
	    Eterm owner = state->driver.select->inport;
	    if (owner != id && is_not_nil(owner))
		select_steal(ix, state, mode, on);
	}
	ctl_events |= ERTS_POLL_EV_IN;
    }
    if (mode & DO_WRITE) {
	if (state->type == ERTS_EV_TYPE_DRV_SEL) {
	    Eterm owner = state->driver.select->outport;
	    if (owner != id && is_not_nil(owner))
		select_steal(ix, state, mode, on);
	}
	ctl_events |= ERTS_POLL_EV_OUT;
    }	

    ASSERT(state->events
	   ? (state->type == ERTS_EV_TYPE_DRV_SEL)
	   : (state->type == ERTS_EV_TYPE_NONE));

    new_events = ERTS_CIO_POLL_CTL(pollset, state->fd, ctl_events, on);
    if (new_events & (ERTS_POLL_EV_ERR|ERTS_POLL_EV_NVAL))
	goto error;

    old_events = state->events;

    ASSERT(on
	   ? (new_events == (state->events | ctl_events))
	   : (new_events == (state->events & ~ctl_events)));

    ASSERT(state->type == ERTS_EV_TYPE_DRV_SEL
	   || state->type == ERTS_EV_TYPE_NONE);

    state->events = new_events;
    if (ctl_events) {
	if (on) {
	    if (state->type == ERTS_EV_TYPE_NONE) {
		ErtsDrvSelectDataState *dsdsp
		    = erts_alloc(ERTS_ALC_T_DRV_SEL_D_STATE,
				 sizeof(ErtsDrvSelectDataState));
		dsdsp->inport = NIL;
		dsdsp->outport = NIL;
		erts_port_task_handle_init(&dsdsp->intask);
		erts_port_task_handle_init(&dsdsp->outtask);
		state->driver.select = dsdsp;
		state->type = ERTS_EV_TYPE_DRV_SEL;
	    }
	    ASSERT(state->type == ERTS_EV_TYPE_DRV_SEL);
	    if (ctl_events & ERTS_POLL_EV_IN)
		state->driver.select->inport = id;
	    if (ctl_events & ERTS_POLL_EV_OUT)
		state->driver.select->outport = id;
	}
	else if (state->type == ERTS_EV_TYPE_DRV_SEL) {
	    if (ctl_events & ERTS_POLL_EV_IN) {
		abort_tasks(state, DO_READ);
		state->driver.select->inport = NIL;
	    }
	    if (ctl_events & ERTS_POLL_EV_OUT) {
		abort_tasks(state, DO_WRITE);
		state->driver.select->outport = NIL;
	    }
	    if (new_events == 0) {
		ASSERT(!erts_port_task_is_scheduled(&state->driver.select->intask));
		ASSERT(!erts_port_task_is_scheduled(&state->driver.select->outtask));
		erts_free(ERTS_ALC_T_DRV_SEL_D_STATE,
			  state->driver.select);
		state->driver.select = NULL;
		state->flags = 0;
		state->type = ERTS_EV_TYPE_NONE;
	    }
	}
    }
    check_ignore(state, new_events, old_events);

#ifndef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (state->type == ERTS_EV_TYPE_NONE) {
	hash_erase_drv_ev_state(state);
    }
#endif
    
    erts_smp_mtx_unlock(&drv_ev_state_mtx);

    return 0;

 error:

#ifndef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (state->type == ERTS_EV_TYPE_NONE) {
	hash_erase_drv_ev_state(state);
    }
#endif

   erts_smp_mtx_unlock(&drv_ev_state_mtx);
    return -1;
}

int
ERTS_CIO_EXPORT(driver_event)(ErlDrvPort ix,
			      ErlDrvEvent e,
			      ErlDrvEventData event_data)
{
#if !ERTS_CIO_HAVE_DRV_EVENT
    return -1;
#else
    ErtsSysFdType fd = (ErtsSysFdType) e;
    ErtsPollEvents events;
    ErtsPollEvents add_events;
    ErtsPollEvents remove_events;
    Eterm id = drvport2id(ix);
    ErtsDrvEventState *state;

    ERTS_SMP_LC_ASSERT(erts_drvport2port(ix)
		       && erts_lc_is_port_locked(erts_drvport2port(ix)));

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (fd < 0)
	return -1;

    if (fd >= max_fds) {
	event_large_fd_error(ix, fd, event_data);
	return -1;
    }
#endif

    erts_smp_mtx_lock(&drv_ev_state_mtx);

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (fd >= drv_ev_state_len)
	grow_drv_ev_state(fd);
    state = &drv_ev_state[(int) fd];
#else
    /* Could use hash_new directly, but want to keep the normal case fast */
    state = hash_get_drv_ev_state(fd);
    if (state == NULL) {
	state = hash_new_drv_ev_state(fd);
    }
#endif

    if (state->type == ERTS_EV_TYPE_DRV_SEL
	|| (state->type == ERTS_EV_TYPE_DRV_EV
	    && state->driver.event->port != id)) {
	event_steal(ix, state, event_data);
    }

    ASSERT(state->type == ERTS_EV_TYPE_DRV_EV
	   || state->type == ERTS_EV_TYPE_NONE);

    events = state->events;

    if (!event_data) {
	remove_events = events;
	add_events = 0;
    }
    else {
	remove_events = ~event_data->events & events;
	add_events = ~events & event_data->events;

    }

    if (add_events) {
	events = ERTS_CIO_POLL_CTL(pollset, state->fd, add_events, 1);
	if (events & (ERTS_POLL_EV_ERR|ERTS_POLL_EV_NVAL))
	    goto error;
    }
    if (remove_events) {
	events = ERTS_CIO_POLL_CTL(pollset, state->fd, remove_events, 0);
	if (events & (ERTS_POLL_EV_ERR|ERTS_POLL_EV_NVAL))
	    goto error;
    }
    if (event_data) {
	if (state->type == ERTS_EV_TYPE_DRV_EV) {
	    state->driver.event->removed_events &= ~add_events;
	    state->driver.event->removed_events |= remove_events;
	}
	else {
	    state->driver.event
		= erts_alloc(ERTS_ALC_T_DRV_EV_D_STATE,
			     sizeof(ErtsDrvEventDataState));
	    erts_port_task_handle_init(&state->driver.event->task);
	    state->driver.event->port = id;
	    state->driver.event->removed_events = (ErtsPollEvents) 0;
	    state->type = ERTS_EV_TYPE_DRV_EV;
	}
	state->driver.event->data = event_data;
    }
    else {
	if (state->type == ERTS_EV_TYPE_DRV_EV) {
	    abort_tasks(state, 0);
	    erts_free(ERTS_ALC_T_DRV_EV_D_STATE,
		      state->driver.event);
	}
	state->driver.select = NULL;
	state->flags = 0;
	state->type = ERTS_EV_TYPE_NONE;
    }
    check_ignore(state, events, state->events);
    state->events = events;
    ASSERT(event_data ? events == event_data->events : events == 0); 

#ifndef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (state->type == ERTS_EV_TYPE_NONE) {
	hash_erase_drv_ev_state(state);
    }
#endif

    erts_smp_mtx_unlock(&drv_ev_state_mtx);
    return 0;
 error:

#ifndef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (state->type == ERTS_EV_TYPE_NONE) {
	hash_erase_drv_ev_state(state);
    }
#endif

    erts_smp_mtx_unlock(&drv_ev_state_mtx);
    return -1;
#endif
}

static ERTS_INLINE int
chk_stale(Eterm id, ErtsDrvEventState *state, int mode)
{
    if (is_nil(id))
	return 0;
    if (erts_is_port_alive(id))
	return 1; /* Steal */
    stale_drv_select(id, state, mode);
    return 0;
}

static int
need2steal(ErtsDrvEventState *state, int mode)
{
    int do_steal = 0;
    switch (state->type) {
    case ERTS_EV_TYPE_DRV_SEL:
	if (mode & DO_READ)
	    do_steal |= chk_stale(state->driver.select->inport,
				  state,
				  DO_READ);
	if (mode & DO_WRITE)
	    do_steal |= chk_stale(state->driver.select->outport,
				  state,
				  DO_WRITE);
	break;
#if ERTS_CIO_HAVE_DRV_EVENT
    case ERTS_EV_TYPE_DRV_EV:
	do_steal |= chk_stale(state->driver.event->port, state, 0);
	break;
#endif
    default:
	break;
    }
    return do_steal;
}

static void
print_driver_name(erts_dsprintf_buf_t *dsbufp, Eterm id)
{
    ErtsPortNames *pnp = erts_get_port_names(id);
    if (!pnp->name && !pnp->driver_name)
	erts_dsprintf(dsbufp, "%s ", "<unknown>");
    else {
	if (pnp->name) {
	    if (!pnp->driver_name || strcmp(pnp->driver_name, pnp->name) == 0)
		erts_dsprintf(dsbufp, "%s ", pnp->name);
	    else
		erts_dsprintf(dsbufp, "%s (%s) ", pnp->driver_name, pnp->name);
	}
	else if (pnp->driver_name) {
	    erts_dsprintf(dsbufp, "%s ", pnp->driver_name);
	}
    }
    erts_free_port_names(pnp);
}

static void
steal(erts_dsprintf_buf_t *dsbufp, ErtsDrvEventState *state, int mode)
{
    erts_dsprintf(dsbufp, "stealing control of fd=%d from ", (int) state->fd);
    switch (state->type) {
    case ERTS_EV_TYPE_DRV_SEL: {
	int deselect_mode = 0;
	Eterm iid = state->driver.select->inport;
	Eterm oid = state->driver.select->outport;
	if ((mode & DO_READ) && (is_not_nil(iid))) {
	    erts_dsprintf(dsbufp, "input driver ");
	    print_driver_name(dsbufp, iid);
	    erts_dsprintf(dsbufp, "%T ", iid);
	    deselect_mode |= DO_READ;
	}
	if ((mode & DO_READ) && is_not_nil(iid)
	    && (mode & DO_WRITE) && is_not_nil(oid))
	    erts_dsprintf(dsbufp, "and ");
	if ((mode & DO_WRITE) && is_not_nil(oid)) {
	    erts_dsprintf(dsbufp, "output driver ");
	    print_driver_name(dsbufp, oid);
	    erts_dsprintf(dsbufp, "%T ", oid);
	    deselect_mode |= DO_WRITE;
	}
	if (deselect_mode)
	    deselect(state, deselect_mode);
	else {
	    erts_dsprintf(dsbufp, "no one", (int) state->fd);
	    ASSERT(0);
	}
	erts_dsprintf(dsbufp, "\n");
	break;
    }
#if ERTS_CIO_HAVE_DRV_EVENT
    case ERTS_EV_TYPE_DRV_EV: {
	Eterm eid = state->driver.event->port;
	if (is_nil(eid)) {
	    erts_dsprintf(dsbufp, "no one", (int) state->fd);
	    ASSERT(0);
	}
	else {
	    erts_dsprintf(dsbufp, "event driver ");
	    print_driver_name(dsbufp, eid);
	    erts_dsprintf(dsbufp, "%T ", eid);
	}
	erts_dsprintf(dsbufp, "\n");
	deselect(state, 0);
	break;
    }
#endif
    default:
	erts_dsprintf(dsbufp, "no one\n", (int) state->fd);
	ASSERT(0);
    }
}

static void
print_select_op(erts_dsprintf_buf_t *dsbufp,
		ErlDrvPort ix, ErtsSysFdType fd, int mode, int on)
{
    Port *pp = erts_drvport2port(ix);
    erts_dsprintf(dsbufp,
		  "driver_select(%p, %d, %s%s%s, %d) "
		  "by ",
		  ix,
		  (int) fd,
		  mode & DO_READ ? "DO_READ" : "",
		  (mode & (DO_READ|DO_WRITE)) == (DO_READ|DO_WRITE) ? "|" : "",
		  mode & DO_WRITE ? "DO_WRITE" : "",
		  on);
    print_driver_name(dsbufp, pp->id);
    erts_dsprintf(dsbufp, "driver %T ", pp ? pp->id : NIL);
}

static void
select_steal(ErlDrvPort ix, ErtsDrvEventState *state, int mode, int on)
{
    if (need2steal(state, mode)) {
	erts_dsprintf_buf_t *dsbufp = erts_create_logger_dsbuf();
	print_select_op(dsbufp, ix, state->fd, mode, on);
	steal(dsbufp, state, mode);
	erts_send_error_to_logger_nogl(dsbufp);
    }
}

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
static void
large_fd_error_common(erts_dsprintf_buf_t *dsbufp, ErtsSysFdType fd)
{
    erts_dsprintf(dsbufp,
		  "fd=%d is larger than the largest allowed fd=%d\n",
		  (int) fd, max_fds - 1);
}

static void
select_large_fd_error(ErlDrvPort ix, ErtsSysFdType fd, int mode, int on)
{
    erts_dsprintf_buf_t *dsbufp = erts_create_logger_dsbuf();
    print_select_op(dsbufp, ix, fd, mode, on);
    erts_dsprintf(dsbufp, "failed: ");
    large_fd_error_common(dsbufp, fd);
    erts_send_error_to_logger_nogl(dsbufp);
}
#endif

#if ERTS_CIO_HAVE_DRV_EVENT

static void
print_event_op(erts_dsprintf_buf_t *dsbufp,
	       ErlDrvPort ix, ErtsSysFdType fd, ErlDrvEventData event_data)
{
    Port *pp = erts_drvport2port(ix);
    erts_dsprintf(dsbufp, "driver_event(%p, %d, ", ix, (int) fd);
    if (!event_data)
	erts_dsprintf(dsbufp, "NULL");
    else
	erts_dsprintf(dsbufp, "{0x%x, 0x%x}",
		      (unsigned int) event_data->events,
		      (unsigned int) event_data->revents);
    erts_dsprintf(dsbufp, ") by ");
    print_driver_name(dsbufp, pp->id);
    erts_dsprintf(dsbufp, "driver %T ", pp ? pp->id : NIL);
}

static void
event_steal(ErlDrvPort ix, ErtsDrvEventState *state, ErlDrvEventData event_data)
{
    if (need2steal(state, DO_READ|DO_WRITE)) {
	erts_dsprintf_buf_t *dsbufp = erts_create_logger_dsbuf();
	print_event_op(dsbufp, ix, state->fd, event_data);
	steal(dsbufp, state, DO_READ|DO_WRITE);
	erts_send_error_to_logger_nogl(dsbufp);
    }
}

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
static void
event_large_fd_error(ErlDrvPort ix, ErtsSysFdType fd, ErlDrvEventData event_data)
{
    erts_dsprintf_buf_t *dsbufp = erts_create_logger_dsbuf();
    print_event_op(dsbufp, ix, fd, event_data);
    erts_dsprintf(dsbufp, "failed: ");
    large_fd_error_common(dsbufp, fd);
    erts_send_error_to_logger_nogl(dsbufp);
}
#endif
#endif

static ERTS_INLINE void
iready(Eterm id, ErtsDrvEventState *state)
{
    if (erts_port_task_schedule(id,
				&state->driver.select->intask,
				ERTS_PORT_TASK_INPUT,
				(ErlDrvEvent) state->fd,
				NULL) != 0) {
	stale_drv_select(id, state, DO_READ);
    }
}

static ERTS_INLINE void
oready(Eterm id, ErtsDrvEventState *state)
{
    if (erts_port_task_schedule(id,
				&state->driver.select->outtask,
				ERTS_PORT_TASK_OUTPUT,
				(ErlDrvEvent) state->fd,
				NULL) != 0) {
	stale_drv_select(id, state, DO_WRITE);
    }
}

#if ERTS_CIO_HAVE_DRV_EVENT
static ERTS_INLINE void
eready(Eterm id, ErtsDrvEventState *state, ErlDrvEventData event_data)
{
    if (erts_port_task_schedule(id,
				&state->driver.event->task,
				ERTS_PORT_TASK_EVENT,
				(ErlDrvEvent) state->fd,
				event_data) != 0) {
	stale_drv_select(id, state, 0);
    }
}
#endif

static void bad_fd_in_pollset( ErtsDrvEventState *, Eterm, Eterm, ErtsPollEvents);

void
ERTS_CIO_EXPORT(erts_check_io_interrupt)(int set)
{
    ERTS_CIO_POLL_INTR(pollset, set);
}

void
ERTS_CIO_EXPORT(erts_check_io_interrupt_timed)(int set, long msec)
{
    ERTS_CIO_POLL_INTR_TMD(pollset, set, msec);
}

void
ERTS_CIO_EXPORT(erts_check_io)(int do_wait)
{
    ErtsPollResFd pollres[256];
    int pollres_len;
    SysTimeval wait_time;
    int poll_ret, i;

 restart:

    /* Figure out timeout value */
    if (do_wait) {
	erts_time_remaining(&wait_time);
    } else {			/* poll only */
	wait_time.tv_sec = 0;
	wait_time.tv_usec = 0;
    }

#ifdef ERTS_ENABLE_LOCK_CHECK
    erts_lc_check_exact(NULL, 0); /* No locks should be locked */
#endif
    erts_smp_activity_begin(ERTS_ACTIVITY_WAIT, NULL, NULL, NULL);
    pollres_len = sizeof(pollres)/sizeof(ErtsPollResFd);
    erts_smp_atomic_set(&in_poll_wait, 1);
    poll_ret = ERTS_CIO_POLL_WAIT(pollset, pollres, &pollres_len, &wait_time);

#ifdef ERTS_ENABLE_LOCK_CHECK
    erts_lc_check_exact(NULL, 0); /* No locks should be locked */
#endif
    erts_smp_activity_end(ERTS_ACTIVITY_WAIT, NULL, NULL, NULL);

    erts_deliver_time(); /* sync the machine's idea of time */

#ifdef ERTS_BREAK_REQUESTED
    if (ERTS_BREAK_REQUESTED)
	erts_do_break_handling();
#endif

    if (poll_ret != 0) {
	erts_smp_atomic_set(&in_poll_wait, 0);

	if (poll_ret == EAGAIN)
	    goto restart;

	if (poll_ret != ETIMEDOUT
	    && poll_ret != EINTR
#ifdef ERRNO_BLOCK
	    && poll_ret != ERRNO_BLOCK
#endif
	    ) {
	    erts_dsprintf_buf_t *dsbufp = erts_create_logger_dsbuf();
	    erts_dsprintf(dsbufp, "erts_poll_wait() failed: %s (%d)\n",
			  erl_errno_id(poll_ret), poll_ret);
	    erts_send_error_to_logger_nogl(dsbufp);
	}

	return;
    }

    erts_smp_mtx_lock(&drv_ev_state_mtx);
    erts_smp_atomic_set(&in_poll_wait, 0);

    for (i = 0; i < pollres_len; i++) {
	ErtsSysFdType fd = (ErtsSysFdType) pollres[i].fd;
	ErtsDrvEventState *state;
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
	state = &drv_ev_state[ (int) fd];
#else
	state = hash_get_drv_ev_state(fd);
	if (state == NULL) {
	    continue;
	}
#endif

	if (state->flags & ERTS_EV_FLG_IGNORE)
	    continue;

	switch (state->type) {
	case ERTS_EV_TYPE_DRV_SEL: { /* Requested via driver_select()... */
	    ErtsPollEvents revents;
	    ErtsPollEvents revent_mask;

	    revent_mask = ~(ERTS_POLL_EV_IN|ERTS_POLL_EV_OUT);
	    revent_mask |= state->events;
	    revents = pollres[i].events & revent_mask;

	    if (revents & ERTS_POLL_EV_ERR) {
		/*
		 * Let the driver handle the error condition. Only input,
		 * only output, or nothing might have been selected.
		 * We *do not* want to call a callback that corresponds
		 * to an event not selected. revents might give us a clue
		 * on which one to call.
		 */ 
		if ((revents & ERTS_POLL_EV_IN)
		    || (!(revents & ERTS_POLL_EV_OUT)
			&& state->events & ERTS_POLL_EV_IN))
		    iready(state->driver.select->inport, state);
		else if (state->events & ERTS_POLL_EV_OUT)
		    oready(state->driver.select->outport, state);
	    }
	    else if (revents & (ERTS_POLL_EV_IN|ERTS_POLL_EV_OUT)) {
		if (revents & ERTS_POLL_EV_OUT)
		    oready(state->driver.select->outport, state);
		/* Someone might have deselected input since revents
		   was read (true also on the non-smp emulator since
		   oready() may have been called); therefore, update
		   revents... */
		revents &= ~(~state->events & ERTS_POLL_EV_IN);
		if (revents & ERTS_POLL_EV_IN)
		    iready(state->driver.select->inport, state);
	    }
	    else if (revents & ERTS_POLL_EV_NVAL) {
		bad_fd_in_pollset(state,
				  state->driver.select->inport,
				  state->driver.select->outport,
				  state->events);
	    }
	    break;
	}

#if ERTS_CIO_HAVE_DRV_EVENT
	case ERTS_EV_TYPE_DRV_EV: { /* Requested via driver_event()... */
	    ErlDrvEventData event_data;
	    ErtsPollEvents revents;
	    ASSERT(state->driver.event);
	    ASSERT(state->driver.event->data);
	    event_data = state->driver.event->data;
	    revents = pollres[i].events;
	    revents &= ~state->driver.event->removed_events;

	    if (revents) {
		event_data->events = state->events;
		event_data->revents = revents;

		eready(state->driver.event->port, state, event_data);
	    }
	    break;
	}
#endif

	case ERTS_EV_TYPE_NONE: /* Deselected ... */
	    break;

	default: { /* Error */
	    erts_dsprintf_buf_t *dsbufp;
	    dsbufp = erts_create_logger_dsbuf();
	    erts_dsprintf(dsbufp,
			  "Invalid event request type for fd in erts_poll()! "
			  "fd=%d, event request type=%sd\n", (int) state->fd,
			  (int) state->type);
	    ASSERT(0);
	    deselect(state, 0);
	    break;
	}
	}

    }

    reset_ignores();

    erts_smp_mtx_unlock(&drv_ev_state_mtx);
}

static void
bad_fd_in_pollset(ErtsDrvEventState *state, Eterm inport, 
		  Eterm outport, ErtsPollEvents events)
{
    erts_dsprintf_buf_t *dsbufp = erts_create_logger_dsbuf();

    if (events & (ERTS_POLL_EV_IN|ERTS_POLL_EV_OUT)) {
	char *io_str;
	Eterm port = NIL;
	if ((events & ERTS_POLL_EV_IN) && (events & ERTS_POLL_EV_OUT)) {
	    io_str = "input/output";
	    if (inport == outport)
		port = inport;
	}
	else {
	    if (events & ERTS_POLL_EV_IN) {
		io_str = "input";
		port = inport;
	    }
	    else {
		io_str = "output";
		port = outport;
	    }
	}
	erts_dsprintf(dsbufp,
		      "Bad %s fd in erts_poll()! fd=%d, ",
		      io_str, (int) state->fd);
	if (is_nil(port)) {
	    ErtsPortNames *ipnp = erts_get_port_names(inport);
	    ErtsPortNames *opnp = erts_get_port_names(outport);
	    erts_dsprintf(dsbufp, "ports=%T/%T, drivers=%s/%s, names=%s/%s\n",
			  is_nil(inport) ? am_undefined : inport,
			  is_nil(outport) ? am_undefined : outport,
			  ipnp->driver_name ? ipnp->driver_name : "<unknown>",
			  opnp->driver_name ? opnp->driver_name : "<unknown>",
			  ipnp->name ? ipnp->name : "<unknown>",
			  opnp->name ? opnp->name : "<unknown>");
	    erts_free_port_names(ipnp);
	    erts_free_port_names(opnp);
	}
	else {
	    ErtsPortNames *pnp = erts_get_port_names(port);
	    erts_dsprintf(dsbufp, "port=%T, driver=%s, name=%s\n",
			  is_nil(port) ? am_undefined : port,
			  pnp->driver_name ? pnp->driver_name : "<unknown>",
			  pnp->name ? pnp->name : "<unknown>");
	    erts_free_port_names(pnp);
	}
    }
    else {
	erts_dsprintf(dsbufp, "Bad fd in erts_poll()! fd=%d\n", (int) state->fd);
    }
    erts_send_error_to_logger_nogl(dsbufp);

    /* unmap entry */
    deselect(state, 0);
}

static void
stale_drv_select(Eterm id, ErtsDrvEventState *state, int mode)
{
    erts_stale_drv_select(id, (ErlDrvEvent) state->fd, mode, 0);
    deselect(state, mode);
}

#ifndef ERTS_SYS_CONTINOUS_FD_NUMBERS
static HashValue drv_ev_state_hash(void *des)
{
    return (HashValue) ((ErtsDrvEventState *) des)->fd;
}

static int drv_ev_state_cmp(void *des1, void *des2)
{
    return ( ((ErtsDrvEventState *) des1)->fd == ((ErtsDrvEventState *) des2)->fd
	    ? 0 : 1);
}

static void *drv_ev_state_alloc(void *des_tmpl)
{
    ErtsDrvEventState *evstate;
    if (state_prealloc_first == NULL) {
	evstate = (ErtsDrvEventState *) 
	    erts_alloc(ERTS_ALC_T_DRV_EV_STATE, sizeof(ErtsDrvEventState));
    } else {
	evstate = state_prealloc_first;
	state_prealloc_first = (ErtsDrvEventState *) evstate->hb.next;
	--num_state_prealloc;
    }
    /* XXX: Already valid data if prealloced, could ignore template! */
    *evstate = *((ErtsDrvEventState *) des_tmpl);

    return (void *) evstate;
}

static void drv_ev_state_free(void *des)
{
    ((ErtsDrvEventState *) des)->hb.next = (struct hash_bucket *) state_prealloc_first;
    state_prealloc_first = (ErtsDrvEventState *) des;
    ++num_state_prealloc;
}
#endif

void
ERTS_CIO_EXPORT(erts_init_check_io)(void)
{
    init_fd_list_alloc();
    ignored_list = NULL;
    erts_smp_atomic_init(&in_poll_wait, 0);
    ERTS_CIO_POLL_INIT();
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    max_fds = ERTS_CIO_POLL_MAX_FDS();
#endif
    pollset = ERTS_CIO_NEW_POLLSET();
    erts_smp_mtx_init(&drv_ev_state_mtx, "drv_ev_state");
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    drv_ev_state_len = 0;
    drv_ev_state = NULL;
#else
    {
	HashFunctions hf;
	hf.hash = &drv_ev_state_hash;
	hf.cmp = &drv_ev_state_cmp;
	hf.alloc = &drv_ev_state_alloc;
	hf.free = &drv_ev_state_free;
	num_state_prealloc = 0;
	state_prealloc_first = NULL;

	/* On windows, since io is not initiated, the ERTS_CIO_POLL_MAX_FDS() will return 
	   1024 unconditionally at this point, but the hash table grows if needed, so that's 
	   not a problem */
	hash_init(ERTS_ALC_T_DRV_EV_STATE, &drv_ev_state_tab, "drv_ev_state_tab", 
		  ERTS_CIO_POLL_MAX_FDS(), hf);
    }
#endif
}

int
ERTS_CIO_EXPORT(erts_check_io_max_files)(void)
{
#ifdef  ERTS_SYS_CONTINOUS_FD_NUMBERS
    return max_fds;
#else
    return erts_poll_max_fds();
#endif
}

Uint
ERTS_CIO_EXPORT(erts_check_io_size)(void)
{
    Uint res;
    ErtsPollInfo pi;
    erts_smp_mtx_lock(&drv_ev_state_mtx);
    ERTS_CIO_POLL_INFO(pollset, &pi);
    res = pi.memory_size;
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    res += sizeof(ErtsDrvEventState)*drv_ev_state_len;
#else
    res += hash_table_sz(&drv_ev_state_tab);
    {
	HashInfo hi;
	hash_get_info(&hi, &drv_ev_state_tab);
	res += hi.objs * sizeof(ErtsDrvEventState);
    }
    res += num_state_prealloc * sizeof(ErtsDrvEventState);
#endif

    erts_smp_mtx_unlock(&drv_ev_state_mtx);
    return res;
}

Eterm
ERTS_CIO_EXPORT(erts_check_io_info)(void *proc)
{
    Process *p = (Process *) proc;
    Eterm tags[15], values[15], res;
    Uint sz, *szp, *hp, **hpp, memory_size;
    Sint i;
    ErtsPollInfo pi;
    
    erts_smp_mtx_lock(&drv_ev_state_mtx);
    ERTS_CIO_POLL_INFO(pollset, &pi);
    memory_size = pi.memory_size;
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    memory_size += sizeof(ErtsDrvEventState)*drv_ev_state_len;
#else
    memory_size += hash_table_sz(&drv_ev_state_tab);
    {
	HashInfo hi;
	hash_get_info(&hi, &drv_ev_state_tab);
	memory_size += hi.objs * sizeof(ErtsDrvEventState);
    }
    memory_size += num_state_prealloc * sizeof(ErtsDrvEventState);
#endif
    erts_smp_mtx_unlock(&drv_ev_state_mtx);

    hpp = NULL;
    szp = &sz;
    sz = 0;

 bld_it:
    i = 0;

    tags[i] = erts_bld_atom(hpp, szp, "name");
    values[i++] = erts_bld_atom(hpp, szp, "erts_poll");

    tags[i] = erts_bld_atom(hpp, szp, "primary");
    values[i++] = erts_bld_atom(hpp, szp, pi.primary);

    tags[i] = erts_bld_atom(hpp, szp, "fallback");
    values[i++] = erts_bld_atom(hpp, szp, pi.fallback ? pi.fallback : "false");

    tags[i] = erts_bld_atom(hpp, szp, "kernel_poll");
    values[i++] = erts_bld_atom(hpp, szp,
				pi.kernel_poll ? pi.kernel_poll : "false");

    tags[i] = erts_bld_atom(hpp, szp, "memory_size");
    values[i++] = erts_bld_uint(hpp, szp, memory_size);

    tags[i] = erts_bld_atom(hpp, szp, "total_poll_set_size");
    values[i++] = erts_bld_uint(hpp, szp, (Uint) pi.poll_set_size);

    if (pi.fallback) {
	tags[i] = erts_bld_atom(hpp, szp, "fallback_poll_set_size");
	values[i++] = erts_bld_uint(hpp, szp, (Uint) pi.fallback_poll_set_size);
    }

    tags[i] = erts_bld_atom(hpp, szp, "lazy_updates");
    values[i++] = pi.lazy_updates ? am_true : am_false;

    if (pi.lazy_updates) {
	tags[i] = erts_bld_atom(hpp, szp, "pending_updates");
	values[i++] = erts_bld_uint(hpp, szp, (Uint) pi.pending_updates);
    }

    tags[i] = erts_bld_atom(hpp, szp, "batch_updates");
    values[i++] = pi.batch_updates ? am_true : am_false;

    tags[i] = erts_bld_atom(hpp, szp, "concurrent_updates");
    values[i++] = pi.concurrent_updates ? am_true : am_false;

    tags[i] = erts_bld_atom(hpp, szp, "max_fds");
    values[i++] = erts_bld_uint(hpp, szp, (Uint) pi.max_fds);

#ifdef ERTS_POLL_COUNT_AVOIDED_WAKEUPS
    tags[i] = erts_bld_atom(hpp, szp, "no_avoided_wakeups");
    values[i++] = erts_bld_uint(hpp, szp, (Uint) pi.no_avoided_wakeups);

    tags[i] = erts_bld_atom(hpp, szp, "no_avoided_interrupts");
    values[i++] = erts_bld_uint(hpp, szp, (Uint) pi.no_avoided_interrupts);

    tags[i] = erts_bld_atom(hpp, szp, "no_interrupt_timed");
    values[i++] = erts_bld_uint(hpp, szp, (Uint) pi.no_interrupt_timed);
#endif

    res = erts_bld_2tup_list(hpp, szp, i, tags, values);

    if (!hpp) {
	hp = HAlloc(p, sz);
	hpp = &hp;
	szp = NULL;
	goto bld_it;
    }

    return res;
}

static ERTS_INLINE ErtsPollEvents
print_events(ErtsPollEvents ev)
{
    int first = 1;
    if(ev & ERTS_POLL_EV_IN) {
	ev &= ~ERTS_POLL_EV_IN;
	erts_printf("%s%s", first ? "" : "|", "IN");
	first = 0;
    }
    if(ev & ERTS_POLL_EV_OUT) {
	ev &= ~ERTS_POLL_EV_OUT;
	erts_printf("%s%s", first ? "" : "|", "OUT");
	first = 0;
    }
    /* The following should not appear... */
    if(ev & ERTS_POLL_EV_NVAL) {
	erts_printf("%s%s", first ? "" : "|", "NVAL");
	first = 0;
    }
    if(ev & ERTS_POLL_EV_ERR) {
	erts_printf("%s%s", first ? "" : "|", "ERR");
	first = 0;
    }
    if (ev)
	erts_printf("%s0x%b32x", first ? "" : "|", (Uint32) ev);
    return ev;
}

typedef struct {
    int used_fds;
    int num_errors;
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    int internal_fds;
    ErtsPollEvents *epep;
#endif
} IterDebugCounters;

static void doit_erts_check_io_debug(void *vstate, void *vcounters)
{
    ErtsDrvEventState *state = (ErtsDrvEventState *) vstate;
    IterDebugCounters *counters = (IterDebugCounters *) vcounters;
    ErtsPollEvents cio_events = state->events;
    ErtsSysFdType fd = state->fd;
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    int internal = 0;
    ErtsPollEvents ep_events = counters->epep[(int) fd];
#endif
    int err = 0;

#if defined(HAVE_FSTAT) && !defined(NO_FSTAT_ON_SYS_FD_TYPE)
    struct stat stat_buf;
#endif
    
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    if (state->events || ep_events) {
	if (ep_events & ERTS_POLL_EV_NVAL) {
	    ep_events &= ~ERTS_POLL_EV_NVAL;
	    internal = 1;
	    counters->internal_fds++;
	}
	else
	    counters->used_fds++;
#else
    if (state->events) {
        counters->used_fds++;
#endif
	
	erts_printf("fd=%d ", (int) fd);
	
#if defined(HAVE_FSTAT) && !defined(NO_FSTAT_ON_SYS_FD_TYPE)
	if (fstat((int) fd, &stat_buf) < 0)
	    erts_printf("type=unknown ");
	else {
	    erts_printf("type=");
#ifdef S_ISSOCK
	    if (S_ISSOCK(stat_buf.st_mode))
		erts_printf("sock ");
	    else
#endif
#ifdef S_ISFIFO
	    if (S_ISFIFO(stat_buf.st_mode))
		erts_printf("fifo ");
	    else
#endif
#ifdef S_ISCHR
	    if (S_ISCHR(stat_buf.st_mode))
		erts_printf("chr ");
	    else
#endif
#ifdef S_ISDIR
	    if (S_ISDIR(stat_buf.st_mode))
		erts_printf("dir ");
	    else
#endif
#ifdef S_ISBLK
	    if (S_ISBLK(stat_buf.st_mode))
		erts_printf("blk ");
	    else
#endif
#ifdef S_ISREG
	    if (S_ISREG(stat_buf.st_mode))
		erts_printf("reg ");
	    else
#endif
#ifdef S_ISLNK
	    if (S_ISLNK(stat_buf.st_mode))
		erts_printf("lnk ");
	    else
#endif
#ifdef S_ISDOOR
	    if (S_ISDOOR(stat_buf.st_mode))
		erts_printf("door ");
	    else
#endif
#ifdef S_ISWHT
	    if (S_ISWHT(stat_buf.st_mode))
		erts_printf("wht ");
	    else
#endif
#ifdef S_ISXATTR
	    if (S_ISXATTR(stat_buf.st_mode))
	        erts_printf("xattr ");
	    else
#endif
	        erts_printf("unknown ");
	}
#else
	erts_printf("type=unknown ");
#endif

	if (state->type == ERTS_EV_TYPE_DRV_SEL) {
	    erts_printf("driver_select ");
	    
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
	    if (internal) {
		erts_printf("internal ");
		err = 1;		    
	    }
	    
	    if (cio_events == ep_events) {
		erts_printf("ev=");
		if (print_events(cio_events) != 0)
		    err = 1;
	    }
	    else {
		err = 1;
		erts_printf("cio_ev=");
		print_events(cio_events);
		erts_printf(" ep_ev=");
		print_events(ep_events);
	    }
#else
	    if (print_events(cio_events) != 0)
		err = 1;
#endif
	    erts_printf(" ");
	    if (cio_events & ERTS_POLL_EV_IN) {
		Eterm id = state->driver.select->inport;
		if (is_nil(id)) {
		    erts_printf("inport=none inname=none indrv=none ");
		    err = 1;
		}
		else {
		    ErtsPortNames *pnp = erts_get_port_names(id);
		    erts_printf(" inport=%T inname=%s indrv=%s ",
				id,
				pnp->name ? pnp->name : "unknown",
				(pnp->driver_name
				 ? pnp->driver_name
				 : "unknown"));
		    erts_free_port_names(pnp);
		}
	    }
	    if (cio_events & ERTS_POLL_EV_OUT) {
		Eterm id = state->driver.select->outport;
		if (is_nil(id)) {
		    erts_printf("outport=none outname=none outdrv=none ");
		    err = 1;
		}
		else {
		    ErtsPortNames *pnp = erts_get_port_names(id);
		    erts_printf(" outport=%T outname=%s outdrv=%s ",
				id,
				pnp->name ? pnp->name : "unknown",
				(pnp->driver_name
				 ? pnp->driver_name
				 : "unknown"));
		    erts_free_port_names(pnp);
		}
	    }
	}
	else if (state->type == ERTS_EV_TYPE_DRV_EV) {
	    Eterm id;
	    erts_printf("driver_event ");
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
	    if (internal) {
		erts_printf("internal ");
		err = 1;		    
	    }
	    if (cio_events == ep_events) {
		erts_printf("ev=0x%b32x", (Uint32) cio_events);
	    }
	    else {
		err = 1;
		erts_printf("cio_ev=0x%b32x", (Uint32) cio_events);
		erts_printf(" ep_ev=0x%b32x", (Uint32) ep_events);
	    }
#else
	    erts_printf("ev=0x%b32x", (Uint32) cio_events);
#endif
	    id = state->driver.event->port;
	    if (is_nil(id)) {
		erts_printf(" port=none name=none drv=none ");
		err = 1;
	    }
	    else {
		ErtsPortNames *pnp = erts_get_port_names(id);
		erts_printf(" port=%T name=%s drv=%s ",
			    id,
			    pnp->name ? pnp->name : "unknown",
			    (pnp->driver_name
			     ? pnp->driver_name
			     : "unknown"));
		erts_free_port_names(pnp);
	    }
	}
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
	else if (internal) {
	    erts_printf("internal ");
	    if (cio_events) {
		err = 1;
		erts_printf("cio_ev=");
		print_events(cio_events);
	    }
	    if (ep_events) {
		erts_printf("ep_ev=");
		print_events(ep_events);
	    }
	}
#endif
	else {
	    err = 1;
	    erts_printf("control_type=%d ", state->type);
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
	    if (cio_events == ep_events) {
		erts_printf("ev=0x%b32x", (Uint32) cio_events);
	    }
	    else {
		erts_printf("cio_ev=0x%b32x", (Uint32) cio_events);
		erts_printf(" ep_ev=0x%b32x", (Uint32) ep_events);
	    }
#else
	    erts_printf("ev=0x%b32x", (Uint32) cio_events);
#endif
	}
	
	if (err) {
	    counters->num_errors++;
	    erts_printf(" ERROR");
	}
	erts_printf("\n");
    }
}
    
int
ERTS_CIO_EXPORT(erts_check_io_debug)(void)
{
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    int fd;
#endif
    IterDebugCounters counters;
    ErtsDrvEventState null_des;

    null_des.driver.select = NULL;
    null_des.events = 0;
    null_des.flags = 0;
    null_des.type = ERTS_EV_TYPE_NONE;

    erts_smp_mtx_lock(&drv_ev_state_mtx);

    erts_printf("--- fds in pollset --------------------------------------\n");

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    counters.epep = erts_alloc(ERTS_ALC_T_TMP, sizeof(ErtsPollEvents)*max_fds);
    ERTS_POLL_EXPORT(erts_poll_get_selected_events)(pollset, counters.epep, max_fds);
    counters.internal_fds = 0;
#endif
    counters.used_fds = 0;
    counters.num_errors = 0;

#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    for (fd = 0; fd < max_fds; fd++) {
	ErtsDrvEventState *desp = ((fd < drv_ev_state_len)
				   ? &drv_ev_state[fd]
				   : &null_des);
	null_des.fd = fd;
	doit_erts_check_io_debug((void *) desp, (void *) &counters);
    }
#else
    hash_foreach(&drv_ev_state_tab, &doit_erts_check_io_debug, (void *) &counters);
#endif
    erts_printf("\n");
    erts_printf("used fds=%d\n", counters.used_fds);
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    erts_printf("internal fds=%d\n", counters.internal_fds);
#endif
    erts_printf("---------------------------------------------------------\n");
    fflush(stdout);
#ifdef ERTS_SYS_CONTINOUS_FD_NUMBERS
    erts_free(ERTS_ALC_T_TMP, (void *) counters.epep);
#endif
    erts_smp_mtx_unlock(&drv_ev_state_mtx);
    return counters.num_errors;
}
