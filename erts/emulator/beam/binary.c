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

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include "sys.h"
#include "erl_vm.h"
#include "global.h"
#include "erl_process.h"
#include "error.h"
#include "bif.h"
#include "big.h"
#include "erl_binary.h"

/*
 * Create a brand new binary from scratch.
 */

Eterm
new_binary(Process *p, byte *buf, int len)
{
    ProcBin* pb;
    Binary* bptr;

    if (len <= ERL_ONHEAP_BIN_LIMIT) {
	ErlHeapBin* hb = (ErlHeapBin *) HAlloc(p, heap_bin_size(len));
	hb->thing_word = header_heap_bin(len);
	hb->size = len;
	if (buf != NULL) {
	    sys_memcpy(hb->data, buf, len);
	}
	return make_binary(hb);
    }

    /*
     * Allocate the binary struct itself.
     */
    bptr = (Binary *) safe_alloc_from(61, len+sizeof(Binary));
    bptr->flags = 0;
    bptr->orig_size = len;
    bptr->refc = 1;
    if (buf != NULL) {
	sys_memcpy(bptr->orig_bytes, buf, len);
    }

    /*
     * Now allocate the ProcBin on the heap.
     */
    pb = (ProcBin *) HAlloc(p, PROC_BIN_SIZE);
    pb->thing_word = HEADER_PROC_BIN;
    pb->size = len;
    pb->next = p->off_heap.mso;
    p->off_heap.mso = pb;
    pb->val = bptr;
    pb->bytes = bptr->orig_bytes;

    /*
     * Miscellanous updates. Return the tagged binary.
     */
    tot_bin_allocated += len;
    p->off_heap.overhead += pb->size / BINARY_OVERHEAD_FACTOR / sizeof(Eterm);
    return make_binary(pb);
}

/* Like new_binary, but uses ArithAlloc. */
/* Silly name. Come up with something better. */
Eterm new_binary_arith(Process *p, byte *buf, int len)
{
    ProcBin* pb;
    Binary* bptr;

    if (len <= ERL_ONHEAP_BIN_LIMIT) {
	ErlHeapBin* hb = (ErlHeapBin *) ArithAlloc(p, heap_bin_size(len));
	hb->thing_word = header_heap_bin(len);
	hb->size = len;
	if (buf != NULL) {
	    sys_memcpy(hb->data, buf, len);
	}
	return make_binary(hb);
    }

    /*
     * Allocate the binary struct itself.
     */
    bptr = (Binary *) safe_alloc_from(61, len+sizeof(Binary));
    bptr->flags = 0;
    bptr->orig_size = len;
    bptr->refc = 1;
    if (buf != NULL) {
	sys_memcpy(bptr->orig_bytes, buf, len);
    }

    /*
     * Now allocate the ProcBin on the heap.
     */
    pb = (ProcBin *) ArithAlloc(p, PROC_BIN_SIZE);
    pb->thing_word = HEADER_PROC_BIN;
    pb->size = len;
    pb->next = p->off_heap.mso;
    p->off_heap.mso = pb;
    pb->val = bptr;
    pb->bytes = bptr->orig_bytes;

    /*
     * Miscellanous updates. Return the tagged binary.
     */
    tot_bin_allocated += len;
    p->off_heap.overhead += pb->size / BINARY_OVERHEAD_FACTOR / sizeof(Eterm);
    return make_binary(pb);
}


Eterm
erts_realloc_binary(Eterm bin, size_t size)
{
    Eterm* bval = binary_val(bin);

    if (thing_subtag(*bval) == HEAP_BINARY_SUBTAG) {
	binary_size(bin) = size;
    } else {			/* REFC */
	ProcBin* pb = (ProcBin *) bval;
	Binary* newbin = sys_realloc(pb->val, sizeof(Binary) + size);
	tot_bin_allocated += (size - newbin->orig_size);
	newbin->orig_size = size;
	pb->val = newbin;
	pb->size = size;
	pb->bytes = newbin->orig_bytes;
	bin = make_binary(pb);
    }
    return bin;
}

BIF_RETTYPE binary_to_list_1(BIF_ALIST_1)
BIF_ADECL_1
{
    Uint size;
    Eterm previous;
    Eterm* hp;
    byte* bufp;

    if (is_not_binary(BIF_ARG_1)) {
	BIF_ERROR(BIF_P, BADARG);
    }

    size = binary_size(BIF_ARG_1);
    hp = HAlloc(BIF_P, 2 * size);
    GET_BINARY_BYTES(BIF_ARG_1, bufp);

    previous = NIL;
    while (size) {
	previous = CONS(hp, make_small(bufp[--size]), previous);
	hp += 2;
    }
    BIF_RET(previous);
}

