
/* pngconf.c - machine configurable file for libpng

   libpng 1.0 beta 4 - version 0.90
   For conditions of distribution and use, see copyright notice in png.h
   Copyright (c) 1995, 1996 Guy Eric Schalnat, Group 42, Inc.
   December 3, 1996
   */

/* Any machine specific code is near the front of this file, so if you
   are configuring libpng for a machine, you may want to read the section
   starting here down to where it starts to typedef png_color, png_text,
   and png_info */

#ifndef PNGCONF_H
#define PNGCONF_H

/* This is the size of the compression buffer, and thus the size of
   an IDAT chunk.  Make this whatever size you feel is best for your
   machine.  One of these will be allocated per png_struct.  When this
   is full, it writes the data to the disk, and does some other
   calculations.  Making this an extreamly small size will slow
   the library down, but you may want to experiment to determine
   where it becomes significant, if you are concerned with memory
   usage.  Note that zlib allocates at least 32Kb also.  For readers,
   this describes the size of the buffer available to read the data in.
   Unless this gets smaller then the size of a row (compressed),
   it should not make much difference how big this is.  */

#define PNG_ZBUF_SIZE 8192

/* If you are running on a machine where you cannot allocate more then
   64K of memory, uncomment this.  While libpng will not normally need
   that much memory in a chunk (unless you load up a very large file),
   zlib needs to know how big of a chunk it can use, and libpng thus
   makes sure to check any memory allocation to verify it will fit
   into memory.
#define PNG_MAX_ALLOC_64K
*/
#ifdef MAXSEG_64K
#define PNG_MAX_ALLOC_64K
#endif

/* This protects us against compilers which run on a windowing system
   and thus don't have or would rather us not use the stdio types:
   stdin, stdout, and stderr.  The only one currently used is stderr
   in png_error() and png_warning().  #defining PNG_NO_STDIO will
   prevent these from being compiled and used. */

/* #define PNG_NO_STDIO */

/* for FILE.  If you are not using standard io, you don't need this */
#ifndef PNG_NO_STDIO
#include <stdio.h>
#endif

/* This macro protects us against machines that don't have function
   prototypes (ie K&R style headers).  If your compiler does not handle
   function prototypes, define this macro.  I've always been able to use
   _NO_PROTO as the indicator, but you may need to drag the empty declaration
   out in front of here, or change the ifdef to suit your own needs. */
#ifndef PNGARG

#ifdef OF /* Zlib prototype munger */
#define PNGARG(arglist) OF(arglist)
#else

#ifdef _NO_PROTO
#define PNGARG(arglist) ()
#else
#define PNGARG(arglist) arglist
#endif /* _NO_PROTO */

#endif /* OF */

#endif /* PNGARG */

/* Try to determine if we are compiling on a Mac */
#if defined(__MWERKS__) ||defined(applec) ||defined(THINK_C) ||defined(__SC__)
#define MACOS
#endif

/* enough people need this for various reasons to include it here */
#if !defined(MACOS) && !defined(RISCOS)
#include <sys/types.h>
#endif

/* need the time information for reading tIME chunks */
#include <time.h>

/* This is an attempt to force a single setjmp behaviour on Linux */
#ifdef linux
#ifdef _BSD_SOURCE
#define _PNG_SAVE_BSD_SOURCE
#undef _BSD_SOURCE
#endif
#ifdef _SETJMP_H
error: png.h already includes setjmp.h
#endif
#endif /* linux */

/* include setjmp.h for error handling */
#include <setjmp.h>

#ifdef linux
#ifdef _PNG_SAVE_BSD_SOURCE
#define _BSD_SOURCE
#undef _PNG_SAVE_BSD_SOURCE
#endif
#endif /* linux */

#ifdef BSD
#include <strings.h>
#else
#include <string.h>
#endif

/* Other defines for things like memory and the like can go here.  These
   are the only files included in libpng, so if you need to change them,
   change them here.  They are only included if PNG_INTERNAL is defined. */
#ifdef PNG_INTERNAL
#include <stdlib.h>
#include <ctype.h>

/* Other defines specific to compilers can go here.  Try to keep
   them inside an appropriate ifdef/endif pair for portability */

#ifdef MACOS
#include <fp.h>
#else
#include <math.h>
#endif

/* For some reason, Borland C++ defines memcmp, etc. in mem.h, not
   stdlib.h like it should (I think).  Or perhaps this is a C++
   feature? */
#ifdef __TURBOC__
#include <mem.h>
#include "alloc.h"
#endif

#ifdef _MSC_VER
#include <malloc.h>
#endif

/* This controls how fine the dithering gets.  As this allocates
   a largish chunk of memory (32K), those who are not as concerned
   with dithering quality can decrease some or all of these. */
#define PNG_DITHER_RED_BITS 5
#define PNG_DITHER_GREEN_BITS 5
#define PNG_DITHER_BLUE_BITS 5

/* This controls how fine the gamma correction becomes when you
   are only interested in 8 bits anyway.  Increasing this value
   results in more memory being used, and more pow() functions
   being called to fill in the gamma tables.  Don't set this
   value less then 8, and even that may not work (I haven't tested
   it). */

