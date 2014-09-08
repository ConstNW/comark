/**
 * ...
 * @author ...
 */
package comark;
import haxe.ds.StringMap;

using StringTools;


class InlineParser
{
	static var TAGNAME = '[A-Za-z][A-Za-z0-9]*';
	static var ATTRIBUTENAME = '[a-zA-Z_:][a-zA-Z0-9:._-]*';
	static var UNQUOTEDVALUE = "[^\"'=<>`\\x00-\\x20]+";
	static var SINGLEQUOTEDVALUE = "'[^']*'";
	static var DOUBLEQUOTEDVALUE = '"[^"]*"';
	static var ATTRIBUTEVALUE = "(?:" + UNQUOTEDVALUE + "|" + SINGLEQUOTEDVALUE + "|" + DOUBLEQUOTEDVALUE + ")";
	static var ATTRIBUTEVALUESPEC = "(?:" + "\\s*=" + "\\s*" + ATTRIBUTEVALUE + ")";
	static var ATTRIBUTE = "(?:" + "\\s+" + ATTRIBUTENAME + ATTRIBUTEVALUESPEC + "?)";
	static var OPENTAG = "<" + TAGNAME + ATTRIBUTE + "*" + "\\s*/?>";
	static var CLOSETAG = "</" + TAGNAME + "\\s*[>]";
	static var HTMLCOMMENT = "<!--([^-]+|[-][^-]+)*-->";
	static var PROCESSINGINSTRUCTION = "[<][?].*?[?][>]";
	static var DECLARATION = "<![A-Z]+" + "\\s+[^>]*>";
	static var CDATA = "<!\\[CDATA\\[([^\\]]+|\\][^\\]]|\\]\\][^>])*\\]\\]>";
	static var HTMLTAG = "(?:" + OPENTAG + "|" + CLOSETAG + "|" + HTMLCOMMENT + "|" + PROCESSINGINSTRUCTION + "|" + DECLARATION + "|" + CDATA + ")";
	public static var reHtmlTag = new EReg('^' + HTMLTAG, 'i');
	
	
	// Matches a character with a special meaning in markdown,
	// or a string of non-special characters.
	static var reMain = ~/^(?:[\n`\[\]\\!<&*_]|[^\n`\[\]\\!<&*_]+)/m;
	
	static var reEscapable = new EReg(DocParser.ESCAPABLE, '');
	
	static var ESCAPED_CHAR = '\\\\' + DocParser.ESCAPABLE;
	static var reLinkDestinationBraces = new EReg('^(?:[<](?:[^<>\\n\\\\\\x00]' + '|' + ESCAPED_CHAR + '|' + '\\\\)*[>])', '');
	
	static var REG_CHAR = '[^\\\\()\\x00-\\x20]';
	static var IN_PARENS_NOSP = '\\((' + REG_CHAR + '|' + ESCAPED_CHAR + ')*\\)';
	static var reLinkDestination = new EReg('^(?:' + REG_CHAR + '+|' + ESCAPED_CHAR + '|' + IN_PARENS_NOSP + ')*', '');
	
	static var reLinkTitle = new EReg(
    '^(?:"(' + ESCAPED_CHAR + '|[^"\\x00])*"' +
    '|' +
    '\'(' + ESCAPED_CHAR + '|[^\'\\x00])*\'' +
    '|' +
    '\\((' + ESCAPED_CHAR + '|[^)\\x00])*\\))', '');
	
	var subject : String;
	var label_nest_level : Int; //0, // used by parseLinkLabel method
	var pos : Int; // 0,
	var refmap : StringMap<Dynamic>; // { },

	public function new( )
	{
		subject = '';
		label_nest_level = 0;
		pos = 0;
		refmap = new StringMap();
	}
	
	public function parse( s : String, refmap : StringMap<Dynamic> ) : Array<InlineElement>
	{
		this.subject = s;
		this.pos = 0;
		this.refmap = refmap != null ? refmap : new StringMap();
		
		var inlines : Array<InlineElement> = [];
		while ( parseInline(inlines) > 0 ) { }
		return inlines;
	}
	
