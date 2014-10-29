/**
 * ...
 * @author ...
 */
package comark;
import haxe.ds.StringMap;

using StringTools;

typedef EmphasisOpener = {
	var cc : Int; // cc,
	var numdelims : Int; // numdelims,
	var pos : Int; // inlines.length - 1,
	var previous : EmphasisOpener; // this.emphasis_openers
};

class InlineParser
{
	inline static var C_NEWLINE = 10;
	inline static var C_SPACE = 32;
	inline static var C_ASTERISK = 42;
	inline static var C_UNDERSCORE = 95;
	inline static var C_BACKTICK = 96;
	inline static var C_OPEN_BRACKET = 91;
	inline static var C_CLOSE_BRACKET = 93;
	inline static var C_LESSTHAN = 60;
	inline static var C_GREATERTHAN = 62;
	inline static var C_BANG = 33;
	inline static var C_BACKSLASH = 92;
	inline static var C_AMPERSAND = 38;
	inline static var C_OPEN_PAREN = 40;
	inline static var C_COLON = 58;
	
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
	
	public static var ESCAPABLE = '[!"#$%&\'()*+,./:;<=>?@[\\\\\\]^_`{|}~-]';
	public static var reAllEscapedChar = new EReg('\\\\(' + ESCAPABLE + ')', 'g');
	
	// Matches a character with a special meaning in markdown,
	// or a string of non-special characters.
	var reMain : EReg;
	
	static var reEscapable = new EReg(ESCAPABLE, '');
	
	static var ENTITY = "&(?:#x[a-f0-9]{1,8}|#[0-9]{1,8}|[a-z][a-z0-9]{1,31});";
	static var reEntity = new EReg(ENTITY, 'gi');
	static var reEntityHere = new EReg('^' + ENTITY, 'i');
	
	static var ESCAPED_CHAR = '\\\\' + ESCAPABLE;
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
	var emphasis_openers : EmphasisOpener; // used by parseEmphasis method
	var pos : Int; // 0,
	var refmap : StringMap<Dynamic>; // { },

	public function new( )
	{
		reMain  = // ~/^(?:[\n`\[\]\\!<&*_]|[^\n`\[\]\\!<&*_]+)/m;
		~/^(?:[_*`\n]+|[\[\]\\!<&*_]|(?: *[^\n `\[\]\\!<&*_]+)+|[ \n]+)/m;
		
