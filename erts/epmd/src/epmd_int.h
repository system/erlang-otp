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
 * This file is for internal use within epmd.
 */

/* This file don't depend on "sys.h" so we have to do some target
   definitions ourselves */

#ifdef __WIN32__
#define NO_SYSLOG
#define NO_SYSCONF
#define NO_DAEMON
#endif

#ifdef VXWORKS
#define NO_SYSLOG
#define NO_SYSCONF
#define NO_DAEMON
#define NO_FCNTL
#define DONT_USE_MAIN
#endif

/* ************************************************************************ */
/* Standard includes                                                        */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __WIN32__
#  include <winsock2.h>
#  include <windows.h>
#  include <process.h>
#endif

#include <sys/types.h>
#include <fcntl.h>

#ifdef VXWORKS
#  include <sys/times.h>
#  include <time.h>
#  include <selectLib.h>
#  include <sysLib.h>
#  include <sockLib.h>
#  include <ioLib.h>
#  include <taskLib.h>
#  include <rpc/rpc.h>
#else /* ! VXWORKS */
#ifndef __WIN32__
#  include <sys/time.h>
#endif
#endif /* ! VXWORKS */


#ifndef __WIN32__
#  include <netinet/in.h>
#  include <sys/socket.h>
#  include <sys/stat.h>

#  ifdef DEF_INADDR_LOOPBACK_IN_RPC_TYPES_H
#    include <rpc/types.h>
#  endif

#  include <arpa/inet.h>
#  include <netinet/tcp.h>
#endif /* ! WIN32 */


#include <ctype.h>
#include <errno.h>
#include <signal.h>

#ifndef NO_SYSLOG
#  include <syslog.h>
#endif

#ifdef SYS_SELECT_H
#  include <sys/select.h>
#endif

#ifdef HAVE_UNISTD_H
#  include <unistd.h>
#endif

#if defined(__STDC__) || defined(_MSC_VER)
#  include <stdarg.h>
#else
#  include <varargs.h>
#  define const
#endif

/* ************************************************************************ */
/* Replace some functions by others by making the function name a macro */

#ifdef __WIN32__
#  define close(s) closesocket((s))
#  define write(a,b,c) send((a),(b),(c),0)
#  define read(a,b,c) recv((a),(char *)(b),(c),0)
#  define sleep(s) Sleep((s) * 1000)
#  define ioctl(s,r,o) ioctlsocket((s),(r),(o))
#endif /* WIN32 */

#ifdef VXWORKS
#define sleep(n) taskDelay((n) * sysClkRateGet())
#endif /* VXWORKS */

#ifdef USE_BCOPY
#  define memcpy(a, b, c) bcopy((b), (a), (c))
#  define memcmp(a, b, c) bcmp((a), (b), (c))
#  define memzero(buf, len) bzero((buf), (len))
#else
#  define memzero(buf, len) memset((buf), '\0', (len))
#endif

/* ************************************************************************ */
/* Try to find replacement values for undefined system parameters           */

#if defined(__WIN32__) && !defined(EADDRINUSE)
#  define EADDRINUSE WSAEADDRINUSE
#endif

#ifndef SOMAXCONN
#  define SOMAXCONN 5
#endif

/* How to get max no of file descriptors? We used to use NOFILE from
   <sys/param.h>, but that tends to have little relation to reality.
   Best is to use sysconf() (POSIX), but we'll just punt if that isn't
   available (noone wants more than 64 Erlang systems on a host, right?:-) */
#define MAX_FILES 64		/* if sysconf() isn't available, or fails */

/* ************************************************************************ */
/* Macros that let us use IPv6                                              */

#if defined(HAVE_IN6) && defined(AF_INET6) && defined(EPMD6)

#define SOCKADDR_IN sockaddr_in6
#define FAMILY      AF_INET6

#define SET_ADDR_LOOPBACK(addr, af, port) do { \
    static u_int32_t __addr[4] = IN6ADDR_LOOPBACK_INIT; \
    memset((char*)&(addr), 0, sizeof(addr)); \
    (addr).sin6_family = (af); \
    (addr).sin6_flowinfo = 0; \
    (addr).sin6_addr.s6_addr32[0] = __addr[0]; \
    (addr).sin6_addr.s6_addr32[1] = __addr[1]; \
    (addr).sin6_addr.s6_addr32[2] = __addr[2]; \
    (addr).sin6_addr.s6_addr32[3] = __addr[3]; \
    (addr).sin6_port = htons(port); \
 } while(0)

#define SET_ADDR_ANY(addr, af, port) do { \
    static u_int32_t __addr[4] = IN6ADDR_ANY_INIT; \
    memset((char*)&(addr), 0, sizeof(addr)); \
    (addr).sin6_family = (af); \
    (addr).sin6_flowinfo = 0; \
    (addr).sin6_addr.s6_addr32[0] = __addr[0]; \
    (addr).sin6_addr.s6_addr32[1] = __addr[1]; \
    (addr).sin6_addr.s6_addr32[2] = __addr[2]; \
    (addr).sin6_addr.s6_addr32[3] = __addr[3]; \
    (addr).sin6_port = htons(port); \
 } while(0)

#else /* Not IP v6 */