	// All of the parsers below try to match something at the current position
	// in the subject.  If they succeed in matching anything, they
	// push an inline element onto the 'inlines' list.  They return the
	// number of characters parsed (possibly 0).	
	
	
	// Parse the next inline element in subject, advancing subject position
	// and adding the result to 'inlines'.
	function parseInline( inlines : Array<InlineElement> ) : Int
	{
		var c = peek();
		var res : Int = null;
		
		switch( c )
		{
			case '\n':     res = parseNewline(inlines);
			case '\\':     res = parseEscaped(inlines);
			case '`':      res = parseBackticks(inlines);
			case '*', '_': res = parseEmphasis(inlines);
			case '[':      res = parseLink(inlines);
			case '!':      res = parseImage(inlines);
			case '<':      res = parseAutolink(inlines); if ( res == 0 ) res = parseHtmlTag(inlines);
			case '&':      res = parseEntity(inlines);
			case _:
		}
		
		return res > 0 ? res :  parseString(inlines);
	}
	
	// Attempt to parse a link reference, modifying refmap.
	public function parseReference( s : String, refmap : StringMap<Dynamic> ) : Int
	{
		this.subject = s;
		this.pos = 0;
		
		var rawlabel;
		var dest;
		var title;
		var matchChars;
		var startpos = this.pos;
		var match;
		
		// label:
		matchChars = this.parseLinkLabel();
		if ( matchChars == 0 )
			return 0;
		
		
		
		rawlabel = this.subject.substr(0, matchChars);
		
		// colon:
		if ( this.peek() == ':' )
		{
			this.pos++;
		}
		else
		{
			this.pos = startpos;
			return 0;
		}
		
		//  link url
		this.spnl();

		dest = this.parseLinkDestination();
		if ( dest == null || dest.length == 0 )
		{
			this.pos = startpos;
			return 0;
		}
		
		var beforetitle = this.pos;
		this.spnl();
		title = this.parseLinkTitle();
		if ( title == null )
		{
			title = '';
			// rewind before spaces
			this.pos = beforetitle;
		}
		
		// make sure we're at line end:
		if ( this.match(~/^ *(?:\n|$)/) == null )
		{
			this.pos = startpos;
			return 0;
		}
		
		var normlabel = normalizeReference(rawlabel);
		
		if ( !refmap.exists(normlabel) )
			refmap.set(normlabel, { destination: dest, title: title });
		
		return this.pos - startpos;
	}
	
	// Parse a newline.
	// If it was preceded by two spaces, return a hard line break; otherwise a soft line break.
	function parseNewline( inlines : Array<InlineElement> ) : Int
	{
		if ( this.peek() == '\n')
		{
			pos++;
			var last = inlines[inlines.length - 1];
			if ( last != null && last.t == 'Str' && last.c.substr( -2) == '  ' )
			{
				last.c = ~/ *$/.replace(last.c,'');
				inlines.push({ t: 'Hardbreak' });
			}
			else
			{
				if ( last != null && last.t == 'Str' && last.c.substr( -1) == ' ' )
					last.c = last.c.substr(0, -1);
				
				inlines.push({ t: 'Softbreak' });
			}
			
			return 1;
		}
		else return 0;
	}
	
	// Parse a backslash-escaped special character, adding either the escaped
	// character, a hard line break (if the backslash is followed by a newline),
	// or a literal backslash to the 'inlines' list.
	function parseEscaped( inlines : Array<InlineElement> ) : Int
	{
		var subj = this.subject;
		var pos  = this.pos;
		
		if ( subj.charAt(pos) == '\\' )
		{
			if ( subj.charAt(pos + 1) == '\n' )
			{
				inlines.push({ t: 'Hardbreak' });
				this.pos = this.pos + 2;
				return 2;
			}
			else if ( reEscapable.match(subj.charAt(pos + 1)) )
			{
				inlines.push({ t: 'Str', c: subj.charAt(pos + 1) });
				this.pos = this.pos + 2;
				return 2;
			}
			else
			{
				this.pos++;
				inlines.push({t: 'Str', c: '\\'});
				return 1;
			}
		}
		else return 0;
	}
	