#define PNG_MAX_GAMMA_8 11

#endif /* PNG_INTERNAL */

/* The following uses const char * instead of char * for error
   and warning message functions, so some compilers won't complain.
   If you want to use const, define PNG_USE_CONST here.  It is not
   normally defined to make configuration easier, as it is not a
   critical part of the code.
   */

#if defined(__STDC__) || defined(HAS_STDARG)
#define PNG_USE_CONST
#endif

#ifdef PNG_USE_CONST
#  define PNG_CONST const
#else
#  define PNG_CONST
#endif

/* The following defines give you the ability to remove code from the
   library that you will not be using.  I wish I could figure out how to
   automate this, but I can't do that without making it seriously hard
   on the users.  So if you are not using an ability, change the #define
   to and #undef, and that part of the library will not be compiled.  If
   your linker can't find a function, you may want to make sure the
   ability is defined here.  Some of these depend upon some others being
   defined.  I haven't figured out all the interactions here, so you may
   have to experiment awhile to get everything to compile.  If you are
   creating or using a shared library, you probably shouldn't touch this,
   as it will affect the size of the structures, and this will cause bad
   things to happen if the library and/or application ever change. */

/* Any transformations you will not be using can be undef'ed here */
#define PNG_PROGRESSIVE_READ_SUPPORTED
#define PNG_READ_INTERLACING_SUPPORTED
#define PNG_READ_EXPAND_SUPPORTED
#define PNG_READ_SHIFT_SUPPORTED
#define PNG_READ_PACK_SUPPORTED
#define PNG_READ_BGR_SUPPORTED
#define PNG_READ_SWAP_SUPPORTED
#define PNG_READ_INVERT_SUPPORTED
#define PNG_READ_DITHER_SUPPORTED
#define PNG_READ_BACKGROUND_SUPPORTED
#define PNG_READ_16_TO_8_SUPPORTED
#define PNG_READ_FILLER_SUPPORTED
#define PNG_READ_GAMMA_SUPPORTED
#define PNG_READ_GRAY_TO_RGB_SUPPORTED

#define PNG_WRITE_INTERLACING_SUPPORTED
#define PNG_WRITE_SHIFT_SUPPORTED
#define PNG_WRITE_PACK_SUPPORTED
#define PNG_WRITE_BGR_SUPPORTED
#define PNG_WRITE_SWAP_SUPPORTED
#define PNG_WRITE_INVERT_SUPPORTED
#define PNG_WRITE_FILLER_SUPPORTED
#define PNG_WRITE_FLUSH_SUPPORTED

/* These functions are turned off by default, as they will be phased out. */
#undef  PNG_USE_OWN_CRC
#undef  PNG_CORRECT_PALETTE_SUPPORTED

/* any chunks you are not interested in, you can undef here.  The
   ones that allocate memory may be expecially important (hIST,
   tEXt, zTXt, tRNS) Others will just save time and make png_info
   smaller.  OPT_PLTE only disables the optional palette in RGB
   and RGB Alpha images. */

#define PNG_READ_gAMA_SUPPORTED
#define PNG_READ_sBIT_SUPPORTED
#define PNG_READ_cHRM_SUPPORTED
#define PNG_READ_tRNS_SUPPORTED
#define PNG_READ_bKGD_SUPPORTED
#define PNG_READ_hIST_SUPPORTED
#define PNG_READ_pHYs_SUPPORTED
#define PNG_READ_oFFs_SUPPORTED
#define PNG_READ_tIME_SUPPORTED
#define PNG_READ_tEXt_SUPPORTED
#define PNG_READ_zTXt_SUPPORTED
#define PNG_READ_OPT_PLTE_SUPPORTED

#define PNG_WRITE_gAMA_SUPPORTED
#define PNG_WRITE_sBIT_SUPPORTED
#define PNG_WRITE_cHRM_SUPPORTED
#define PNG_WRITE_tRNS_SUPPORTED
#define PNG_WRITE_bKGD_SUPPORTED
#define PNG_WRITE_hIST_SUPPORTED
#define PNG_WRITE_pHYs_SUPPORTED
#define PNG_WRITE_oFFs_SUPPORTED
#define PNG_WRITE_tIME_SUPPORTED
#define PNG_WRITE_tEXt_SUPPORTED
#define PNG_WRITE_zTXt_SUPPORTED

/* Some typedefs to get us started.  These should be safe on most of the
   common platforms.  The typedefs should be at least as large as the
   numbers suggest (a png_uint_32 must be at least 32 bits long), but they
   don't have to be exactly that size. */

typedef unsigned long png_uint_32;
typedef long png_int_32;
typedef unsigned short png_uint_16;
typedef short png_int_16;
typedef unsigned char png_byte;

/* This is usually size_t.  It is typedef'ed just in case you need it to
   change (I'm not sure if you will or not, so I thought I'd be safe) */
typedef size_t png_size_t;

