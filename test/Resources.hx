import haxe.Resource;
import haxe.macro.Context;

import comark.GithubMarkdown;
import comark.Markdown;

using StringTools;


class Resources
{
	var files : Array<String>;
	var spec : String;
	var specG : String;

    public var cases : Array<SpecCase>;

	public function new( )
	{
        cases = [];
		files = [];
#if !sys
		LoadResources.loadFile('tests/spec.txt', 'bin/tests/spec.txt');
		LoadResources.loadFile('tests/github.txt', 'bin/tests/github.txt');
#end
		process('tests/spec.txt');
		process('tests/spec.txt', true);
		process('tests/github.txt', true, false);
	}
	
	function process( file : String , github : Bool = false, skipUtf8 : Bool = true ) : Void
	{
		var spec : String = '';
#if sys
		spec = sys.io.File.getContent(file);
#else
		spec = Resource.getString(file);
#end
		var lines = spec.replace('\r', '').split('\n');
		
		var eStart : EReg = ~/^\.$/;
		var eEnd : EReg = ~/^<!-- END TESTS -->/;
		var eHead : EReg = ~/^(#+) +(.*)/;
		
		var stage = 0;
		var lineNum = 0;
		var example = 0;
		var exampleLine = 0;
		
		var markdown = '';
		var html = '';
		
		//var secLevel = 0; var sec
		var header = '';
		
		for (l in lines)
		{
			lineNum++;
			if (eStart.match(l))
			{
				stage = (stage + 1) % 3;
				
				if (stage == 1)
				{
					exampleLine = lineNum;
				}
				else if (stage == 0)
				{
					example++;
					
					var md = ~/␣/g.replace(~/→/g.replace(markdown, '\t'), ' ');
					files.push(md);
					
						 if (false ) { }
					else if (skipUtf8 && example ==   2) { }   // UTF german
					else if (skipUtf8 && example == 120) { }   // UTF greek
					else if (skipUtf8 && example == 234) { }   // UTF magic - Decimal entities
					else if (skipUtf8 && example == 235) { }   // UTF magic - Hexadecimal entities
					else if (skipUtf8 && example == 377) { }   // UTF russian
					
					else if (github && example ==  25) { }   // Github Flavour #hashtag
					
					else cases.push({
						md: md,
						html: html,
						header: header,
						example: example,
						line: exampleLine,
						file: file,
						is_github: github,
					});

					markdown = '';
					html = '';
				}
			}
			else if (stage == 0 && eEnd.match(l))
			{
				break;
			}
			else if (stage == 0 && eHead.match(l)) header = eHead.matched(2);
			else if (stage == 1) markdown += l + '\n';
			else if (stage == 2) html += l + '\n';
		}
	}
}

class LoadResources
{
	macro public static function loadFile( name : String, file : String )
	{
		Context.addResource(name, sys.io.File.getBytes(file));
		
		return Context.makeExpr(0, Context.currentPos());
	}
}