	// Attempt to parse backticks, adding either a backtick code span or a
	// literal sequence of backticks to the 'inlines' list.
	function parseBackticks( inlines : Array<InlineElement> ) : Int
	{
		var startpos = this.pos;
		var ticks = this.match(~/^`+/);
		if ( ticks == null )
			return 0;
		
		var afterOpenTicks = this.pos;
		var foundCode = false;
		var match;
		while ( !foundCode && (match = this.match(~/`+/m)) != null )
		{
			if ( match == ticks )
			{
				inlines.push({
					t: 'Code',
					c: ~/[ \n]+/g.replace(subject.substring(afterOpenTicks, this.pos - ticks.length), ' ').trim()
				});
				return (this.pos - startpos);
			}
		}
		
		// If we got here, we didn't match a closing backtick sequence.
		inlines.push({ t: 'Str', c: ticks });
		this.pos = afterOpenTicks;
		
		return (this.pos - startpos);
	}
	
	// Attempt to parse emphasis or strong emphasis in an efficient way, with no backtracking.
	function parseEmphasis( inlines : Array<InlineElement> ) : Int
	{
		var startpos = this.pos;
		var c ;
		var first_close = 0;
		var nxt = this.peek();
		if (nxt == '*' || nxt == '_') c = nxt;
		else
			return 0;
		
		var numdelims;
		var delimpos;
		
		// Get opening delimiters.
		var res = this.scanDelims(c);
		numdelims = res.numdelims;
		this.pos += numdelims;
		
		// We provisionally add a literal string.  If we match appropriate
		// closing delimiters, we'll change this to Strong or Emph.
		inlines.push({
			t: 'Str',
			c: this.subject.substr(this.pos - numdelims, numdelims)
		});
		
		// Record the position of this opening delimiter:
		delimpos = inlines.length - 1;
		
		if ( !res.can_open || numdelims == 0 )
			return 0;
		
		var first_close_delims = 0;
		
		switch ( numdelims )
		{
			case 1:  // we started with * or _
				while ( true )
				{
					res = this.scanDelims(c);
					if ( res.numdelims >= 1 && res.can_close )
					{
						this.pos += 1;
						// Convert the inline at delimpos, currently a string with the delim,
						// into an Emph whose contents are the succeeding inlines
						inlines[delimpos].t = 'Emph';
						inlines[delimpos].childs = inlines.slice(delimpos + 1, inlines.length);
						inlines.splice(delimpos + 1, inlines.length);
						break;
					}
					else if ( this.parseInline(inlines) == 0 )
						break;
				}
				return (this.pos - startpos);
			
			case 2:  // We started with ** or __
				while ( true )
				{
					res = this.scanDelims(c);
					if ( res.numdelims >= 2 && res.can_close )
					{
						this.pos += 2;
						inlines[delimpos].t = 'Strong';
						inlines[delimpos].childs = inlines.slice(delimpos + 1, inlines.length);
						inlines.splice(delimpos + 1, inlines.length);
						break;
					}
					else if ( this.parseInline(inlines) == 0 )
						break;
				}
				return (this.pos - startpos);
			
			case 3:  // We started with *** or ___
				while ( true )
				{
					res = this.scanDelims(c);
					if ( res.numdelims >= 1 && res.numdelims <= 3 && res.can_close && res.numdelims != first_close_delims )
					{
						if ( first_close_delims == 1 && numdelims > 2 ) res.numdelims = 2;
						else if ( first_close_delims == 2 ) res.numdelims = 1;
						else if ( res.numdelims == 3 )
						{
							// If we opened with ***, then we interpret *** as ** followed by *
							// giving us <strong><em>
							res.numdelims = 1;
						}
						this.pos += res.numdelims;
						
						if (first_close > 0)
						{
							// if we've already passed the first closer:
							inlines[delimpos].t = first_close_delims == 1 ? 'Strong' : 'Emph';
							inlines[delimpos].childs = ([{
								t: first_close_delims == 1 ? 'Emph' : 'Strong',
								childs: inlines.slice(delimpos + 1, first_close)
							}] : Array<InlineElement> )
							.concat(inlines.slice(first_close + 1));
							
							inlines.splice(delimpos + 1, inlines.length);
							break;
						}
						else
						{ 
							// this is the first closer; for now, add literal string;
							// we'll change this when he hit the second closer
							inlines.push({
								t: 'Str',
								c: this.subject.substr(this.pos - res.numdelims, this.pos)
							});
							first_close = inlines.length - 1;
							first_close_delims = res.numdelims;
						}
					}
					else
					{ 
						// parse another inline element, til we hit the end
						if ( this.parseInline(inlines) == 0 )
							break;
					}
				}
				return (this.pos - startpos);
			
			case _:
				//return res;
				return 0;
		}
		
		return 0;
	}
	
	// Attempt to parse an image.  If the opening '!' is not followed
	// by a link, add a literal '!' to inlines.
	function parseImage( inlines : Array<InlineElement> )
	{
		if ( this.match(~/^!/) != null )
		{
			var n = this.parseLink(inlines);
			if ( n == 0 )
			{
				inlines.push({ t: 'Str', c: '!' });
				return 1;
			}
			else if ( inlines[inlines.length - 1] != null && inlines[inlines.length - 1].t == 'Link' )
			{
				inlines[inlines.length - 1].t = 'Image';
				return n+1;
			}
			else
				throw "Shouldn't happen";
		
		}
		else return 0;
	}

	// Attempt to parse a link.  If successful, add the link to
	// inlines.
	function parseLink( inlines : Array<InlineElement> ) : Int
	{
		var startpos = this.pos;
		var reflabel : String;
		var n;
		var dest;
		var title;
		
		n = this.parseLinkLabel();
		if ( n == 0 )
			return 0;
		
		var afterlabel = this.pos;
		var rawlabel = this.subject.substr(startpos, n);
		
		// if we got this far, we've parsed a label.
		// Try to parse an explicit link: [label](url "title")
		if ( this.peek() == '(' )
		{
			this.pos++;
			if ( this.spnl() &&
				((dest = this.parseLinkDestination()) != null) &&
				this.spnl() &&
				// make sure there's a space before the title:
				(~/^\s/.match(this.subject.charAt(this.pos - 1)) && (title = this.parseLinkTitle()) != null || true) &&
				this.spnl() &&
				this.match(~/^\)/) != null
			)
			{
				if ( title == null )
					title = '';
				
				inlines.push( {
					t: 'Link',
					destination: dest,
					title: title,
					label: parseRawLabel(rawlabel)
				});
				return this.pos - startpos;
			}
			else
			{
				this.pos = startpos;
				return 0;
			}
		}
		
		// If we're here, it wasn't an explicit link. Try to parse a reference link.
		// first, see if there's another label
		var savepos = this.pos;
		this.spnl();
		var beforelabel = this.pos;
		n = this.parseLinkLabel();
		if ( n == 2 )
		{
			// empty second label
			reflabel = rawlabel;
		}
		else if ( n > 0 )
		{
			reflabel = this.subject.substring(beforelabel, beforelabel + n);
		}
		else
		{
			this.pos = savepos;
			reflabel = rawlabel;
		}
		
		// lookup rawlabel in refmap
		var link = this.refmap.get(normalizeReference(reflabel));
		if ( link != null )
		{
			inlines.push({
				t: 'Link',
				destination: link.destination,
				title: link.title,
				label: parseRawLabel(rawlabel)
			});
			return this.pos - startpos;
		}
		else
		{
			this.pos = startpos;
			return 0;
		}
		
		// Nothing worked, rewind:
		this.pos = startpos;
		return 0;
	}
	
	// Attempt to parse link title (sans quotes), returning the string
	// or null if no match.
	function parseLinkTitle( )
	{
		var title = this.match(reLinkTitle);
		if ( title != null )
			// chop off quotes from title and unescape:
			return unescape(title.substr(1, title.length - 2));
		else
			return null;
	}

	// Attempt to parse link destination, returning the string or
	// null if no match.
	function parseLinkDestination( )
	{
		var res = this.match(reLinkDestinationBraces);
		if ( res != null )
			// chop off surrounding <..>:
			return unescape(res.substr(1, res.length - 2));
		else
		{
			res = this.match(reLinkDestination);
			if ( res != null )
				return unescape(res);
			else
				return null;
		}
	}
	
	// Attempt to parse a link label, returning number of characters parsed.
	function parseLinkLabel( )
	{
		if ( this.peek() != '[' )
			return 0;
		
		var startpos = this.pos;
		var nest_level = 0;
		if ( this.label_nest_level > 0 )
		{
			// If we've already checked to the end of this subject
			// for a label, even with a different starting [, we
			// know we won't find one here and we can just return.
			// This avoids lots of backtracking.
			// Note:  nest level 1 would be: [foo [bar]
			//        nest level 2 would be: [foo [bar [baz]
			this.label_nest_level--;
			return 0;
		}
		
		this.pos++;  // advance past [
		
		var c;
		while ( (c = this.peek()) != null && (c != ']' || nest_level > 0) )
		{
			switch (c)
			{
				case '`': this.parseBackticks([]);
				case '<': this.parseAutolink([]) > 0 || this.parseHtmlTag([]) > 0 || this.parseString([]) > 0;
				case '[':  // nested []
					nest_level++;
					this.pos++;
				
				case ']':  // nested []
					nest_level--;
					this.pos++;
				
				case '\\':
					this.parseEscaped([]);
				
				default:
					this.parseString([]);
			}
		}
		
		if ( c == ']' )
		{
			this.label_nest_level = 0;
			this.pos++; // advance past ]
			return this.pos - startpos;
		}
		else
		{
			if ( c == null )
				this.label_nest_level = nest_level;
			
			this.pos = startpos;
			return 0;
		}
	}
	
	// Parse raw link label, including surrounding [], and return
	// inline contents.  (Note:  this is not a method of InlineParser.)
	function parseRawLabel( s : String )
	{
		// note:  parse without a refmap; we don't want links to resolve
		// in nested brackets!
		return new InlineParser().parse(s.substr(1, s.length - 2), new StringMap());
	}
	
	// Attempt to parse an entity, adding to inlines if successful.
	function parseEntity( inlines : Array<InlineElement> )
	{
		var m;
		if ( (m = this.match(~/^&(?:#x[a-f0-9]{1,8}|#[0-9]{1,8}|[a-z][a-z0-9]{1,31});/i)) != null )
		{
			inlines.push({ t: 'Entity', c: m });
			return m.length;
		}
		else
			return  0;
	}
	
	// Parse a run of ordinary characters, or a single character with
	// a special meaning in markdown, as a plain string, adding to inlines.
	function parseString( inlines : Array<InlineElement> ) : Int
	{
		var m;
		if ( (m = this.match(reMain)) != null )
		{
			inlines.push({ t: 'Str', c: m });
			return m.length;
		}
		else
			return 0;
	}
	
	// Attempt to parse an autolink (URL or email in pointy brackets).
	function parseAutolink( inlines : Array<InlineElement> ) : Int
	{
		var erMail = ~/^<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>/;
		var erLink = ~/^<(?:coap|doi|javascript|aaa|aaas|about|acap|cap|cid|crid|data|dav|dict|dns|file|ftp|geo|go|gopher|h323|http|https|iax|icap|im|imap|info|ipp|iris|iris.beep|iris.xpc|iris.xpcs|iris.lwz|ldap|mailto|mid|msrp|msrps|mtqp|mupdate|news|nfs|ni|nih|nntp|opaquelocktoken|pop|pres|rtsp|service|session|shttp|sieve|sip|sips|sms|snmp|soap.beep|soap.beeps|tag|tel|telnet|tftp|thismessage|tn3270|tip|tv|urn|vemmi|ws|wss|xcon|xcon-userid|xmlrpc.beep|xmlrpc.beeps|xmpp|z39.50r|z39.50s|adiumxtra|afp|afs|aim|apt|attachment|aw|beshare|bitcoin|bolo|callto|chrome|chrome-extension|com-eventbrite-attendee|content|cvs|dlna-playsingle|dlna-playcontainer|dtn|dvb|ed2k|facetime|feed|finger|fish|gg|git|gizmoproject|gtalk|hcp|icon|ipn|irc|irc6|ircs|itms|jar|jms|keyparc|lastfm|ldaps|magnet|maps|market|message|mms|ms-help|msnim|mumble|mvn|notes|oid|palm|paparazzi|platform|proxy|psyc|query|res|resource|rmi|rsync|rtmp|secondlife|sftp|sgn|skype|smb|soldat|spotify|ssh|steam|svn|teamspeak|things|udp|unreal|ut2004|ventrilo|view-source|webcal|wtai|wyciwyg|xfire|xri|ymsgr):[^<>\x00-\x20]*>/i;
		
		var m : String;
		var dest;
		if ( (m = this.match(erMail)) != null )
		{
			// email autolink
			//dest = m.substr(1,-1);
			dest = m.substr(1, m.length - 2);
			inlines.push( {
				t: 'Link',
				label: [{ t: 'Str', c: dest }],
				destination: 'mailto:' + dest
			});
			return m.length;
		}
		else if ( (m = this.match(erLink)) != null )
		{
			//dest = m.substr(1, -1);
			dest = m.substr(1, m.length - 2);
			inlines.push( {
				t: 'Link',
				label: [{ t: 'Str', c: dest }],
				destination: dest
			});
			return m.length;
		}
		else
			return 0;
	}

	// Attempt to parse a raw HTML tag.
	function parseHtmlTag(inlines : Array<InlineElement> ) : Int
	{
		var m = this.match(reHtmlTag);
		if ( m != null )
		{
			inlines.push({ t: 'Html', c: m });
			return m.length;
		}
		else
			return 0;
	}


	// Replace backslash escapes with literal characters.
	function unescape( s : String ) : String return DocParser.reAllEscapedChar.replace(s, '$1');
	
	// Returns the character at the current subject position, or null if
	// there are no more characters.
	function peek( ) return pos == subject.length ? null : subject.charAt(pos); // ] || null;
	
	// Parse zero or more space characters, including at most one newline
	function spnl( ) : Bool
	{
		this.match(~/^ *(?:\n *)?/);
		return true;
	}
	
	// If re matches at current position in the subject, advance
	// position in subject and return the match; otherwise return null.
	function match( re : EReg ) : String
	{
		if ( re.match(this.subject.substr(this.pos)) )
		{
			this.pos += re.matchedPos().pos + re.matched(0).length;
			return re.matched(0);
		}
		else return null;
	}
	
	// Normalize reference label: collapse internal whitespace
	// to single space, remove leading/trailing whitespace, case fold.
	function normalizeReference( s : String ) return ~/\s+/.replace(s.trim(),' ').toUpperCase();
	
	// Scan a sequence of characters == c, and return information about
	// the number of delimiters and whether they are positioned such that
	// they can open and/or close emphasis or strong emphasis.  A utility
	// function for strong/emph parsing.
	function scanDelims( c )
	{
		var numdelims = 0;
		var first_close_delims = 0;
		var char_before;
		var char_after;
		var startpos = this.pos;
		
		char_before = this.pos == 0 ? '\n' : this.subject.charAt(this.pos - 1);
		
		while ( this.peek() == c )
		{
			numdelims++;
			this.pos++;
		}
		
		char_after = this.peek();
		if( char_after == null ) char_after = '\n';
		
		var can_open = numdelims > 0 && numdelims <= 3 && !(~/\s/.match(char_after));
		var can_close = numdelims > 0 && numdelims <= 3 && !(~/\s/.match(char_before));
		
		if ( c == '_' )
		{
			can_open = can_open && !((~/[a-z0-9]/i).match(char_before));
			can_close = can_close && !((~/[a-z0-9]/i).match(char_after));
		}
		
		this.pos = startpos;
		return {
			numdelims: numdelims,
			can_open: can_open,
			can_close: can_close
		};
	}
}