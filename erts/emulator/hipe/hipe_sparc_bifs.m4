/* $Id$
 * hipe_sparc_bifs.m4
 */

#include "hipe_sparc_asm.h"

/*
 * A C bif returns a single tagged Erlang value. To indicate an
 * exceptional condition, it puts an error code in p->freason
 * and returns zero (THE_NON_VALUE).
 *
 * If p->freason == TRAP, then the bif redirects its call to some
 * other function, given by p->fvalue and p->def_arg_reg[].
 * The other function has the same arity as the bif.
 *
 * A bif can suspend the call by setting p->freason == RESCHEDULE.
 * The caller should return immediately to the scheduler. When
 * the process is resumed, the caller should re-execute the call.
 *
 * These m4 macros expand to assembly code which
 * is further processed using the C pre-processor:
 * - Expansion of symbolic names for registers and PCB fields.
 * - Conditional assembly. Some BIFs need specialised code.
 *   Instead of special-casing them in all generated BIF lists,
 *   we use #ifndef wrappers to allow hand-written code to
 *   override that generated by the standard m4 macros.
 *   This is used for:
 *   - demonitor/1, exit/2, group_leader/2, link/1, monitor/2,
 *     port_command/2, send/2, unlink/2: can fail with RESCHEDULE
 *
 * XXX: TODO:
 * - Compiler should prefix argument list with P in all std bif calls;
 *   alternatively it could use %01..%o5 in normal calls, then we could
 *   just mov P, %o0.
 * - Replace "subcc ARG0,0,%g0; bz,pn" with "brz,pn ARG0"
 * - Can a BIF with arity 0 fail? beam_emu doesn't think so ...
 */

/*
 * standard_bif_interface_0(nbif_name, cbif_name)
 * standard_bif_interface_1(nbif_name, cbif_name)
 * standard_bif_interface_2(nbif_name, cbif_name)
 * standard_bif_interface_3(nbif_name, cbif_name)
 *
 * Generate native interface for a BIF with 0-3 arguments and
 * standard failure mode (may fail, but not with RESCHEDULE).
 */
