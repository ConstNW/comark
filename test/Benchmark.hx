class Benchmark
{
    public function new( )
    {
        
    }

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

    inline static function t( ) return haxe.Timer.stamp();
}