#define SOCKADDR_IN sockaddr_in
#define FAMILY      AF_INET

#define SET_ADDR_LOOPBACK(addr, af, port) do { \
    memset((char*)&(addr), 0, sizeof(addr)); \
    (addr).sin_family = (af); \
    (addr).sin_addr.s_addr = htonl(INADDR_LOOPBACK); \
    (addr).sin_port = htons(port); \
 } while(0)

#define SET_ADDR_ANY(addr, af, port) do { \
    memset((char*)&(addr), 0, sizeof(addr)); \
    (addr).sin_family = (af); \
    (addr).sin_addr.s_addr = htonl(INADDR_ANY); \
    (addr).sin_port = htons(port); \
 } while(0)

#endif /* Not IP v6 */

/* ************************************************************************ */
/* Our own definitions                                                      */

#define FALSE 0
#define TRUE 1

/* If no activity we let select() return every IDLE_TIMEOUT second
   A file descriptor that are idle for CLOSE_TIMEOUT seconds and
   isn't a ALIVE socket is probably hanging and we close it */

#define IDLE_TIMEOUT 5
#define CLOSE_TIMEOUT 60

/* We save the name of nodes that are unregistered. If a new
   node register the name we want to increment the "creation",
   a constant 1..3. But we put an limit to this saving to keep
   the lookup fast and not to leak memory. */

#define MAX_UNREG_COUNT 1000
#define DEBUG_MAX_UNREG_COUNT 5

/* Maximum length of a node name == atom name */
#define MAXSYMLEN 255

#define INBUF_SIZE 1024
#define OUTBUF_SIZE 1024

#define get_int16(s) ((((unsigned char*)  (s))[0] << 8) | \
                      (((unsigned char*)  (s))[1]))

#define put_int16(i, s) {((unsigned char*)(s))[0] = ((i) >> 8) & 0xff; \
                        ((unsigned char*)(s))[1] = (i)         & 0xff;}

/* ************************************************************************ */
/* Prototypes                                                               */

#if ((defined(__STDC__) || defined(_MSC_VER) || defined(SABER)) && !defined(NO_PROTOTYPE)) || defined(__cplusplus) || defined(USE_PROTOTYPE)
#  define _USING_PROTOTYPES_ 1
#  define _ANSI_ARGS_(x)	x
#  define CONST const
#  define EXTERN
#else
#  define _ANSI_ARGS_(x)	()
#  define CONST
#  define EXTERN extern
#endif

/* Stuctures used by server */

typedef struct {
  int fd;			/* File descriptor */
  unsigned open:1;		/* TRUE if open */
  unsigned keep:1;		/* Don't close when sent reply */
  unsigned got;			/* # of bytes we have got */
  unsigned want;		/* Number of bytes we want */
  char *buf;			/* The remaining buffer */

  time_t mod_time;		/* Last activity on this socket */
} Connection;

struct enode {
  struct enode *next;
  int fd;			/* The socket in use */
  unsigned short port;		/* Port number of Erlang node */
  char symname[MAXSYMLEN+1];	/* Name of the Erlang node */
  short creation;		/* Started as a random number 1..3 */
  char nodetype;                /* 77 = normal erlang node 72 = hidden (c-node */
  char protocol;                /* 0 = tcp/ipv4 */
  unsigned short highvsn;                /* 0 = OTP-R3 erts-4.6.x, 1 = OTP-R4 erts-4.7.x*/
  unsigned short lowvsn;
  char extra[MAXSYMLEN+1];
};

typedef struct enode Node;

typedef struct {
  Node *reg;
  Node *unreg;
  Node *unreg_tail;
  int unreg_count;
} Nodes;


/* This is the structure with all variables needed to pass on
   to all functions. This makes this program reentrant */

typedef struct {
  int port;
  int debug;
  int silent; 
  int is_daemon;
  unsigned packet_timeout;
  unsigned delay_accept;
  unsigned delay_write;
  int max_conn;
  char *progname;
  Connection *conn;
  Nodes nodes;
  fd_set orig_read_mask;
  int listenfd;
  char **argv;
} EpmdVars;

EXTERN void dbg_printf     _ANSI_ARGS_((EpmdVars*,int,const char*,...));
EXTERN void dbg_tty_printf _ANSI_ARGS_((EpmdVars*,int,const char*,...));
EXTERN void dbg_perror     _ANSI_ARGS_((EpmdVars*,const char*,...));
EXTERN void kill_epmd _ANSI_ARGS_((EpmdVars*));
EXTERN void epmd_call _ANSI_ARGS_((EpmdVars*,int));
EXTERN void run _ANSI_ARGS_((EpmdVars*));
EXTERN void epmd_cleanup_exit _ANSI_ARGS_((EpmdVars*, int));
EXTERN int epmd_conn_close _ANSI_ARGS_((EpmdVars*,Connection*));

#ifdef DONT_USE_MAIN
EXTERN int  start_epmd _ANSI_ARGS_((char *,char *,char *,char *,char *,char *,char *,char *,char *,char *));
EXTERN int  epmd _ANSI_ARGS_((int,char **));
EXTERN int  epmd_dbg _ANSI_ARGS_((int,int));
#endif

