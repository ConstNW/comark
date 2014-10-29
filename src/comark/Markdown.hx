/**
 * ...
 * @author ...
 */
package comark;

class Markdown
{
	var render : HtmlRenderer;
	var parser : DocParser;
	
	public function new( )
	{
		render = new HtmlRenderer();
		parser = new DocParser();
	}
	
	public function parse( text : String ) : String return render.render(parser.parse(text));
}