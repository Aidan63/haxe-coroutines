import haxe.macro.Printer;
import haxe.macro.Expr;
import haxe.macro.Context;

class Macro {
	macro static public function build():Array<Field> {
		var fields = Context.getBuildFields();
		var coros  = [];

		for (field in fields) {
			switch field.kind {
				case FFun(fun) if (Lambda.exists(field.meta, m -> m.name == ":suspend")):
					coros.push(field.name);
				case _:
			}
		}
		
		for (field in fields) {
			switch field.kind {
				case FFun(fun) if (Lambda.exists(field.meta, m -> m.name == ":suspend")):
					field.kind = FFun(Codegen.doTransform(fun, field.pos, coros));

					trace(field.name);
					trace(new Printer().printField(field));
				case _:
			}
		}
		return fields;
	}
}