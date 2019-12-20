import utest.Runner;
import utest.ui.Report;


class Main
{
	static function main( ) : Void
	{
		var r = new Resources();

		var mode = 'test';
#if sys
		mode = Sys.args()[0];
#else
		mode = '';
#end
		switch(mode)
		{
			case 'bench':

			default: 
				var runner = new Runner();
				runner.addCase(new StringTest(r.cases));
				Report.create(runner);
				runner.run();
		}
	}
}