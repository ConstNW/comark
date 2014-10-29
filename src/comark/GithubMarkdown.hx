/**
 * ...
 * @author ...
 */
package comark;


class GithubMarkdown extends Markdown
{
	public function new( ?header_start : Int = 1, ?allow_html : Bool = false )
	{
		super();
		
		render = new GithubHtmlRenderer();
		parser = new GithubDocParser();
		
		render.header_start = header_start;
		render.allow_html = allow_html;
	}
}