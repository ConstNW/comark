/**
 * ...
 * @author ...
 */
package comark;


class GithubMarkdown extends Markdown
{
	public function new( )
	{
		super();
		
		render = new GithubHtmlRenderer();
		parser = new GithubDocParser();
	}
}