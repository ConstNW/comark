/**
 * ...
 * @author ...
 */
package comark;
import haxe.ds.StringMap;

using StringTools;


class DocParser
{
	static var reAllTab : EReg = ~/\t/g;
	static var reHrule : EReg = ~/^(?:(?:\* *){3,}|(?:_ *){3,}|(?:- *){3,}) *$/;
	
	static var BLOCKTAGNAME = '(?:article|header|aside|hgroup|iframe|blockquote|hr|body|li|map|button|object|canvas|ol|caption|output|col|p|colgroup|pre|dd|progress|div|section|dl|table|td|dt|tbody|embed|textarea|fieldset|tfoot|figcaption|th|figure|thead|footer|footer|tr|form|ul|h1|h2|h3|h4|h5|h6|video|script|style)';
	static var HTMLBLOCKOPEN = "<(?:" + BLOCKTAGNAME + "[\\s/>]" + "|" + "/" + BLOCKTAGNAME + "[\\s>]" + "|" + "[?!])";
	static var reHtmlBlockOpen = new EReg('^' + HTMLBLOCKOPEN, 'i');
	
	public static var ESCAPABLE = '[!"#$%&\'()*+,./:;<=>?@[\\\\\\]^_`{|}~-]';
	public static var reAllEscapedChar = new EReg('\\\\(' + ESCAPABLE + ')', 'g');
	
	var doc : BlockElement;
	var tip : BlockElement;
	
	var refmap : StringMap<Dynamic>;
	
	var inlineParser : InlineParser;
	
	public function new( )
	{
		init();
		
		inlineParser = new InlineParser();
	}
	
	function init( ) : Void
	{
		doc = makeBlock('Document', 1, 1);
		tip = doc;
		refmap = new StringMap();
	}
	
	public function parse( input : String )
	{
		init();
		
		var er = ~/\n$/g;
		while ( er.match(input) )  input = er.replace(input, '');
		
		var lines = ~/\r\n|\n|\r/g.split(input);
		
		var len = lines.length;
		var i = 0;
		do incorporateLine(lines[i], i+1) while ( len > ++i );
		
		while ( tip != null ) finalize(tip, len - 1);
		
		processInlines(doc);
		
		return doc;
	}
	
