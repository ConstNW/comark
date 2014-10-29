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
				  //~/^(?:[\n`\[\]\\!<&*_]|[^\n`\[\]\\!<&*_]+)/m;
		reMain  = //~/^(?:[\n`\[\]\\!<&*_~]|[^\n`\[\]\\!<&*_~]+)/m;
		            ~/^(?:[_*`\n]+|[\[\]\\!<&*_]|(?: *[^\n `\[\]\\!<&*_~]+)+|[ \n]+)/m;
	}
	
	override function applyParsers( c : Int, inlines : Array<InlineElement> ) : Bool
	{
		return switch( c )
		{
			case '~'.code: parseStrike(inlines);
			case '#'.code: parseHashtag(inlines);
			
			case _: super.applyParsers(c, inlines);
		}
	}
	
	function parseStrike( inlines : Array<InlineElement> ) : Bool
	{
		var startpos : Int = this.pos;
		var c : Int;
		var first_close : Int = 0;
		
		var nxt : Int = this.peek();
		if ( nxt == '~'.code ) c = nxt;
		else
			return false;
		
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
			return false;
		
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
			else if( !this.parseInline(inlines) )
				break;
		}
		
		return (this.pos != startpos);
	}
	
	function parseHashtag( inlines : Array<InlineElement> ) : Bool
	{
		// Entity
		var prev = subject.charAt(pos - 1);
		if ( pos > 0 && prev != ' ' ) 
			return false;
		
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
			return true;
		}
		else
		{
			this.pos = startpos;
			return false;
		}
	}
}