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
 **
 *  Purpose:  Portprogram for supervision of memory usage.
 *
 *  Synopsis: memsup
 *
 *  PURPOSE OF THIS PROGRAM
 *
 *  This program supervises the memory status of the entire system, and
 *  sends status reports upon request from the Erlang system
 *
 *  SPAWNING FROM ERLANG
 *
 *  This program is started from Erlang as follows,
 *
 *      Port = open_port({spawn, 'memsup'}, [{packet,1}]) for UNIX and VxWorks
 *
 *  Erlang sends one of the request condes defined in memsup.h (which
 *  is input for the IG generation of memsup.hrl) and this program
 *  answers in one of two ways:
 *  * If the request is for simple memory data (which is used periodically
 *    for monitoring) the answer is simply sent in two packets, where 
 *    all numbers are divided by 256 (shifted right 8 steps) to avoid
 *    problems with HUGE memories.
 *  * If the request is for the system specific data, the answer is delivered
 *    in two packets per value, first a tag value, then the actual
 *    value. The values are delivered "as is", this interface is
 *    mainly for VxWorks.
 *
 *  SUNOS FAKING
 *
 *  When using SunOS 4, the memory report is faked. The total physical memory
 *  is always reported to be 256MB, and the used fraction to be 128MB.
 *
 *  STANDARD INPUT, OUTPUT AND ERROR
 *
 *  This program communicates with Erlang through the standard
 *  input and output file descriptors (0 and 1). These descriptors
 *  (and the standard error descriptor 2) must NOT be closed
 *  explicitely by this program at termination (in UNIX it is
 *  taken care of by the operating system itself; in VxWorks
 *  it is taken care of by the spawn driver part of the Emulator).
 *
 *  END OF FILE
 *
 *  If a read from a file descriptor returns zero (0), it means
 *  that there is no process at the other end of the connection
 *  having the connection open for writing (end-of-file).
 *
 *  COMPILING
 *
 *  When the target is VxWorks the identifier VXWORKS must be defined for
 *  the preprocessor (usually by a -D option).
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

#ifndef VXWORKS
#include <unistd.h>
#endif

#if defined __STDC__
#include <stdarg.h>
#else
#include <varargs.h>
#endif
#include <string.h>
#include <time.h>
#include <errno.h>
#ifdef VXWORKS
#include <vxWorks.h>
#include <ioLib.h>
#include <memLib.h>
#endif

/* commands */
#include "memsup.h"

#define CMD_SIZE      1
#define MAX_CMD_BUF   10
#define ERLIN_FD      0
#define ERLOUT_FD     1


/*  prototypes */

static void print_error(const char *,...);
#ifdef VXWORKS
extern int erl_mem_info_get(MEM_PART_STATS *);
#endif

#ifdef VXWORKS
#define MAIN memsup

static MEM_PART_STATS latest;
static unsigned long latest_system_total; /* does not fit in the struct */

#else
#define MAIN main
#endif

/*  static variables */

static char *program_name;

static void
send(unsigned long value)
{
    char buf[20];
    int left, bytes, res;
    
    sprintf(buf+1, "%lu", value);
    bytes = (char) strlen(buf+1); 
    buf[0] = bytes;		
    left = ++bytes;

    while (left > 0){
	res = write(ERLOUT_FD, buf+bytes-left, left);
	if (res <= 0){
	    perror("Error writing to pipe");
	    exit(1);
	}
	left -= res;
    }
}

static void
send_tag(int value){
    unsigned char buf[2];
    int res,left;

    buf[0] = 1U;
    buf[1] = (unsigned char) value;
    left = 2;
    while(left > 0)
	if((res = write(ERLOUT_FD, buf+left-2,left)) <= 0){
	    perror("Error writing to pipe");
	    exit(1);
	} else
	    left -= res;
}

#ifdef VXWORKS
static void load_statistics(void){
    if(memPartInfoGet(memSysPartId,&latest) != OK)
	memset(&latest,0,sizeof(latest));
    latest_system_total = latest.numBytesFree + latest.numBytesAlloc;
    erl_mem_info_get(&latest); /* if it fails, latest is untouched */
}
#endif