	// Analyze a line of text and update the document appropriately.
	// We parse markdown text by calling this on each line of input,
	// then finalizing the document.
	function incorporateLine( ln : String, line_number : Int ) : Void
	{
		var all_matched = true;
		var last_child : BlockElement;
		var first_nonspace : Int;
		var offset : Int = 0;
		var match : Int;
		var data : ListData;
		var blank : Bool = true;
		var indent : Int;
		var last_matched_container : BlockElement;
		var i : Int ;
		var CODE_INDENT : Int = 4;
		
		var container = this.doc;
		var oldtip = this.tip;
		
		// Convert tabs to spaces:
		ln = detabLine(ln);
		
		// For each containing block, try to parse the associated line start.
		// Bail out on failure: container will point to the last matching block.
		// Set all_matched to false if not all containers match.
		while ( container.children.length > 0 )
		{
			last_child = container.children[container.children.length - 1];
			if ( !last_child.open )
				break;
			
			container = last_child;
			
			match = matchAt(~/[^ ]/, ln, offset);
			if ( match == null )
			{
				first_nonspace = ln.length;
				blank = true;
			}
			else
			{
				first_nonspace = match;
				blank = false;
			}
			indent = first_nonspace - offset;
			
			switch ( container.t )
			{
				case 'BlockQuote':
					var matched = indent <= 3 && ln.charAt(first_nonspace) == '>';
					if ( matched )
					{
						offset = first_nonspace + 1;
						if (ln.charAt(offset) == ' ')
							offset++;
					}
					else all_matched = false;
				
				case 'ListItem':
					if ( indent >= container.list_data.marker_offset + container.list_data.padding )
					{
						offset += container.list_data.marker_offset +
						container.list_data.padding;
					}
					else if ( blank )
					{
						offset = first_nonspace;
					}
					else all_matched = false;
				
				case 'IndentedCode':
					if ( indent >= CODE_INDENT ) offset += CODE_INDENT;
					else if ( blank ) offset = first_nonspace;
					else all_matched = false;
				
				case 'ATXHeader', 'SetextHeader', 'HorizontalRule':
					// a header can never container > 1 line, so fail to match:
					all_matched = false;
				
				case 'FencedCode':
					// skip optional spaces of fence offset
					i = container.fence_offset;
					while ( i > 0 && ln.charAt(offset) == ' ' )
					{
						offset++;
						i--;
					}
				
				case 'HtmlBlock':
					if ( blank )
						all_matched = false;
					
				case 'Paragraph':
					if ( blank )
					{
						container.last_line_blank = true;
						all_matched = false;
					}
					
				case _:
			}
			
			if ( !all_matched )
			{
				container = container.parent; // back up to last matching block
				break;
			}
		}
		
		last_matched_container = container;
		
		// This function is used to finalize and close any unmatched
		// blocks.  We aren't ready to do this now, because we might
		// have a lazy paragraph continuation, in which case we don't
		// want to close unmatched blocks.  So we store this closure for
		// use later, when we have more information.
		var already_done = false;
		var closeUnmatchedBlocks = function( mythis : DocParser ) {
			// finalize any blocks not matched
			while ( !already_done && oldtip != last_matched_container ) {
				mythis.finalize(oldtip, line_number);
				oldtip = oldtip.parent;
			}
			already_done = true;
		};
		
		// Check to see if we've hit 2nd blank line; if so break out of list:
		if ( blank && container.last_line_blank )
			breakOutOfLists(container, line_number);
		
		// Unless last matched container is a code block, try new container starts,
		// adding children to the last matched container:
		while ( container.t != 'FencedCode' &&
				container.t != 'IndentedCode' &&
				container.t != 'HtmlBlock' &&
				// this is a little performance optimization:
				matchAt(~/^[ #`~*+_=<>0-9-]/, ln, offset) != null )
		{
			match = matchAt(~/[^ ]/, ln, offset);
			if ( match == null )
			{
				first_nonspace = ln.length;
				blank = true;
			}
			else
			{
				first_nonspace = match;
				blank = false;
			}
			indent = first_nonspace - offset;
			
			
			var erATX = ~/^#{1,6}(?: +|$)/;
			var erCode = ~/^`{3,}(?!.*`)|^~{3,}(?!.*~)/;
			var erSetext = ~/^(?:=+|-+) *$/;
			
			if ( indent >= CODE_INDENT )
			{
				// indented code
				if ( tip.t != 'Paragraph' && !blank )
				{
					offset += CODE_INDENT;
					closeUnmatchedBlocks(this);
					container = addChild('IndentedCode', line_number, offset);
				}
				else break; // indent > 4 in a lazy paragraph continuation
				
			}
			else if ( ln.charAt(first_nonspace) == '>' )
			{
				// blockquote
				offset = first_nonspace + 1;
				
				// optional following space
				if (ln.charAt(offset) == ' ')
					offset++;
				
				closeUnmatchedBlocks(this);
				
				container = addChild('BlockQuote', line_number, offset);
			}
			else if ( erATX.match(ln.substr(first_nonspace)) )
			{
				// ATX header
				offset = first_nonspace + erATX.matched(0).length;
				closeUnmatchedBlocks(this);
				
				container = addChild('ATXHeader', line_number, first_nonspace);
				container.level = erATX.matched(0).trim().length; // number of #s
				
				// remove trailing ###s:
				var s = ln.substr(offset);
				container.strings = [~/(?:(\\#) *#*| *#+) *$/.replace(s, '$1')];
				break;
			}
			else if ( erCode.match(ln.substr(first_nonspace)) )
			{
				// fenced code block
				var fence_length = erCode.matched(0).length;
				closeUnmatchedBlocks(this);
				
				container = addChild('FencedCode', line_number, first_nonspace);
				container.fence_length = fence_length;
				container.fence_char = erCode.matched(0).charAt(0);
				container.fence_offset = first_nonspace - offset;
				
				offset = first_nonspace + fence_length;
				break;
			}
			else if ( matchAt(reHtmlBlockOpen, ln, first_nonspace) != null )
			{
				// html block
				closeUnmatchedBlocks(this);
				
				container = addChild('HtmlBlock', line_number, first_nonspace);
				// note, we don't adjust offset because the tag is part of the text
				break;
			}
			else if ( container.t == 'Paragraph' && container.strings.length == 1 && ( erSetext.match(ln.substr(first_nonspace)) ) )
			{
				// setext header line
				closeUnmatchedBlocks(this);
				container.t = 'SetextHeader'; // convert Paragraph to SetextHeader
				container.level = erSetext.matched(0).charAt(0) == '=' ? 1 : 2;
				offset = ln.length;
			}
			else if ( matchAt(reHrule, ln, first_nonspace) != null )
			{
				// hrule
				closeUnmatchedBlocks(this);
				container = addChild('HorizontalRule', line_number, first_nonspace);
				offset = ln.length - 1;
				
				break;
			}
			else if ( (data = parseListMarker(ln, first_nonspace)) != null )
			{
				// list item
				closeUnmatchedBlocks(this);
				data.marker_offset = indent;
				offset = first_nonspace + data.padding;
				
				// add the list if needed
				if ( container.t != 'List' || !(listsMatch(container.list_data, data)) )
				{
					container = addChild('List', line_number, first_nonspace);
					container.list_data = data;
				}
				
				// add the list item
				container = addChild('ListItem', line_number, first_nonspace);
				container.list_data = data;
				
			}
			else break;
			
			if ( acceptsLines(container.t) )
			{
				// if it's a line container, it can't contain other containers
				break;
			}
		}
		
		// What remains at the offset is a text line.  Add the text to the
		// appropriate container.
		match = matchAt(~/[^ ]/, ln, offset);
		
		if ( match == null )
		{
			first_nonspace = ln.length;
			blank = true;
		}
		else
		{
			first_nonspace = match;
			blank = false;
		}
		indent = first_nonspace - offset;
		
		// First check for a lazy paragraph continuation:
		if ( tip != last_matched_container && !blank && tip.t == 'Paragraph' && tip.strings.length > 0)
		{
			// lazy paragraph continuation
			tip.last_line_blank = false;
			addLine(ln, offset);
		}
		else
		{
			// not a lazy continuation
			
			// finalize any blocks not matched
			closeUnmatchedBlocks(this);
			
			// Block quote lines are never blank as they start with >
			// and we don't count blanks in fenced code for purposes of tight/loose
			// lists or breaking out of lists.  We also don't set last_line_blank
			// on an empty list item.
			container.last_line_blank = blank && !(
				container.t == 'BlockQuote' ||
				container.t == 'FencedCode' ||
				(container.t == 'ListItem' && container.children.length == 0 && container.start_line == line_number)
			);
			
			var cont = container;
			while ( cont.parent != null )
			{
				cont.parent.last_line_blank = false;
				cont = cont.parent;
			}
			
			switch ( container.t )
			{
				case 'IndentedCode', 'HtmlBlock':
					addLine(ln, offset);
				
				case 'FencedCode':
					// check for closing code fence:
					var erFence = ~/^(?:`{3,}|~{3,})(?= *$)/;
					var matched = (indent <= 3 &&
							ln.charAt(first_nonspace) == container.fence_char &&
							erFence.match(ln.substr(first_nonspace))
					);
					
					if ( matched && erFence.matched(0).length >= container.fence_length )
						// don't add closing fence to container; instead, close it:
						finalize(container, line_number);
					else
						addLine(ln, offset);
				
				case 'ATXHeader', 'SetextHeader', 'HorizontalRule':
					// nothing to do; we already added the contents.
				
				case _:
					if ( acceptsLines(container.t) )
					{
						addLine(ln, first_nonspace);
					}
					else if ( blank )
					{
						// do nothing
					}
					else if ( container.t != 'HorizontalRule' && container.t != 'SetextHeader' )
					{
						// create paragraph container for line
						container = addChild('Paragraph', line_number, first_nonspace);
						addLine(ln, first_nonspace);
					}
					else
						trace('Line $line_number with container type ${container.t} did not match any condition.');
			}
		}
	}
	
	// Finalize a block.  Close it and do any necessary postprocessing,
	// e.g. creating string_content from strings, setting the 'tight'
	// or 'loose' status of a list, and parsing the beginnings
	// of paragraphs for reference definitions.  Reset the tip to the
	// parent of the closed block.
	function finalize( block : BlockElement, line_number : Int ) : Void
	{
		var pos;
		
		// don't do anything if the block is already closed
		if ( !block.open )
			return;
		
		block.open = false;
		if ( line_number > block.start_line ) block.end_line = line_number - 1;
		else                                  block.end_line = line_number;
		
		switch ( block.t )
		{
			case 'Paragraph':
				block.string_content = ~/^  */m.replace(block.strings.join('\n'), '');
				
				// try parsing the beginning as link reference definitions:
				while (block.string_content.charAt(0) == '[' && ( pos = inlineParser.parseReference(block.string_content, refmap) ) > 0 )
				{
					block.string_content = block.string_content.substr(pos);
					if ( isBlank(block.string_content) )
					{
						block.t = 'ReferenceDef';
						break;
					}
				}
				
			case 'ATXHeader', 'SetextHeader', 'HtmlBlock': block.string_content = block.strings.join('\n');
			
			case 'IndentedCode':
				block.string_content = ~/(\n *)*$/.replace(block.strings.join('\n'), '\n');
			
			case 'FencedCode':
				// first line becomes info string
				block.info = unescape(block.strings[0].trim());
				if ( block.strings.length == 1 )
					block.string_content = '';
				else
					block.string_content = block.strings.slice(1).join('\n') + '\n';
			
			case 'List':
				block.tight = true; // tight by default
				var numitems = block.children.length;
				var i = 0;
				while ( i < numitems )
				{
					var item = block.children[i];
					// check for non-final list item ending with blank line:
					var last_item = i == numitems - 1;
					if ( endsWithBlankLine(item) && !last_item )
					{
						block.tight = false;
						break;
					}
					
					// recurse into children of list item, to see if there are
					// spaces between any of them:
					var numsubitems = item.children.length;
					var j = 0;
					while ( j < numsubitems )
					{
						var subitem = item.children[j];
						var last_subitem = j == numsubitems - 1;
						if ( endsWithBlankLine(subitem) && !(last_item && last_subitem) )
						{
							block.tight = false;
							break;
						}
						j++;
					}
					i++;
				}
			
			case _:
		}
		
		tip = block.parent != null ? block.parent : null;
		//tip = block.parent != null ? block.parent : tip;
	}
	
	// Walk through a block & children recursively, parsing string content
	// into inline content where appropria
	function processInlines( block : BlockElement ) : Void
	{
		switch( block.t )
		{
			case 'Paragraph', 'SetextHeader', 'ATXHeader':
				block.inline_content = inlineParser.parse(block.string_content.trim(), refmap);
				block.string_content = "";
			
			case _:
		}
		
		if ( block.children != null ) for( c in block.children )
			processInlines(c);
	}
	
	
	// These are methods of a DocParser object, defined below.
	function makeBlock( tag : String, start_line : Int, start_column : Int ) : BlockElement return {
		t: tag,
		open: true,
		last_line_blank: false,
		start_line: start_line,
		start_column: start_column,
		end_line: start_line,
		children: [],
		parent: null,
		
		// string_content is formed by concatenating strings, in finalize:
		string_content: "",
		strings: [],
		inline_content: [],
	};
	
	// Add block of type tag as a child of the tip.  If the tip can't
	// accept children, close and finalize it and try its parent,
	// and so on til we find a block that can accept children.
	function addChild( tag : String, line_number : Int, offset : Int ) : BlockElement
	{
		while ( !canContain(tip.t, tag) )
			finalize(tip, line_number);
		
		var column_number = offset + 1; // offset 0 = column 1
		var newBlock = makeBlock(tag, line_number, column_number);
		
		tip.children.push(newBlock);
		newBlock.parent = tip;
		tip = newBlock;
		
		return newBlock;
	}
	
	// Add a line to the block at the tip.  We assume the tip
	// can accept lines -- that check should be done before calling this.
	function addLine( ln : String, offset : Int )
	{
		var s = ln.substr(offset);
		
		if ( !tip.open )
			throw( { msg: 'Attempted to add line ($ln) to closed container.' } );
		
		tip.strings.push(s);
	}
	
	// Convert tabs to spaces on each line using a 4-space tab stop.
	function detabLine( text : String ) : String
	{
		if ( text.indexOf('\t') == -1 )
			return text;
		
		var lastStop : Int = 0;
		return reAllTab.map(text, function(er : EReg) : String {
			var offset = er.matchedPos().pos;
			var result = '    '.substr((offset - lastStop) % 4);
			lastStop = offset + 1;
			return result;
		});
		
		/*
		return text.replace(reAllTab, function(match, offset) {
			var result = '    '.slice((offset - lastStop) % 4);
			lastStop = offset + 1;
			return result;
		});
		*/
	}
	
	// Attempt to match a regex in string s at offset offset.
	// Return index of match or null.
	function matchAt( re : EReg, s : String, offset : Int ) : Null<Int>
	{
		if ( re.match(s.substr(offset)) )
			return offset + re.matchedPos().pos;
		else
			return null;
	}
	
	// Break out of all containing lists, resetting the tip of the
	// document to the parent of the highest list, and finalizing
	// all the lists.  (This is used to implement the "two blank lines
	// break of of all lists" feature.)
	function breakOutOfLists( block : BlockElement, line_number : Int ) : Void
	{
		var b = block;
		var last_list = null;
		do
		{
			if ( b.t == 'List' )
				last_list = b;
			b = b.parent;
			
		}
		while( b != null );
		
		if ( last_list != null )
		{
			while (block != last_list)
			{
				finalize(block, line_number);
				block = block.parent;
			}
			
			finalize(last_list, line_number);
			tip = last_list.parent;
		}
	}
	
	// Parse a list marker and return data on the marker (type, start, delimiter, bullet character, padding) or null.
	function parseListMarker( ln : String, offset : Int ) : ListData
	{
		var rest = ln.substr(offset);
		var match : EReg;
		var spaces_after_marker;
		var data : ListData = cast { };
		
		if ( reHrule.match(rest) )
			return null;
		
		var erBullet = ~/^[*+-]( +|$)/;
		var erOrdered = ~/^(\d+)([.)])( +|$)/;
		if ( erBullet.match(rest) )
		{
			match = erBullet;
			
			spaces_after_marker = erBullet.matched(1).length;
			data.type = 'Bullet';
			data.bullet_char = erBullet.matched(0).charAt(0);
		}
		else if ( erOrdered.match(rest) )
		{
			match = erOrdered;
			
			spaces_after_marker = erOrdered.matched(3).length;
			data.type = 'Ordered';
			data.start = Std.parseInt(erOrdered.matched(1));
			data.delimiter = erOrdered.matched(2);
		}
		else return null;
		
		var blank_item = match.matched(0).length == rest.length;
		if ( spaces_after_marker >= 5 || spaces_after_marker < 1 || blank_item )
			data.padding = match.matched(0).length - spaces_after_marker + 1;
		else
			data.padding = match.matched(0).length;
		
		return data;
	}

	
	// Returns true if the two list items are of the same type,
	// with the same delimiter and bullet character.  This is used
	// in agglomerating list items into lists.
	function listsMatch( list_data : ListData, item_data : ListData ) : Bool
	{
		return (list_data.type == item_data.type &&
				list_data.delimiter == item_data.delimiter &&
				list_data.bullet_char == item_data.bullet_char);
	};

	
	// Returns true if parent block can contain child block.
	function canContain( parent_type : String, child_type : String ) : Bool
	{
		return ( parent_type == 'Document' ||
				 parent_type == 'BlockQuote' ||
				 parent_type == 'ListItem' ||
				(parent_type == 'List' && child_type == 'ListItem') );
	}
	
	// Returns true if block type can accept lines of text.
	function acceptsLines( block_type : String ) : Bool return ( block_type == 'Paragraph' || block_type == 'IndentedCode' || block_type == 'FencedCode' );
	
	// Replace backslash escapes with literal characters.
	function unescape( s ) return reAllEscapedChar.replace(s, '$1');

	// Returns true if string contains only space characters.
	function isBlank(s) return ~/^\s*$/.match(s);
	
	
	// Returns true if block ends with a blank line, descending if needed
	// into lists and sublists.
	function endsWithBlankLine( block : BlockElement ) : Bool
	{
		if ( block.last_line_blank )
			return true;
		
		if ( (block.t == 'List' || block.t == 'ListItem') && block.children.length > 0 )
			return endsWithBlankLine(block.children[block.children.length - 1]);
		else
			return false;
	}
}