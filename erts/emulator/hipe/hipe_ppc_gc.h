/* $Id$
 * Stack walking helpers for native stack GC procedures.
 */
#ifndef HIPE_PPC_GC_H
#define HIPE_PPC_GC_H

#include "hipe_ppc_asm.h"	/* for NR_ARG_REGS */

struct nstack_walk_state {
    const struct sdesc *sdesc0;	/* .sdesc0 must be a pointer rvalue */
};

static inline int nstack_walk_init_check(const Process *p)
{
    return p->hipe.nra ? 1 : 0;
}

static inline Eterm *nstack_walk_nsp_begin(const Process *p)
{
    unsigned int nstkarity = p->hipe.narity - NR_ARG_REGS;
    if( (int)nstkarity < 0 )
	nstkarity = 0;
    return p->hipe.nsp + nstkarity;
}

static inline const struct sdesc*
nstack_walk_init_sdesc(const Process *p, struct nstack_walk_state *state)
{
    const struct sdesc *sdesc = hipe_find_sdesc((unsigned long)p->hipe.nra);
    state->sdesc0 = sdesc;
    return sdesc;
}

static inline void nstack_walk_update_trap(Process *p, const struct sdesc *sdesc0)
{
    Eterm *nsp = p->hipe.nsp;
    p->hipe.nsp = nstack_walk_nsp_begin(p);
    hipe_update_stack_trap(p, sdesc0);
    p->hipe.nsp = nsp;
}

static inline Eterm *nstack_walk_nsp_end(const Process *p)
{
    return p->hipe.nstend - 1;
}

static inline void nstack_walk_kill_trap(Process *p, Eterm *nsp_end)
{
    /* remove gray/white boundary trap */
    if( (unsigned long)p->hipe.nra == (unsigned long)nbif_stack_trap_ra ) {
	p->hipe.nra = p->hipe.ngra;
    } else {
	for(;;) {
	    --nsp_end;
	    if( nsp_end[0] == (unsigned long)nbif_stack_trap_ra ) {
		nsp_end[0] = (unsigned long)p->hipe.ngra;
		break;
	    }
	}
    }
}

static inline int nstack_walk_gray_passed_black(const Eterm *gray, const Eterm *black)
{
    return gray > black;
}

static inline int nstack_walk_nsp_reached_end(const Eterm *nsp, const Eterm *nsp_end)
{
    return nsp >= nsp_end;
}

static inline unsigned int nstack_walk_frame_size(const struct sdesc *sdesc)
{
    return sdesc_fsize(sdesc) + 1 + sdesc_arity(sdesc);
}

static inline Eterm *nstack_walk_frame_index(Eterm *nsp, unsigned int i)
{
    return &nsp[i];
}

static inline unsigned long
nstack_walk_frame_ra(const Eterm *nsp, const struct sdesc *sdesc)
{
    return nsp[sdesc_fsize(sdesc)];
}

static inline Eterm *nstack_walk_next_frame(Eterm *nsp, unsigned int sdesc_size)
{
    return nsp + sdesc_size;
}

#endif /* HIPE_PPC_GC_H */