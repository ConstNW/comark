/**
 * ...
 * @author ...
 */
package comark;

typedef InlineElement = {
	var t : String;
	@:optional var c : String;
	@:optional var title : String;
	@:optional var destination : String;
	
	@:optional var childs : Array<InlineElement>;
	@:optional var label : Array<InlineElement>;
	//@:optional var childs : Array<InlineElement>;
};