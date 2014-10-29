/**
 * ...
 * @author ...
 */

package ;

import comark.Markdown;


class StringTest extends haxe.unit.TestCase
{
	public static var PATH = '';
	
	var md : Markdown;
	//var name : String;
	
	var src : String;
	var res : String;
	
	var num : Int;
	var line : Int;
	var header : String;
	
	public function new( md : Markdown, src : String, res : String, header : String, num : Int, line : Int )
	{
		this.md = md;
		//this.name = name;
		
		super();
		
		this.src = src;
		this.res = res;
		
		this.header = header;
		this.num = num;
		this.line = line;
	}
	
	public function testCoversion( ) : Void assertEquals(res, md.parse(src));
	//public function testCoversion( ) : Void assertEquals(src, md.parse(src));
	
	override public function setup( ) : Void
	{
		super.setup();
		
		currentTest.classname = '$header $num (line $line)';
		print(currentTest.classname + " ");
	}
}