/* The following is needed for medium model support. It cannot be in the
   PNG_INTERNAL section. Needs modification for other compilers besides
   MSC. Model independent support declares all arrays that might be very
   large using the far keyword. The Zlib version used must also support
   model independent data. As of version Zlib .95, the necessary changes
   have been made in Zlib. The USE_FAR_KEYWORD define triggers other
   changes that are needed. Most of the far keyword changes are hidden
   inside typedefs with suffix "f". (Tim Wegner) */

/* Separate compiler dependencies (problem here is that zlib.h always
   defines FAR. (SJT) */
#ifdef __BORLANDC__
#if defined(__LARGE__) || defined(__HUGE__) || defined(__COMPACT__)
#define LDATA 1
#else
#define LDATA 0
#endif

#if !defined(__WIN32__) && !defined(__FLAT__)
#define PNG_MAX_MALLOC_64K
#if (LDATA != 1)
#ifndef FAR
#define FAR __far
#endif
#define USE_FAR_KEYWORD
#endif   /* LDATA != 1 */

/* Possibly useful for moving data out of default segment.
   Uncomment it if you want. Could also define FARDATA as
   const if your compiler supports it. (SJT)
#  define FARDATA FAR
*/
#endif  /* __WIN32__, __FLAT__ */

#endif   /* __BORLANDC__ */


/* Suggest testing for specific compiler first before testing for
   FAR.  The Watcom compiler defines both __MEDIUM__ and M_I86MM,
   making reliance oncertain keywords suspect. (SJT) */

/* MSC Medium model */
#if defined(FAR)
#  if defined(M_I86MM)
#     define USE_FAR_KEYWORD
#     define FARDATA FAR
#     include <dos.h>
#  endif
#endif

/* SJT: default case */
#ifndef FAR
#   define FAR
#endif

/* SJT: At this point FAR is always defined */

/* SJT: */
#ifndef FARDATA
#define FARDATA
#endif

/* Not used anymore (as of 0.88), but kept for compatability (for now). */
typedef unsigned char FAR png_bytef;

/* SJT: Add typedefs for pointers */
typedef void            FAR * png_voidp;
typedef png_byte        FAR * png_bytep;
typedef png_uint_32     FAR * png_uint_32p;
typedef png_int_32      FAR * png_int_32p;
typedef png_uint_16     FAR * png_uint_16p;
typedef png_int_16      FAR * png_int_16p;
typedef PNG_CONST char  FAR * png_const_charp;
typedef char            FAR * png_charp;

/*  SJT: Pointers to pointers; i.e. arrays */
typedef png_byte        FAR * FAR * png_bytepp;
typedef png_uint_32     FAR * FAR * png_uint_32pp;
typedef png_int_32      FAR * FAR * png_int_32pp;
typedef png_uint_16     FAR * FAR * png_uint_16pp;
typedef png_int_16      FAR * FAR * png_int_16pp;
typedef PNG_CONST char  FAR * FAR * png_const_charpp;
typedef char            FAR * FAR * png_charpp;


/* SJT: libpng typedefs for types in zlib. If Zlib changes
   or another compression library is used, then change these.
   Eliminates need to change all the source files.
*/

/* Compile with -DPNG_DLL for Windows DLL support */
#if defined(__WIN32__) && defined(PNG_DLL)
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  undef WIN32_LEAN_AND_MEAN
#  if defined(_MSC_VER)
#    define EXTERN(type) extern __declspec(dllexport) type
#  else
#    if defined(__BORLANDC__)
#	define EXTERN(type) extern type _export
#    endif
#  endif
#endif

#if !defined(EXTERN)
#define EXTERN(type)		extern type
#endif

#if defined(PNG_INTERNAL)

#include "zlib.h"
typedef charf *         png_zcharp;
typedef charf * FAR *   png_zcharpp;
typedef z_stream FAR *  png_zstreamp; 

#endif

/* User may want to use these so not in PNG_INTERNAL. Any library functions
   that are passed far data must be model independent. */

#if defined(USE_FAR_KEYWORD)  /* memory model independent fns */
/* use this to make far-to-near assignments */
#   define CHECK   1
#   define NOCHECK 0
#   define CVT_PTR(ptr) (far_to_near(png_ptr,ptr,CHECK))
#   define CVT_PTR_NOCHECK(ptr) (far_to_near(png_ptr,ptr,NOCHECK))
#   define png_strcpy _fstrcpy
#   define png_strcat _fstrcat
#   define png_strlen _fstrlen
#   define png_strcmp _fstrcmp
#   define png_memcmp _fmemcmp      /* SJT: added */
#   define png_memcpy _fmemcpy
#   define png_memset _fmemset
#else /* use the usual functions */
#   define CVT_PTR(ptr)         (ptr)
#   define CVT_PTR_NOCHECK(ptr) (ptr)
#   define png_strcpy strcpy
#   define png_strcat strcat
#   define png_strlen strlen
#   define png_strcmp strcmp
#   define png_memcmp memcmp     /* SJT: added */
#   define png_memcpy memcpy
#   define png_memset memset
#endif
/* End of memory model independent support */

#endif /* PNGCONF_H */
