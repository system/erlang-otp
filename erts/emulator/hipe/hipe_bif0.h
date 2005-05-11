/* $Id$
 * hipe_bif0.h
 *
 * Compiler and linker support.
 */
#ifndef HIPE_BIF0_H
#define HIPE_BIF0_H

extern Eterm address_to_term(const void *address, Process *p);
extern Uint *hipe_bifs_find_pc_from_mfa(Eterm mfa);

/* shared with ggc.c -- NOT an official API */
extern Eterm *hipe_constants_start;
extern Eterm *hipe_constants_next;

extern void hipe_mfa_info_table_init(void);
extern void *hipe_get_remote_na(Eterm m, Eterm f, unsigned int a);
extern Eterm hipe_find_na_or_make_stub(Process*, Eterm, Eterm, Eterm);
#if defined(__powerpc__) || defined(__ppc__) || defined(__powerpc64__)
extern void *hipe_mfa_get_trampoline(Eterm m, Eterm f, unsigned int a);
extern void hipe_mfa_set_trampoline(Eterm m, Eterm f, unsigned int a, void *trampoline);
#endif

/* needed in beam_load.c */
void hipe_mfa_save_orig_beam_op(Eterm m, Eterm f, unsigned int a, Eterm *pc);

/* these are also needed in hipe_amd64.c */
extern void *term_to_address(Eterm);
extern int term_to_Sint32(Eterm, Sint *);

#endif /* HIPE_BIF0_H */
