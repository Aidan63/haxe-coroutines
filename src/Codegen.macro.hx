import Transform;
import haxe.macro.Expr;

using haxe.macro.ExprTools;
using haxe.macro.ComplexTypeTools;

// static macro function transform(expr) {
//     return switch expr.expr {
//         case EFunction(name, fun):
//             {expr: EFunction(name, doTransform(fun, expr.pos)), pos: expr.pos};
//         case _:
//             throw new Error("Function expected", expr.pos);
//     }
// }

function doTransform(fun:Function, pos:Position):Function {
    var returnCT = if (fun.ret != null) fun.ret else throw new Error("Return type hint expected", pos);
    if (returnCT.toString() == "Void") returnCT = macro : Dynamic;

    var coroArgs = fun.args.copy();
    coroArgs.push({name: "__continuation", type: macro : Continuation<$returnCT>});

    var cfg = FlowGraph.build(fun);

    var coroExpr = if (cfg.hasSuspend) {
        buildStateMachine(cfg.root, fun.expr.pos, returnCT);
    } else {
        buildStateMachine(cfg.root, fun.expr.pos, returnCT);
        // buildSimpleCPS(cfg.root, fun.expr.pos);
    }

    trace(coroExpr.toString());

    return {
        args: coroArgs,
        ret: macro : Continuation<$returnCT>,
        expr: coroExpr
    };
}

function buildStateMachine(bbRoot:BasicBlock, pos:Position, ret:ComplexType):Expr {
    final cases      = new Array<Case>();
    final varDecls   = [];
    final defaultVal = switch ret.toString() {
        case 'Int', 'Float': macro 0;
        case 'Bool': macro false;
        case _: macro null;
    }

    function loop(bb:BasicBlock) {
        var exprs = [];
        for (v in bb.vars)
            varDecls.push(v);

        switch bb.edge {
            case Return:
                var last = bb.elements[bb.elements.length - 1];
                for (i in 0...bb.elements.length - 1)
                    exprs.push(bb.elements[i]);

                exprs.push(macro {
                    __state = -1;
                    __continuation($last, null);
                    return Coroutine.CoroutineResult.Success($last);
                });

            case Final:
                for (e in bb.elements) exprs.push(e);
                exprs.push(macro {
                    __state = -1;
                    __continuation($defaultVal, null);
                    return;
                });

            case Suspend(ef, args, bbNext):
                for (e in bb.elements) exprs.push(e);

                args.push(macro __stateMachine);

                exprs.push(macro {
                    __state = $v{bbNext.id};
                    switch ($ef($a{args})) {
                        case Suspended:
                            return Coroutine.CoroutineResult.Suspended;
                        case other:
                            return other;
                    }
                });
                loop(bbNext);

            case Next(bbNext) | Loop(bbNext, _, _):
                for (e in bb.elements) exprs.push(e);
                loop(bbNext);
                exprs.push(macro __state = $v{bbNext.id});

            case IfThen(bbThen, bbNext):
                var econd = bb.elements[bb.elements.length - 1];
                for (i in 0...bb.elements.length - 1)
                    exprs.push(bb.elements[i]);

                loop(bbThen);
                loop(bbNext);

                exprs.push(macro {
                    if ($econd) {
                        __state = $v{bbThen.id};
                    } else {
                        __state = $v{bbNext.id};
                    }
                });

            case IfThenElse(bbThen, bbElse, _):
                var econd = bb.elements[bb.elements.length - 1];
                for (i in 0...bb.elements.length - 1)
                    exprs.push(bb.elements[i]);

                loop(bbThen);
                loop(bbElse);

                exprs.push(macro {
                    if ($econd) {
                        __state = $v{bbThen.id};
                    } else {
                        __state = $v{bbElse.id};
                    }
                });

            case LoopHead(bbBody, bbNext):
                var econd = bb.elements[bb.elements.length - 1];
                for (i in 0...bb.elements.length - 1)
                    exprs.push(bb.elements[i]);

                loop(bbBody);
                loop(bbNext);

                exprs.push(macro {
                    if ($econd) {
                        __state = $v{bbBody.id};
                    } else {
                        __state = $v{bbNext.id};
                    }
                });

            case LoopBack(bbGoto) | LoopContinue(bbGoto) | LoopBreak(bbGoto):
                for (e in bb.elements) exprs.push(e);
                exprs.push(macro {
                    __state = $v{bbGoto.id};
                });
        }

        cases.unshift({
            values: [macro $v{bb.id}],
            expr: macro $b{exprs}
        });
    }
    loop(bbRoot);

    var eswitch = {
        pos: pos,
        expr: ESwitch(macro __state, cases, macro throw "Invalid state")
    };

    return macro {
        var __state = 0;
        ${ {pos: pos, expr: EVars(varDecls)} };
        function __stateMachine(__result:$ret, __error:haxe.Exception):Coroutine.CoroutineResult {
            try {
                while (true) {
                    $eswitch;
                }
            } catch (exn) {
                __state = -1;

                __continuation($defaultVal, exn);

                return Error(exn);
            }
        }
        // __stateMachine(null);
        return __stateMachine;
    };
}

// static function buildSimpleCPS(bbRoot:BasicBlock, pos:Position):Expr {
// 	function loop(bb:BasicBlock, exprs:Array<Expr>) {
// 		switch bb.edge {
// 			case Suspend(_):
// 				throw "Suspend in a non-suspending coroutine?";

// 			case Return:
// 				var last = bb.elements[bb.elements.length - 1];
// 				for (i in 0...bb.elements.length - 1)
// 					exprs.push(bb.elements[i]);
// 				exprs.push(macro __continuation($last));
// 				exprs.push(macro return);

// 			case Next(bbNext):
// 				for (e in bb.elements) exprs.push(e);
// 				loop(bbNext, exprs);

// 			case Loop(bbHead, bbBody, bbNext):
// 				for (e in bb.elements) exprs.push(e);

// 				var headExprs = [];
// 				loop(bbHead, headExprs);
// 				var condExpr = headExprs.pop();
// 				var bodyExprs = [];
// 				loop(bbBody, bodyExprs);
// 				var loopExpr = macro {
// 					$b{headExprs};
// 					if (!$condExpr) break;
// 					$b{bodyExprs};
// 				};
// 				exprs.push(macro do $loopExpr while (true));
// 				loop(bbNext, exprs);

// 			case LoopHead(_, _) | LoopBack(_):
// 				for (e in bb.elements) exprs.push(e);

// 			case LoopContinue(_):
// 				for (e in bb.elements) exprs.push(e);
// 				exprs.push(macro continue);

// 			case LoopBreak(_):
// 				for (e in bb.elements) exprs.push(e);
// 				exprs.push(macro break);

// 			case IfThen(_, _) | IfThenElse(_, _, _):
// 				throw "TODO";
// 		}
// 	}

// 	var exprs = [];
// 	loop(bbRoot, exprs);
// 	return macro $b{exprs};
// }
