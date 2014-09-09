/**
 * ...
 * @author ...
 */
package comark;


class GithubDocParser extends DocParser
{
	
	public function new( )
	{
		super();
		
		inlineParser = new GithubInlineParser();
	}
	
}