define(standard_bif_interface_0,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and test for success/failure
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	subcc ARG0,0,%g0
	bz,pn %icc,nbif_0_simple_exception
	ld [P+P_NSP],NSP
	jmpl %l0+8,%g0
	nop
	.size $1,.-$1
	.type $1,#function
#endif')

define(standard_bif_interface_1,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG0,ARG1
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and test for success/failure
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	subcc ARG0,0,%g0
	bz,pn %icc,nbif_1_simple_exception
	ld [P+P_NSP],NSP
	jmpl %l0+8,%g0
	nop
	.size $1,.-$1
	.type $1,#function
#endif')

define(standard_bif_interface_2,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG1,ARG2
	mov ARG0,ARG1
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and test for success/failure
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	subcc ARG0,0,%g0
	bz,pn %icc,nbif_2_simple_exception
	ld [P+P_NSP],NSP
	jmpl %l0+8,%g0
	nop
	.size $1,.-$1
	.type $1,#function
#endif')

define(standard_bif_interface_3,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG2,ARG3
	mov ARG1,ARG2
	mov ARG0,ARG1
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and test for success/failure
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	subcc ARG0,0,%g0
	bz,pn %icc,nbif_3_simple_exception
	ld [P+P_NSP],NSP
	jmpl %l0+8,%g0
	nop
	.size $1,.-$1
	.type $1,#function
#endif')

/*
 * expensive_bif_interface_1(nbif_name, cbif_name)
 * expensive_bif_interface_2(nbif_name, cbif_name)
 *
 * Generate native interface for a BIF with 1-2 arguments and
 * an expensive failure mode (may fail with RESCHEDULE).
 */
define(expensive_bif_interface_1,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG0,ARG1
	mov P,ARG0

	!! Save actual parameters in case we must reschedule
	mov ARG1,TEMP1

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and test for success/failure
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	subcc ARG0,0,%g0
	bz,pn %icc,$1_failed
	ld [P+P_NSP],NSP
	jmpl %l0+8,%g0
	nop
$1_failed:
	set $1,TEMP
	b nbif_hairy_exception
	mov 1,ARG4
	.size $1,.-$1
	.type $1,#function
#endif')

define(expensive_bif_interface_2,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG1,ARG2
	mov ARG0,ARG1
	mov P,ARG0

	!! Save actual parameters in case we must reschedule
	mov ARG1,TEMP1
	mov ARG2,TEMP2

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and test for success/failure
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	subcc ARG0,0,%g0
	bz,pn %icc,$1_failed
	ld [P+P_NSP],NSP
	jmpl %l0+8,%g0
	nop
$1_failed:
	set $1,TEMP
	b nbif_hairy_exception
	mov 2,ARG4
	.size $1,.-$1
	.type $1,#function
#endif')

/*
 * gc_nofail_bif_interface_0(nbif_name, cbif_name)
 * gc_nofail_bif_interface_1(nbif_name, cbif_name)
 *
 * Generate native interface for a BIF with 0-1 arguments and
 * no failure mode.
 * The BIF may do gc, so the native code heap and stack limit registers
 * will be reloaded after the call.
 */
define(gc_nofail_bif_interface_0,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and return
	ld [P+P_HP_LIMIT],HP_LIMIT
	ld [P+P_NSP_LIMIT],NSP_LIMIT
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	jmpl %l0+8,%g0
	ld [P+P_NSP],NSP
	.size $1,.-$1
	.type $1,#function
#endif')

define(gc_nofail_bif_interface_1,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG0,ARG1
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and return
	ld [P+P_HP_LIMIT],HP_LIMIT
	ld [P+P_NSP_LIMIT],NSP_LIMIT
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	jmpl %l0+8,%g0
	ld [P+P_NSP],NSP
	.size $1,.-$1
	.type $1,#function
#endif')

/*
 * guard_bif_interface_0(nbif_name, cbif_name)
 * guard_bif_interface_1(nbif_name, cbif_name)
 * guard_bif_interface_2(nbif_name, cbif_name)
 *
 * Generate native interface for a guard BIF with 0-2 arguments.
 * (Like standard_bif_interface without the error check at return.)
 */
define(guard_bif_interface_0,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and return
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	jmpl %l0+8,%g0
	ld [P+P_NSP],NSP
	.size $1,.-$1
	.type $1,#function
#endif')

define(guard_bif_interface_1,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG0,ARG1
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and return
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	jmpl %l0+8,%g0
	ld [P+P_NSP],NSP
	.size $1,.-$1
	.type $1,#function
#endif')

define(guard_bif_interface_2,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Make room for P in the first arg
	mov ARG1,ARG2
	mov ARG0,ARG1
	mov P,ARG0

	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and return
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	jmpl %l0+8,%g0
	ld [P+P_NSP],NSP
	.size $1,.-$1
	.type $1,#function
#endif')

/*
 * bs_nofail_bif_interface(nbif_name, cbif_name)
 *
 * Generate native interface for a binary_syntax primop.
 * These differ from normal BIFs in that they don't throw
 * Erlang exceptions, and the compiler has already prefixed
 * the parameters with P (when needed).
 *
 * The primop may do gc, so the native code heap and stack limit registers
 * will be reloaded after the call.
 * [XXX: is this true? if they just alloc then the limits don't change]
 */
define(bs_nofail_bif_interface,
`
#ifndef HAVE_$1
#define HAVE_$1
	.section ".text"
	.align 4
	.global $1
$1:
	!! Save registers and call the C function
	st REDS,[P+P_FCALLS]
	st HP,[P+P_HP]
	mov RA,%l0
	call $2
	st NSP,[P+P_NSP]

	!! Restore registers and return
	ld [P+P_HP_LIMIT],HP_LIMIT
	ld [P+P_NSP_LIMIT],NSP_LIMIT
	ld [P+P_FCALLS],REDS
	ld [P+P_HP],HP
	jmpl %l0+8,%g0
	ld [P+P_NSP],NSP
	.size $1,.-$1
	.type $1,#function
#endif')

/*
 * BIFs with expensive failure modes.
 */
expensive_bif_interface_1(nbif_demonitor_1, demonitor_1)
expensive_bif_interface_2(nbif_exit_2, exit_2)
expensive_bif_interface_2(nbif_group_leader_2, group_leader_2)
expensive_bif_interface_1(nbif_link_1, link_1)
expensive_bif_interface_2(nbif_monitor_2, monitor_2)
expensive_bif_interface_2(nbif_port_command_2, port_command_2)
expensive_bif_interface_2(nbif_send_2, send_2)
expensive_bif_interface_1(nbif_unlink_1, unlink_1)

/*
 * Arithmetic operators called indirectly by the HiPE compiler.
 */
standard_bif_interface_2(nbif_add_2, erts_mixed_plus)
standard_bif_interface_2(nbif_sub_2, erts_mixed_minus)
standard_bif_interface_2(nbif_mul_2, erts_mixed_times)
standard_bif_interface_2(nbif_div_2, erts_mixed_div)
standard_bif_interface_2(nbif_intdiv_2, div_2)
standard_bif_interface_2(nbif_rem_2, rem_2)
standard_bif_interface_2(nbif_bsl_2, bsl_2)
standard_bif_interface_2(nbif_bsr_2, bsr_2)
standard_bif_interface_2(nbif_band_2, band_2)
standard_bif_interface_2(nbif_bor_2, bor_2)
standard_bif_interface_2(nbif_bxor_2, bxor_2)
standard_bif_interface_1(nbif_bnot_1, bnot_1)

/*
 * Internal primop BIFs.
 * Note: get_msg, select_msg, mbox_empty, next_msg, cmp, and op_exact_eqeq
 * are called directly from native code.
 */
gc_nofail_bif_interface_1(nbif_gc_1, hipe_gc)
gc_nofail_bif_interface_0(nbif_inc_stack_0, hipe_inc_nstack)
standard_bif_interface_1(nbif_set_timeout, hipe_set_timeout)
standard_bif_interface_0(nbif_clear_timeout, hipe_clear_timeout)

/*
 * Binary-syntax primops with _explicit_ P parameter.
 */
bs_nofail_bif_interface(nbif_bs_put_string, erts_bs_put_string)
bs_nofail_bif_interface(nbif_bs_init, erts_bs_init)
bs_nofail_bif_interface(nbif_bs_start_match, erts_bs_start_match)
bs_nofail_bif_interface(nbif_bs_put_binary_all, erts_bs_put_binary_all)
bs_nofail_bif_interface(nbif_bs_put_binary, erts_bs_put_binary)
bs_nofail_bif_interface(nbif_bs_put_float, erts_bs_put_float)
bs_nofail_bif_interface(nbif_bs_put_integer, erts_bs_put_integer)
bs_nofail_bif_interface(nbif_bs_skip_bits_all, erts_bs_skip_bits_all)
bs_nofail_bif_interface(nbif_bs_skip_bits, erts_bs_skip_bits)
bs_nofail_bif_interface(nbif_bs_get_integer, erts_bs_get_integer)
bs_nofail_bif_interface(nbif_bs_get_float, erts_bs_get_float)
bs_nofail_bif_interface(nbif_bs_get_binary, erts_bs_get_binary)
bs_nofail_bif_interface(nbif_bs_get_binary_all, erts_bs_get_binary_all)
bs_nofail_bif_interface(nbif_bs_test_tail, erts_bs_test_tail)
bs_nofail_bif_interface(nbif_bs_restore, erts_bs_restore)
bs_nofail_bif_interface(nbif_bs_save, erts_bs_save)
bs_nofail_bif_interface(nbif_bs_final, erts_bs_final)

/*
 * Standard BIFs.
 * BIF_LIST(ModuleAtom,FunctionAtom,Arity,CFun,Index)
 */
define(BIF_LIST,`standard_bif_interface_$3(nbif_$4, $4)')
include(`erl_bif_list.h')

/*
 * Guard BIFs.
 * GBIF_LIST(FunctionAtom,Arity,CFun)
 */
define(GBIF_LIST,`guard_bif_interface_$2(gbif_$3, $3)')
include(`hipe_gbif_list.h')