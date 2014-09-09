/**
 * ...
 * @author ...
 */
package comark;
import comark.InlineElement;


class GithubHtmlRenderer extends HtmlRenderer
{
	
	public function new( )
	{
		super();
	}
	
	override function renderInline( inlineHtml : InlineElement ) : String
	{
		return switch ( inlineHtml.t )
		{
			case 'Del': inTags('del', [], renderInlines(inlineHtml.childs));
			
			case _: super.renderInline(inlineHtml);
		}
	}
}