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

#ifndef __ERL_BITS_H__
#define __ERL_BITS_H__

/*
 * This structure represents a binary to be matched.
 */

typedef struct erl_bin_match_buffer {
    Eterm orig;			/* Original binary term. */
    byte* base;			/* Current position in binary. */
    Uint offset;		/* Offset in bits. */
    size_t size;		/* Size of binary in bits. */
} ErlBinMatchBuffer;

struct erl_bits_state {
    /*
     * Used for matching.
     */
    ErlBinMatchBuffer erts_mb_;	/* Current match buffer. */
    ErlBinMatchBuffer erts_save_mb_[MAX_REG]; /* Saved match buffers. */
    /*
     * Used for building binaries.
     */
    byte *byte_buf_;
    int byte_buf_len_;
    /*
     * Used for building binaries using the new instruction set.
     */
    byte* erts_current_bin_;	/* Pointer to beginning of current binary. */
    /*
     * Offset in bits into the current binary (new instruction set) or
     * buffer (old instruction set).
     */
    unsigned erts_bin_offset_;
    /*
     * The following variables are only used for building binaries
     * using the old instructions.
     */
    byte* erts_bin_buf_;
    unsigned erts_bin_buf_len_;
};

typedef struct erl_bin_match_struct{
  Eterm thing_word;
  ErlBinMatchBuffer mb; /* Present match buffer */
  Eterm save_offset[1]; /* Saved offsets */
} ErlBinMatchState;

#define ERL_BIN_MATCHSTATE_SIZE(_Max) ((sizeof(ErlBinMatchState) + (_Max-1)*sizeof(Eterm))/sizeof(Eterm)) 
#define HEADER_BIN_MATCHSTATE(_Max) _make_header(ERL_BIN_MATCHSTATE_SIZE(_Max)-1, _TAG_HEADER_BIN_MATCHSTATE)

#define make_matchstate(_Ms) make_boxed((Eterm*)(_Ms))  
#define ms_matchbuffer(_Ms) &(((ErlBinMatchState*)(_Ms - TAG_PRIMARY_BOXED))->mb)


#if defined(ERTS_SMP)
#define ERL_BITS_REENTRANT
#else
/* uncomment to test the reentrant API in the non-SMP runtime system */
/* #define ERL_BITS_REENTRANT */
#endif

#ifdef ERL_BITS_REENTRANT

/*
 * Reentrant API with the state passed as a parameter.
 * (Except when the current Process* already is a parameter.)
 */
#ifdef ERTS_SMP
/* the state resides in the current process' scheduler data */
#define ERL_BITS_DECLARE_STATEP			struct erl_bits_state *EBS
#define ERL_BITS_RELOAD_STATEP(P)		do{EBS = &(P)->scheduler_data->erl_bits_state;}while(0)
#define ERL_BITS_DEFINE_STATEP(P)		struct erl_bits_state *EBS = &(P)->scheduler_data->erl_bits_state
#else
/* reentrant API but with a hidden single global state, for testing only */
extern struct erl_bits_state ErlBitsState_;
#define ERL_BITS_DECLARE_STATEP			struct erl_bits_state *EBS = &ErlBitsState_
#define ERL_BITS_RELOAD_STATEP(P)		do{}while(0)
#define ERL_BITS_DEFINE_STATEP(P)		ERL_BITS_DECLARE_STATEP
#endif
#define ErlBitsState				(*EBS)

#define ERL_BITS_PROTO_0			struct erl_bits_state *EBS
#define ERL_BITS_PROTO_1(PARM1)			struct erl_bits_state *EBS, PARM1
#define ERL_BITS_PROTO_2(PARM1,PARM2)		struct erl_bits_state *EBS, PARM1, PARM2
#define ERL_BITS_PROTO_3(PARM1,PARM2,PARM3)	struct erl_bits_state *EBS, PARM1, PARM2, PARM3
#define ERL_BITS_ARGS_0				EBS
#define ERL_BITS_ARGS_1(ARG1)			EBS, ARG1
#define ERL_BITS_ARGS_2(ARG1,ARG2)		EBS, ARG1, ARG2
#define ERL_BITS_ARGS_3(ARG1,ARG2,ARG3)		EBS, ARG1, ARG2, ARG3

#else	/* ERL_BITS_REENTRANT */

/*
 * Non-reentrant API with a single global state.
 */
extern struct erl_bits_state ErlBitsState;
#define ERL_BITS_DECLARE_STATEP			/*empty*/
#define ERL_BITS_RELOAD_STATEP(P)		do{}while(0)
#define ERL_BITS_DEFINE_STATEP(P)		/*empty*/

#define ERL_BITS_PROTO_0			void
#define ERL_BITS_PROTO_1(PARM1)			PARM1
#define ERL_BITS_PROTO_2(PARM1,PARM2)		PARM1, PARM2
#define ERL_BITS_PROTO_3(PARM1,PARM2,PARM3)	PARM1, PARM2, PARM3
#define ERL_BITS_ARGS_0				/*empty*/
#define ERL_BITS_ARGS_1(ARG1)			ARG1
#define ERL_BITS_ARGS_2(ARG1,ARG2)		ARG1, ARG2
#define ERL_BITS_ARGS_3(ARG1,ARG2,ARG3)		ARG1, ARG2, ARG3