BIF_RETTYPE binary_to_list_3(BIF_ALIST_3)
BIF_ADECL_3
{
    Eterm previous;
    byte* bytes;
    int size;
    Uint i;
    Uint start;
    Uint stop;
    Eterm* hp;

    if (is_not_binary(BIF_ARG_1)) {
	goto error;
    }
    if (!term_to_Uint(BIF_ARG_2, &start) || !term_to_Uint(BIF_ARG_3, &stop)) {
	goto error;
    }
    size = binary_size(BIF_ARG_1);
    GET_BINARY_BYTES(BIF_ARG_1, bytes);
    if (start < 1 || start > size || stop < 1 || stop > size || stop < start) {
	goto error;
    }

    i = stop-start+1;
    hp = HAlloc(BIF_P, 2*i);
    previous = NIL;
    bytes += stop;
    while (i-- > 0) {
	previous = CONS(hp, make_small(*--bytes), previous);
	hp += 2;
    }
    BIF_RET(previous);

 error:
    BIF_ERROR(BIF_P, BADARG);
}


/* Turn a possibly deep list of ints (and binaries) into */
/* One large binary object                               */

BIF_RETTYPE list_to_binary_1(BIF_ALIST_1)
BIF_ADECL_1
{
    Eterm bin;
    int j, i;
    byte* bytes;

    if (is_nil(BIF_ARG_1)) {
	BIF_RET(new_binary(BIF_P,(byte*)"",0));
    }
    if (is_not_list(BIF_ARG_1)) {
    error:
	BIF_ERROR(BIF_P, BADARG);
    }
    if ((i = io_list_len(BIF_ARG_1)) < 0) {
	goto error;
    }
    j = 0;
    bin = new_binary(BIF_P, (byte *)NULL, i);
    GET_BINARY_BYTES(bin, bytes);
    if (io_list_to_buf(BIF_ARG_1, (char*) bytes, &j, i+1) != 0) {
	goto error;
    }
    BIF_RET(bin);
}


BIF_RETTYPE concat_binary_1(BIF_ALIST_1)
BIF_ADECL_1
{
    return list_to_binary_1(BIF_ALIST_1);  /* Not meaningful any longer */
}


BIF_RETTYPE split_binary_2(BIF_ALIST_2)
BIF_ADECL_2
{
    Uint pos;
    ErlSubBin* sb1;
    ErlSubBin* sb2;
    size_t orig_size;
    Eterm orig;
    Uint offset;
    Eterm* hp;

    if (is_not_binary(BIF_ARG_1)) {
    error:
	BIF_ERROR(BIF_P, BADARG);
    }
    if (!term_to_Uint(BIF_ARG_2, &pos)) {
	goto error;
    }
    if ((orig_size = binary_size(BIF_ARG_1)) < pos) {
	goto error;
    }
    hp = HAlloc(BIF_P, 2*ERL_SUB_BIN_SIZE+3);
    GET_REAL_BIN(BIF_ARG_1, orig, offset);
    sb1 = (ErlSubBin *) hp;
    sb1->thing_word = HEADER_SUB_BIN;
    sb1->size = pos;
    sb1->offs = offset;
    sb1->orig = orig;
    hp += ERL_SUB_BIN_SIZE;

    sb2 = (ErlSubBin *) hp;
    sb2->thing_word = HEADER_SUB_BIN;
    sb2->size = orig_size - pos;
    sb2->offs = offset + pos;
    sb2->orig = orig;
    hp += ERL_SUB_BIN_SIZE;

    return TUPLE2(hp, make_binary(sb1), make_binary(sb2));
}

void
erts_cleanup_mso(ProcBin* pb)
{
    while (pb != NULL) {
	ProcBin* next = pb->next;
	ASSERT(pb->val->refc > 0);
	pb->val->refc--;
	if (pb->val->refc == 0) {
	    if (pb->val->flags & BIN_FLAG_MATCH_PROG) {
		erts_match_set_free(pb->val);
	    } else {
		tot_bin_allocated -= pb->val->orig_size;
		sys_free((char*)pb->val);
	    }
	}
	pb = next;
    }
}