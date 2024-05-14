import haxe.macro.Expr;
import haxe.macro.Context;

class Macro {
	macro static public function build():Array<Field> {
		var fields = Context.getBuildFields();
		for (field in fields) {
			switch field.kind {
				case FFun(fun) if (Lambda.exists(field.meta, m -> m.name == ":suspend")):
					field.kind = FFun(Codegen.doTransform(fun, field.pos));
				case _:
			}
		}
		return fields;
	}
}