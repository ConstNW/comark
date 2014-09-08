/**
 * ...
 * @author ...
 */
package comark;

typedef BlockElement = {
	var t : String;
	
	var open : Bool;
	var last_line_blank : Bool;
	
	var start_line : Int;
	var start_column : Int;
	var end_line : Int;
	
	var children : Array<BlockElement>;
	var parent : BlockElement;
	
	// string_content is formed by concatenating strings, in finalize:
	var string_content : String;
	var strings : Array<String>;
	var inline_content : Array<InlineElement>;
	
	@:optional var list_data : ListData;
	@:optional var tight : Bool;
	@:optional var info : Dynamic;
	@:optional var level : Int;
	
	@:optional var fence_length : Int;
	@:optional var fence_char : String;
	@:optional var fence_offset : Int;
};