static void 
get_basic_mem(unsigned long *tot, unsigned long *used, int shiftleft){
#if defined(VXWORKS)
    load_statistics();
    *tot = (latest.numBytesFree + latest.numBytesAlloc) >> shiftleft;
    *used = latest.numBytesAlloc >> shiftleft;
#elif defined(_SC_AVPHYS_PAGES)	/* Does this exist on others than Solaris2? */
    unsigned long avPhys, phys, pgSz;
    
    phys = sysconf(_SC_PHYS_PAGES);
    avPhys = sysconf(_SC_AVPHYS_PAGES);
    pgSz = sysconf(_SC_PAGESIZE) >> shiftleft;
    *used = (phys - avPhys) * pgSz;
    *tot = phys * pgSz;
#else  /* SunOS4 */
    *used = (1<<27) >> shiftleft;	       	/* Fake! 128 MB used */
    *tot = (1<<28) >> shiftleft;		/* Fake! 256 MB total */
#endif
}    

/*
** The simple memory showing 
** sends data divided by 256 to avoid integer overflow on extreme
** large memory systems.
*/
static void
simple_show_mem(void){
    unsigned long tot, used;
    get_basic_mem(&tot,&used,8); /* Shift pagesize left by 8 before 
				    multiplying (or simply shift the
				    results on systems where 
				    "pagesize" has no meaning) */
    send(used);
    send(tot);
}

/*
** The system memory showing sends data as expected (in bytes)
** and also tags values as output may be different on different 
** OS:es. Actually I expect this protocol to be really useful
** only on non paged systems like VxWorks, OSE/Delta etc.
** The possibilities of 4GB+ memories on these
** systems are not counted for...
*/
static void 
extended_show_mem(void){
    unsigned long tot, used;
    get_basic_mem(&tot,&used,0); /* We don't care about extremely
				    large memories here, we 
				    report to erlang as 
				    bytes */
    send_tag(TOTAL_MEMORY);
    send(tot);
    send_tag(FREE_MEMORY);
    send(tot - used);
    send_tag(SYSTEM_TOTAL_MEMORY);
#ifdef VXWORKS
    send(latest_system_total);
    send_tag(LARGEST_FREE);
    send(latest.maxBlockSizeFree);
    send_tag(NUMBER_OF_FREE);
    send(latest.numBlocksFree);
#else
    send(tot);
#endif
    send_tag(SYSTEM_MEM_SHOW_END);
}    

static void
message_loop(int erlin_fd)
{
    char cmdLen, cmd;
    int res;
    
    while (1){
	/*
	 *  Wait for command from Erlang
	 */
	if ((res = read(erlin_fd, &cmdLen, 1)) < 0) {
	    print_error("Error reading from Erlang.");
	    return;
	}

	if (res == 1) {		/* Exactly one byte read ? */
	    if (cmdLen == 1){	/* Should be! */
		switch (read(erlin_fd, &cmd, 1)){
		case 1:	  
		    switch (cmd){
		    case MEM_SHOW:
			simple_show_mem();
			break;
		    case SYSTEM_MEM_SHOW:
			extended_show_mem();
			break;
		    default:	/* ignore all other messages */
			break;
		    }
		  break;
		  
		case 0:
		  print_error("Erlang has closed.");
		  return;

		default:
		  print_error("Error reading from Erlang.");
		  return;
		} /* switch() */
	    } else { /* cmdLen != 1 */
		print_error("Invalid command length (%d) received.", cmdLen);
		return;
	    }
	} else {		/* Erlang end closed */
	    print_error("Erlang has closed.");
	    return;
	}
    }
}

/*
 *  main
 */
int
MAIN(int argc, char **argv)
{
  program_name = argv[0];
  message_loop(ERLIN_FD);
  return 0;
}


/*
 *  print_error
 *
 */
static void
print_error(const char *format,...)
{
  va_list args;

  va_start(args, format);
  fprintf(stderr, "%s: ", program_name);
  vfprintf(stderr, format, args);
  va_end(args);
  fprintf(stderr, " \n");
}




