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
	var spec : String;
	var specG : String;
	
	public function new( )
	{
		init();
	}

	function init( ) : Void
	{
		r = new TestRunner();
		files = [];
		
#if neko
		spec = File.getContent('tests/spec.txt');
		specG = File.getContent('tests/github.txt');
#elseif js
		LoadResources.loadFile('spec.txt', 'bin/tests/spec.txt');
		LoadResources.loadFile('github.txt', 'bin/tests/github.txt');
		
		spec = Resource.getString('spec.txt');
		specG = Resource.getString('github.txt');
#else
	#error
#end
		process(spec);
		process(spec, true);
		process(specG, true, false);
	}
	
	function process( spec : String, github : Bool = false, skipUtf8 : Bool = true )
	{
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
		
		//var secLevel = 0; var sec
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
					
					var md = ~/␣/g.replace(~/→/g.replace(markdown, '\t'), ' ');
					files.push(md);
					
						 if ( false ) { }
					else if ( skipUtf8 && example ==   2 ) { }   // UTF german
					else if ( skipUtf8 && example == 120 ) { }   // UTF greek
					else if ( skipUtf8 && example == 234 ) { }   // UTF magic - Decimal entities
					else if ( skipUtf8 && example == 235 ) { }   // UTF magic - Hexadecimal entities
					else if ( skipUtf8 && example == 377 ) { }   // UTF russian
					
					else if ( github && example ==  25 ) { }   // Github Flavour #hashtag
					
					else
					{
						if ( github )
							r.add(new StringTest(new GithubMarkdown(1, true), md, html, header, example, exampleLine));
						else
							r.add(new StringTest(new Markdown(), md, html, header, example, exampleLine));
					}
					
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
	
	public function run( ) : Void
	{
#if debug
		r.run();
#else
		bench();
#end
	}

#if !debug
	function bench( ) : Void
	{
		var start1 = t();
		for( i in 0...5 )
		for ( f in files ) var out = new comark.Markdown().parse(f);
		var end1 = t();
		
		var start2 = t();
		for( i in 0...5 )
		for ( f in files ) var out = new mdcebe.Markdown().parse(f);
		var end2 = t();
		
		var start3 = t();
		for( i in 0...5 )
		for ( f in files ) var out = markdown.Markdown.markdownToHtml(f);
		var end3 = t();
		
		trace([end1 - start1, end2 - start2, end3 - start3]);
	}
#end

	inline static function t( ) return 
#if neko
		Sys.time();
#elseif js
		Date.now().getTime();
#end
	
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
