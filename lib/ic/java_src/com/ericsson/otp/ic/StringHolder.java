/*<copyright>
 * <year>1999-2007</year>
 * <holder>Ericsson AB, All Rights Reserved</holder>
 *</copyright>
 *<legalnotice>
 * The contents of this file are subject to the Erlang Public License,
 * Version 1.1, (the "License"); you may not use this file except in
 * compliance with the License. You should have received a copy of the
 * Erlang Public License along with this software. If not, it can be
 * retrieved online at http://www.erlang.org/.
 *
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
 * the License for the specific language governing rights and limitations
 * under the License.
 *
 * The Initial Developer of the Original Code is Ericsson AB.
 *</legalnotice>
 */
/**
 * A Holder class for IDL's out/inout argument passing modes for string
 *
 */
package com.ericsson.otp.ic;


/**

Holder class for String, according to OMG-IDL java mapping.

**/ 

final public class StringHolder implements Holder  {
    public String value;
    
    public StringHolder() {}
    
    public StringHolder(String initial) {
	value = initial;
    }

    /* Extra methods not in standard. */ 
    /**
      Comparisson method for Strings.
      @return true if the input object equals the current object, false otherwize
      **/
    public boolean equals( Object obj ) {
	if( obj instanceof String )
	    return ( value == obj);
	else
	    return false;
    }

    /**
      Comparisson method for Strings.
      @return true if the input String value equals the value of the current object, false otherwize
      **/
    public boolean equals( String s ) {
	return ( value == s);
    }
    
}