#endif	/* ERL_BITS_REENTRANT */

#define erts_mb			(ErlBitsState.erts_mb_)
#define erts_save_mb		(ErlBitsState.erts_save_mb_)
#define erts_bin_offset		(ErlBitsState.erts_bin_offset_)
#define erts_current_bin	(ErlBitsState.erts_current_bin_)
#define erts_bin_buf		(ErlBitsState.erts_bin_buf_)
#define erts_bin_buf_len	(ErlBitsState.erts_bin_buf_len_)

#define erts_InitMatchBuf(Src, Fail)				\
do {								\
    Eterm _Bin = (Src);						\
    if (!is_binary(_Bin)) {					\
	Fail;							\
    } else {							\
	Eterm _orig;						\
	Uint _offs;						\
								\
	GET_REAL_BIN(_Bin, _orig, _offs);			\
	erts_mb.orig = _orig;					\
	erts_mb.base = binary_bytes(_orig);			\
	erts_mb.offset = 8 * _offs;				\
	erts_mb.size = binary_size(_Bin) * 8 + erts_mb.offset;	\
    }								\
} while (0)

void erts_init_bits(void);	/* Initialization once. */
#ifdef ERTS_SMP
void erts_bits_init_state(ERL_BITS_PROTO_0);
void erts_bits_destroy_state(ERL_BITS_PROTO_0);
#endif


/*
 * NBYTES(x) returns the number of bytes needed to store x bits.
 */

#define NBYTES(x)  (((x) + 7) >> 3) 

/*
 * Return number of Eterm words needed for allocation with HAlloc(),
 * given a number of bytes.
 */
#define WSIZE(n) ((n + sizeof(Eterm) - 1) / sizeof(Eterm))

/*
 * Binary matching.
 */

int erts_bs_start_match(ERL_BITS_PROTO_1(Eterm Bin));
int erts_bs_skip_bits(ERL_BITS_PROTO_1(Uint num_bits));
int erts_bs_skip_bits_all(ERL_BITS_PROTO_0);
int erts_bs_test_tail(ERL_BITS_PROTO_1(Uint num_bits));
void erts_bs_save(ERL_BITS_PROTO_1(int index));
void erts_bs_restore(ERL_BITS_PROTO_1(int index));
Eterm erts_bs_get_integer(Process *p, Uint num_bits, unsigned flags);
Eterm erts_bs_get_binary(Process *p, Uint num_bits, unsigned flags);
Eterm erts_bs_get_float(Process *p, Uint num_bits, unsigned flags);
Eterm erts_bs_get_binary_all(Process *p);


Eterm erts_bs_start_match_2(Process *p, Eterm Bin, Uint Max);
void erts_bs_save_2(int index, ErlBinMatchState* ms);
void erts_bs_restore_2(int index, ErlBinMatchState* ms);
Eterm erts_bs_get_integer_2(Process *p, Uint num_bits, unsigned flags, ErlBinMatchBuffer* mb);
Eterm erts_bs_get_binary_2(Process *p, Uint num_bits, unsigned flags, ErlBinMatchBuffer* mb);
Eterm erts_bs_get_float_2(Process *p, Uint num_bits, unsigned flags, ErlBinMatchBuffer* mb);
Eterm erts_bs_get_binary_all_2(Process *p, ErlBinMatchBuffer* mb);
/*
 * Binary construction, new instruction set.
 */

int erts_new_bs_put_integer(ERL_BITS_PROTO_3(Eterm Integer, Uint num_bits, unsigned flags));
int erts_new_bs_put_binary(ERL_BITS_PROTO_2(Eterm Bin, Uint num_bits));
int erts_new_bs_put_binary_all(ERL_BITS_PROTO_1(Eterm Bin));
int erts_new_bs_put_float(Process *c_p, Eterm Float, Uint num_bits, int flags);
void erts_new_bs_put_string(ERL_BITS_PROTO_2(byte* iptr, Uint num_bytes));

/*
 * Binary construction, old instruction set.
 */

void erts_bs_init(ERL_BITS_PROTO_0);
Eterm erts_bs_final(Process* p);
Uint erts_bits_bufs_size(void);
int erts_bs_put_integer(ERL_BITS_PROTO_3(Eterm Integer, Uint num_bits, unsigned flags));
int erts_bs_put_binary(ERL_BITS_PROTO_2(Eterm Bin, Uint num_bits));
int erts_bs_put_binary_all(ERL_BITS_PROTO_1(Eterm Bin));
int erts_bs_put_float(Process *c_p, Eterm Float, Uint num_bits, int flags);
void erts_bs_put_string(ERL_BITS_PROTO_2(byte* iptr, Uint num_bytes));

/*
 * Flags for bs_get_* / bs_put_* / bs_init* instructions.
 */

#define BSF_ALIGNED 1		/* Field is guaranteed to be byte-aligned. */
#define BSF_LITTLE 2		/* Field is little-endian (otherwise big-endian). */
#define BSF_SIGNED 4		/* Field is signed (otherwise unsigned). */
#define BSF_EXACT 8		/* Size in bs_init is exact. */
#define BSF_NATIVE 16		/* Native endian. */

#endif /* __ERL_BITS_H__ */
