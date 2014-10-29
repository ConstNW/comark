/**
 * ...
 * @author ...
 */
package comark;

using StringTools;


class HtmlRenderer
{
	public var header_start : Int;
	public var allow_html : Bool;
	
    // default options:
    var blocksep : String; // '\n', // space between blocks
    var innersep : String; // '\n', // space between block container tag and contents
    var softbreak: String; // '\n', // by default, soft breaks are rendered as newlines in HTML
									// set to "<br />" to make them hard breaks
									// set to " " if you want to ignore line wrapping in source
	//var asd : String;
	
	public function new( )
	{
		blocksep = '\n';
		innersep = '\n';
		softbreak = '\n';
		
		header_start = 1;
		allow_html = true;
	}
	
	public function render( block : BlockElement ) return renderBlock(block);
	
	
	function escape( s : String, ?preserve_entities : Bool ) : String
	{
		if ( preserve_entities )
		{
			s = ~/[&](?![#](x[a-f0-9]{1,8}|[0-9]{1,8});|[a-z][a-z0-9]{1,31};)/gi.replace(s, '&amp;');
			s = ~/[<]/g.replace(s, '&lt;');
			s = ~/[>]/g.replace(s, '&gt;');
			s = ~/["]/g.replace(s,'&quot;');
		}
		else
		{
			s = ~/[&]/g.replace(s, '&amp;');
			s = ~/[<]/g.replace(s, '&lt;');
			s = ~/[>]/g.replace(s, '&gt;');
			s = ~/["]/g.replace(s,'&quot;');
		}
		return s;
	}
	
	// Render an inline element as HTML.
    function renderInline( inlineHtml : InlineElement ) : String
	{
		var attrs;
		switch (inlineHtml.t) {
			case 'Str':
				return escape(inlineHtml.c);
			
			case 'Softbreak':
				return softbreak;
			
			case 'Hardbreak':
				return inTags('br', [], "", true) + '\n';
			
			case 'Emph':
				return inTags('em', [], renderInlines(inlineHtml.childs));
			
			case 'Strong':
				return inTags('strong', [], renderInlines(inlineHtml.childs));
			
			case 'Html':
				return allow_html ? inlineHtml.c : escape(inlineHtml.c);
			
			case 'Link':
				attrs = [['href', escape(inlineHtml.destination, true)]];
				if ( inlineHtml.title != null && inlineHtml.title.length > 0 )
					attrs.push(['title', escape(inlineHtml.title, true)]);
				
				return inTags('a', attrs, renderInlines(inlineHtml.label));
			
			case 'Image':
				attrs = [
					['src', escape(inlineHtml.destination, true)],
					['alt', escape(renderInlines(inlineHtml.label))]
				];
				if ( inlineHtml.title != null && inlineHtml.title.length > 0 )
					attrs.push(['title', escape(inlineHtml.title, true)]);
				
				return inTags('img', attrs, "", true);
			
			case 'Code':
				return inTags('code', [], escape(inlineHtml.c));
			
			case _:
				trace("Uknown inline type " + inlineHtml.t);
		}
		
		return "";
	}
	
	// Render a list of inlines.
    function renderInlines( inlines : Array<InlineElement> ) : String
	{
		var r = '';
		for ( inl in inlines )
			r += renderInline(inl);
		
		return r;
	}
	
	// Render a single block element.
    function renderBlock( block : BlockElement, ?in_tight_list : Bool ) : String
	{
		var tag;
		var attr;
		var info_words;
		
		switch ( block.t )
		{
			case 'Document':
				var whole_doc = renderBlocks(block.children);
				return (whole_doc == '' ? '' : whole_doc + '\n');
			
			case 'Paragraph':
				if ( in_tight_list )
					return renderInlines(block.inline_content);
				else
				{
					return inTags('p', [], renderInlines(block.inline_content));
				}
			
			case 'BlockQuote':
				var filling = renderBlocks(block.children);
				
				return inTags('blockquote', [], filling == '' ? innersep : innersep + renderBlocks(block.children) + innersep);
			
			case 'ListItem':
				return inTags('li', [], renderBlocks(block.children, in_tight_list).trim());
			
			case 'List':
				tag = block.list_data.type == 'Bullet' ? 'ul' : 'ol';
				attr = (block.list_data.start == null || block.list_data.start == 1) ? [] : [['start', Std.string(block.list_data.start)]];
				return inTags(tag, attr, innersep + renderBlocks(block.children, block.tight) + innersep);
			
			case 'ATXHeader', 'SetextHeader':
				tag = 'h' + Std.int(Math.min(6, header_start - 1 + block.level));
				return inTags(tag, [], renderInlines(block.inline_content));
			
			case 'IndentedCode':
				return inTags('pre', [], inTags('code', [], escape(block.string_content)));
			
			case 'FencedCode':
				//info_words = block.info.split(/ +/);
				info_words = ~/ +/.split(block.info);
				attr = info_words.length == 0 || info_words[0].length == 0 ? [] : [['class', 'language-' + escape(info_words[0], true)]];
				return inTags('pre', [], inTags('code', attr, escape(block.string_content)));
			
			case 'HtmlBlock':
				return allow_html ? block.string_content : escape(block.string_content);
			
			case 'ReferenceDef':
				return "";
			
			case 'HorizontalRule':
				return inTags('hr', [], "", true);
			
			default:
				trace("Uknown block type " + block.t);
				return "";
		}
		return "";
	}
	
	// Render a list of block elements, separated by this.blocksep.
    function renderBlocks( blocks : Array<BlockElement>, ?in_tight_list : Bool ) : String
	{
		var r = [];
		for ( b in blocks ) if( b.t != 'ReferenceDef' )
			r.push(renderBlock(b, in_tight_list));
		
		//return r.length == 1 ? r[0] : r.join(blocksep);
		return r.join(blocksep);
	}
	
	// Helper function to produce content in a pair of HTML tags.
	function inTags( tag : String, attribs : Array<Array<String>>, contents : String, ?selfclosing : Bool )
	{
		var r = '<$tag';
		if ( attribs != null ) for( attrib in attribs )
			r += ' ${attrib[0]}="${attrib[1]}"';
		
		if ( contents.length > 0 ) r += '>$contents</$tag>';
		else if ( selfclosing ) r += ' />';
		else                    r += '></$tag>';
		
		return r;
	}
}

/*
// The HtmlRenderer object.
function HtmlRenderer(){
  return {
    // default options:
    blocksep: '\n',  // space between blocks
    innersep: '\n',  // space between block container tag and contents
    softbreak: '\n', // by default, soft breaks are rendered as newlines in HTML
                     // set to "<br />" to make them hard breaks
                     // set to " " if you want to ignore line wrapping in source
    escape: function(s, preserve_entities) {
      if (preserve_entities) {
      return s.replace(/[&](?![#](x[a-f0-9]{1,8}|[0-9]{1,8});|[a-z][a-z0-9]{1,31};)/gi,'&amp;')
              .replace(/[<]/g,'&lt;')
              .replace(/[>]/g,'&gt;')
              .replace(/["]/g,'&quot;');
      } else {
      return s.replace(/[&]/g,'&amp;')
              .replace(/[<]/g,'&lt;')
              .replace(/[>]/g,'&gt;')
              .replace(/["]/g,'&quot;');
      }
    },
    renderInline: renderInline,
    renderInlines: renderInlines,
    renderBlock: renderBlock,
    renderBlocks: renderBlocks,
    render: renderBlock
  };
}
*/
