import utest.Assert;
import comark.Markdown;
import comark.GithubMarkdown;

class StringTest extends utest.Test
{
	var specs : Array<SpecCase>;
	
	public function new( specs : Array<SpecCase> )
	{
		this.specs = specs;
		
		super();
	}
	
	public function test_baseCases( ) : Void
	{
		var md = new Markdown();

		for (spec in specs)
			if (!spec.is_github)
				Assert.equals(spec.html, md.parse(spec.md), null, {
					fileName: spec.file,
					lineNumber: spec.line,
					className: spec.header,
					methodName: '${spec.example}'
				});
				//  '${spec.header} ${spec.example} (line ${spec.line})');

		// Assert.equals(res, md.parse(src), '$header $num (line $line)');

	}
	public function test_githubCases( ) : Void
	{
		var md = new GithubMarkdown(1, true);

		for (spec in specs)
			if (!spec.is_github)
				Assert.equals(spec.html, md.parse(spec.md), null, {
					fileName: spec.file,
					lineNumber: spec.line,
					className: spec.header,
					methodName: '${spec.example}'
				});
				//  '${spec.header} ${spec.example} (line ${spec.line})');
	}
	
}