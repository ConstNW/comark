/**
 * ...
 * @author ...
 */
package comark;
import comark.InlineElement;


class GithubInlineParser extends InlineParser
{
	
	public function new( )
	{
		super();
		
		reMain  = ~/^(?:[\n`\[\]\\!<&*_~]|[^\n`\[\]\\!<&*_~]+)/m;
	}
	
	override function applyParsers( c : String, inlines : Array<InlineElement> ) : Int 
	{
		return switch( c )
		{
			case '~': parseStrike(inlines);
			case '#': parseHashtag(inlines);
			
			case _: super.applyParsers(c, inlines);
		}
	}
	
	
	function parseStrike( inlines : Array<InlineElement> ) : Int
	{
		var startpos : Int = this.pos;
		var c : String;
		var first_close : Int = 0;
		var nxt : String = this.peek();
		if ( nxt == '~' ) c = nxt;
		else
			return 0;
		
		// Get opening delimiters.
		var res = this.scanDelims(c);
		var numdelims = res.numdelims;
		this.pos += numdelims;
		
		// We provisionally add a literal string.  If we match appropriate
		// closing delimiters, we'll change this to Del
		inlines.push({
			t: 'Str',
			c: this.subject.substr(this.pos - numdelims, numdelims)
		});
		
		// Record the position of this opening delimiter:
		var delimpos = inlines.length - 1;
		
		if ( !res.can_open || numdelims != 2 )
			return 0;
		
		// We started with ~~
		while ( true )
		{
			res = this.scanDelims(c);
			if ( res.numdelims >= 2 && res.can_close )
			{
				this.pos += 2;
				inlines[delimpos].t = 'Del';
				inlines[delimpos].childs = inlines.slice(delimpos + 1, inlines.length);
				inlines.splice(delimpos + 1, inlines.length);
				break;
			}
			else if ( this.parseInline(inlines) == 0 )
				break;
		}
		
		return (this.pos - startpos);
	}
	
	function parseHashtag( inlines : Array<InlineElement> ) : Int
	{
		// Entity
		var prev = subject.charAt(pos - 1);
		if ( pos > 0 && prev != ' ' ) 
			return 0;
		
		var startpos : Int = this.pos;
		this.pos++;
		var m : String = null;
		if ( (m = this.match(~/^([^\s!,.#"']+)/m)) != null )
		{
			inlines.push({
				t: 'Link',
				destination: '/hashtag/$m',
				//title: m,
				label: [ { t: 'Str', c: '#$m' } ],
			});
			return m.length;
		}
		else
		{
			this.pos = startpos;
			return 0;
		}
	}
}