		subject = '';
		label_nest_level = 0;
		pos = 0;
		refmap = new StringMap();
	}
	
	// Parse s as a list of inlines, using refmap to resolve references.
	// parseInlines
	public function parse( s : String, refmap : StringMap<Dynamic> ) : Array<InlineElement>
	{
		this.subject = s;
		this.pos = 0;
		this.refmap = refmap != null ? refmap : new StringMap();
		
		var inlines : Array<InlineElement> = [];
		while ( parseInline(inlines) ) { }
		return inlines;
	}
	
	// All of the parsers below try to match something at the current position
	// in the subject.  If they succeed in matching anything, they
	// push an inline element onto the 'inlines' list.  They return the
	// number of characters parsed (possibly 0).	
	
	
	// Parse the next inline element in subject, advancing subject position.
	// On success, add the result to the inlines list, and return true.
	// On failure, return false.
	function parseInline( inlines : Array<InlineElement> ) : Bool
	{
		var startpos = this.pos;
		var origlen = inlines.length;
		
		var c = peek();
		if ( c == -1 )
			return false;
		
		var res : Bool = applyParsers(c, inlines);
		if ( !res )
		{
			pos += 1;
			inlines.push({
				t: 'Str',
				c: EntityToChar.fromCodePoint([c])
			});
		}
		
		return true;
		// return res > 0 ? res :  parseString(inlines);
	}
	
	function applyParsers( c : Int, inlines : Array<InlineElement> ) : Bool
	{
		return switch( c )
		{
			case C_NEWLINE,
				 C_SPACE:        parseNewline(inlines);
			
			case C_BACKSLASH:    parseBackslash(inlines);
			
			case C_BACKTICK:     parseBackticks(inlines);
			
			case C_ASTERISK,
				 C_UNDERSCORE:   parseEmphasis(c, inlines);
			
			case C_OPEN_BRACKET: parseLink(inlines);
			
			case C_BANG:         parseImage(inlines);
			
			case C_LESSTHAN:     parseAutolink(inlines) || parseHtmlTag(inlines);
			
			case C_AMPERSAND:    parseEntity(inlines);
			
			case _:              parseString(inlines);
		}
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
		if ( this.peek() == C_COLON )
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
	// If it was preceded by two spaces, return a hard line break;
	// otherwise a soft line break.
	function parseNewline( inlines : Array<InlineElement> ) : Bool
	{
		var m : String = match(~/^ *\n/);
		
		if ( m == null )
			return false;
		
		if ( m.length > 2 )
			inlines.push( { t: 'Hardbreak' } );
		else
			inlines.push( { t: 'Softbreak' } );
		
		return true;
		/*
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
		*/
	}
	
	// Parse a backslash-escaped special character, adding either the escaped
	// character, a hard line break (if the backslash is followed by a newline),
	// or a literal backslash to the 'inlines' list.
	function parseBackslash( inlines : Array<InlineElement> ) : Bool
	{
		var subj = this.subject;
		var pos  = this.pos;
		
		if ( subj.charCodeAt(pos) == C_BACKSLASH )
		{
			if ( subj.charAt(pos + 1) == '\n' )
			{
				inlines.push({ t: 'Hardbreak' });
				this.pos = this.pos + 2;
			}
			else if ( reEscapable.match(subj.charAt(pos + 1)) )
			{
				inlines.push({ t: 'Str', c: subj.charAt(pos + 1) });
				this.pos = this.pos + 2;
			}
			else
			{
				this.pos++;
				inlines.push({t: 'Str', c: '\\'});
			}
			
			return true;
		}
		else return false;
	}
	
	// Attempt to parse backticks, adding either a backtick code span or a
	// literal sequence of backticks to the 'inlines' list.
	function parseBackticks( inlines : Array<InlineElement> ) : Bool
	{
		var startpos = this.pos;
		var ticks = this.match(~/^`+/);
		if ( ticks == null )
			return false;
		
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
				return true;
			}
		}
		
		// If we got here, we didn't match a closing backtick sequence.
		this.pos = afterOpenTicks;
		inlines.push({ t: 'Str', c: ticks });
		return true;
	}
	
	// Attempt to parse emphasis or strong emphasis.
	function parseEmphasis( cc : Int, inlines : Array<InlineElement> ) : Bool
	{
		var startpos = this.pos;
		
		var res = scanDelims(cc);
		var numdelims = res.numdelims;
		
		if ( numdelims == 0 )
		{
			this.pos = startpos;
			return false;
		}
		
		if ( res.can_close )
		{
			// Walk the stack and find a matching opener, if possible
			var opener = this.emphasis_openers;
			while ( opener != null )
			{
				// we have a match!
				if ( opener.cc == cc )
				{
					// all openers used
					if ( opener.numdelims <= numdelims )
					{
						this.pos += opener.numdelims;
						var X : Dynamic -> Dynamic = null;
						switch ( opener.numdelims )
						{
							case 3: X = function(x) { return makeStrong([makeEmph(x)]); };
							case 2: X = makeStrong;
							case 1, _: X = makeEmph;
						}
						
						inlines[opener.pos] = X(inlines.slice(opener.pos + 1));
						inlines.splice(opener.pos + 1, inlines.length - (opener.pos + 1));
						
						// Remove entries after this, to prevent overlapping nesting:
						this.emphasis_openers = opener.previous;
						return true;
					}
					// only some openers used
					else if ( opener.numdelims > numdelims )
					{
						this.pos += numdelims;
						opener.numdelims -= numdelims;
						
						inlines[opener.pos].c = inlines[opener.pos].c.substr(0, opener.numdelims);
						
						var X : Dynamic -> Dynamic = numdelims == 2 ? makeStrong : makeEmph;
						
						inlines[opener.pos + 1] = X(inlines.slice(opener.pos + 1));
						inlines.splice(opener.pos + 2, inlines.length - (opener.pos + 2));
						
						// Remove entries after this, to prevent overlapping nesting:
						this.emphasis_openers = opener;
						return true;
					}
				}
				opener = opener.previous;
			}
		}
		
		// If we're here, we didn't match a closer.
		this.pos += numdelims;
		inlines.push(makeStr(this.subject.substring(startpos, startpos + numdelims)));
		
		if ( res.can_open )
		{
			// Add entry to stack for this opener
			this.emphasis_openers = {
				cc: cc,
				numdelims: numdelims,
				pos: inlines.length - 1,
				previous: this.emphasis_openers
			};
		}
		
		return true;
	}
	
	// Attempt to parse an image.  If the opening '!' is not followed
	// by a link, add a literal '!' to inlines.
	function parseImage( inlines : Array<InlineElement> ) : Bool
	{
		if ( this.match(~/^!/) != null )
		{
			var link = parseLink(inlines);
			if ( link )
			{
				// if ( inlines[inlines.length - 1] != null && inlines[inlines.length - 1].t == 'Link' )
				inlines[inlines.length - 1].t = 'Image';
				return true;
			}
			else
			{
				inlines.push({ t: 'Str', c: '!' });
				return true;
			}
		}
		else return false;
	}

	// Attempt to parse a link.  If successful, add the link to inlines.
	function parseLink( inlines : Array<InlineElement> ) : Bool
	{
		var startpos = this.pos;
		var reflabel : String;
		var n;
		var dest;
		var title;
		
		n = this.parseLinkLabel();
		if ( n == 0 )
			return false;
		
		var afterlabel = this.pos;
		var rawlabel = this.subject.substr(startpos, n);
		
		// if we got this far, we've parsed a label.
		// Try to parse an explicit link: [label](url "title")
		if ( this.peek() == C_OPEN_PAREN )
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
				
				inlines.push({
					t: 'Link',
					destination: dest,
					title: title,
					label: parseRawLabel(rawlabel)
				});
				return true;
			}
			else
			{
				this.pos = startpos;
				return false;
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
			return true;
		}
		else
		{
			this.pos = startpos;
			return false;
		}
		
		// Nothing worked, rewind:
		this.pos = startpos;
		return false;
	}
	
	// Attempt to parse link title (sans quotes), returning the string
	// or null if no match.
	function parseLinkTitle( )
	{
		var title = this.match(reLinkTitle);
		if ( title != null )
			// chop off quotes from title and unescape:
			return unescapeString(title.substr(1, title.length - 2));
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
			return fixEncode(
					unescape(
						unescapeString(res.substr(1, res.length - 2))
					).urlEncode()
				);
		else
		{
			res = this.match(reLinkDestination);
			if ( res != null )
				return fixEncode(
						unescape(
							unescapeString(res)
						).urlEncode()
					);
			else
				return null;
		}
	}
	
	// Attempt to parse a link label, returning number of characters parsed.
	function parseLinkLabel( ) : Int
	{
		if ( this.peek() != C_OPEN_BRACKET )
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
		while ( (c = this.peek()) != -1 && (c !=  C_CLOSE_BRACKET || nest_level > 0) )
		{
			switch (c)
			{
				case C_BACKTICK:      this.parseBackticks([]);
				case C_LESSTHAN:      if ( !(this.parseAutolink([]) || this.parseHtmlTag([])) ) this.pos++;
				case C_OPEN_BRACKET:  // nested []
					nest_level++;
					this.pos++;
				
				case C_CLOSE_BRACKET: // nested []
					nest_level--;
					this.pos++;
				
				case C_BACKSLASH:     this.parseBackslash([]);
				
				case _:               this.parseString([]);
			}
		}
		
		if ( c == C_CLOSE_BRACKET )
		{
			this.label_nest_level = 0;
			this.pos++; // advance past ]
			return this.pos - startpos;
		}
		else
		{
			if ( c == -1 )
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
	function parseEntity( inlines : Array<InlineElement> ) : Bool
	{
		var m;
		/*
		if ((m = this.match(reEntityHere))) {
			inlines.push({ t: 'Str', c: entityToChar(m) });
			return true;
		} else {
			return false;
		}
		*/
		if ( (m = this.match(reEntityHere)) != null )
		{
			inlines.push({ t: 'Str', c: EntityToChar.entityToChar(m) });
			return true;
		}
		else
			return  false;
	}
	
	// Parse a run of ordinary characters, or a single character with
	// a special meaning in markdown, as a plain string, adding to inlines.
	function parseString( inlines : Array<InlineElement> ) : Bool
	{
		var m;
		if ( (m = this.match(reMain)) != null )
		{
			inlines.push({ t: 'Str', c: m });
			return true;
		}
		else
			return false;
	}
	
	// Attempt to parse an autolink (URL or email in pointy brackets).
	function parseAutolink( inlines : Array<InlineElement> ) : Bool
	{
		var erMail = ~/^<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>/;
		var erLink = ~/^<(?:coap|doi|javascript|aaa|aaas|about|acap|cap|cid|crid|data|dav|dict|dns|file|ftp|geo|go|gopher|h323|http|https|iax|icap|im|imap|info|ipp|iris|iris.beep|iris.xpc|iris.xpcs|iris.lwz|ldap|mailto|mid|msrp|msrps|mtqp|mupdate|news|nfs|ni|nih|nntp|opaquelocktoken|pop|pres|rtsp|service|session|shttp|sieve|sip|sips|sms|snmp|soap.beep|soap.beeps|tag|tel|telnet|tftp|thismessage|tn3270|tip|tv|urn|vemmi|ws|wss|xcon|xcon-userid|xmlrpc.beep|xmlrpc.beeps|xmpp|z39.50r|z39.50s|adiumxtra|afp|afs|aim|apt|attachment|aw|beshare|bitcoin|bolo|callto|chrome|chrome-extension|com-eventbrite-attendee|content|cvs|dlna-playsingle|dlna-playcontainer|dtn|dvb|ed2k|facetime|feed|finger|fish|gg|git|gizmoproject|gtalk|hcp|icon|ipn|irc|irc6|ircs|itms|jar|jms|keyparc|lastfm|ldaps|magnet|maps|market|message|mms|ms-help|msnim|mumble|mvn|notes|oid|palm|paparazzi|platform|proxy|psyc|query|res|resource|rmi|rsync|rtmp|secondlife|sftp|sgn|skype|smb|soldat|spotify|ssh|steam|svn|teamspeak|things|udp|unreal|ut2004|ventrilo|view-source|webcal|wtai|wyciwyg|xfire|xri|ymsgr):[^<>\x00-\x20]*>/i;
		
		var m : String;
		var dest;
		if ( (m = this.match(erMail)) != null )
		{
			// email autolink
			dest = m.substr(1, m.length - 2);
			inlines.push( {
				t: 'Link',
				label: [{ t: 'Str', c: dest }],
				destination: 'mailto:' + fixEncode(unescape(dest).urlEncode())
			});
			return true;
		}
		else if ( (m = this.match(erLink)) != null )
		{
			dest = m.substr(1, m.length - 2);
			
			inlines.push({
				t: 'Link',
				label: [{ t: 'Str', c: dest }],
				destination: fixEncode(unescape(dest).urlEncode())
			});
			return true;
		}
		else
			return false;
	}

	// Attempt to parse a raw HTML tag.
	function parseHtmlTag(inlines : Array<InlineElement> ) : Bool
	{
		var m = this.match(reHtmlTag);
		if ( m != null )
		{
			inlines.push({ t: 'Html', c: m });
			return true;
		}
		else
			return false;
	}


	// Replace backslash escapes with literal characters.
	function unescape( s : String ) : String
	{
		return s.replace('%20', ' '); // reAllEscapedChar.replace(s, '$1');
	}
	
	// Replace entities and backslash escapes with literal characters.
	inline public static function unescapeString( s : String ) : String
	{
		return reEntity.map(reAllEscapedChar.replace(s, '$1'), EntityToChar.entityToCharEr);
	}
	
	// Returns the character at the current subject position, or null if
	// there are no more characters.
	function peek( ) : Int return pos == subject.length ? -1 : subject.charCodeAt(pos); // ] || null;
	
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
	function scanDelims( c : Int )
	{
		var numdelims : Int = 0;
		var first_close_delims : Int = 0;
		var char_before : String;
		var char_after : String;
		var c_after : Int;
		var startpos : Int = this.pos;
		
		char_before = this.pos == 0 ? '\n' : this.subject.charAt(this.pos - 1);
		
		while ( this.peek() == c )
		{
			numdelims++;
			this.pos++;
		}
		
		c_after = this.peek();
		char_after = c_after == -1 ? '\n' : EntityToChar.fromCodePoint([c_after]);
		
		var can_open = numdelims > 0 && numdelims <= 3 && !(~/\s/.match(char_after));
		var can_close = numdelims > 0 && numdelims <= 3 && !(~/\s/.match(char_before));
		
		if ( c == C_UNDERSCORE )
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
	
	inline public function fixEncode( s : String ) : String return s
		.replace('%2F', '/')
		.replace('%28', '(')
		.replace('%29', ')')
		.replace('%2A', '*')
		.replace('%3A', ':')
		.replace('%3F', '?')
		.replace('%3D', '=')
		.replace('%26', '&')
		.replace('%40', '@')
		.replace('%2B', '+')
	;
	
	
	inline public static function makeEmph( ils : Array<InlineElement> ) : InlineElement return { t: 'Emph', childs: ils };
	inline public static function makeStrong( ils : Array<InlineElement> ) : InlineElement return { t: 'Strong', childs: ils };
	inline public static function makeStr( s : String ) : InlineElement return { t: 'Str', c: s };
	
/*
	subject: '',
	label_nest_level: 0, // used by parseLinkLabel method
	pos: 0,
	refmap: {},
	
	match: match,
	peek: peek,
	spnl: spnl,
	
	parseBackticks: parseBackticks,
	parseEscaped: parseEscaped,
	parseAutolink: parseAutolink,
	parseHtmlTag: parseHtmlTag,
	scanDelims: scanDelims,
	parseEmphasis: parseEmphasis,
	parseLinkTitle: parseLinkTitle,
	parseLinkDestination: parseLinkDestination,
	parseLinkLabel: parseLinkLabel,
	parseLink: parseLink,
	parseEntity: parseEntity,
	parseString: parseString,
	parseNewline: parseNewline,
	parseImage: parseImage,
	parseReference: parseReference,
	parseInline: parseInline,
	parse: parseInlines
*/
}