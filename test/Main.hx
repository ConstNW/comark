/**
 * ...
 * @author Const
 */
import comark.GithubMarkdown;
import haxe.macro.Context;
import haxe.Resource;
import haxe.unit.TestRunner;

import comark.DocParser;
import comark.HtmlRenderer;
import comark.Markdown;

#if neko
import sys.FileSystem;
import sys.io.File;
#end

class Main
{
	var r : TestRunner;
	var files : Array<String>;
	
	public function new( )
	{
		init();
	}

	function init( ) : Void
	{
		r = new TestRunner();
		files = [];
		
#if neko
		var spec = File.getContent('tests/spec.txt');
#elseif js
		LoadResources.loadFile('spec.txt', 'bin/tests/spec.txt');
		var spec = Resource.getString('spec.txt');
#else
	#error
#end
		var lines = spec.split('\n');
		
		var eStart : EReg = ~/^\.$/;
		var eEnd : EReg = ~/^<!-- END TESTS -->/;
		var eHead : EReg = ~/^(#+) +(.*)/;
		
		var stage = 0;
		var lineNum = 0;
		var example = 0;
		var exampleLine = 0;
		
		var markdown = '';
		var html = '';
		
		var header = '';
		
		for ( l in lines )
		{
			lineNum++;
			if ( eStart.match(l) )
			{
				stage = (stage + 1) % 3;
				
				if ( stage == 1 )
				{
					exampleLine = lineNum;
				}
				else if ( stage == 0 )
				{
					example++;
#if neko
					     if ( example ==   2 ) { }   // UTF german
					else if ( example == 110 ) { }   // UTF greek
					else if ( example == 349 ) { }   // UTF russian
					else 
#end
						 if ( example ==  25 ) { }   // Github Flavour #hashtag
					else
						r.add(new StringTest(new GithubMarkdown(), ~/␣/g.replace(~/→/g.replace(markdown, '\t'), ' '), html, header, example, exampleLine));
					
					markdown = '';
					html = '';
				}
			}
			else if ( stage == 0 && eEnd.match(l) )
			{
				break;
			}
			else if ( stage == 0 && eHead.match(l) ) header = eHead.matched(2);
			else if ( stage == 1 ) markdown += l + '\n';
			else if ( stage == 2 ) html += l + '\n';
			
		}
		
	}

	public function run( ) : Void r.run();
	
	static function main() new Main().run();
}

class LoadResources
{
	macro public static function loadFile( name : String, file : String )
	{
		Context.addResource(name, File.getBytes(file));
		
		return Context.makeExpr(0, Context.currentPos());
	}
}
