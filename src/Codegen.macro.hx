import Transform;
import haxe.macro.Printer;
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.ExprTools;
using haxe.macro.ComplexTypeTools;

function doTransform(funcName:String, fun:Function, pos:Position, found:Array<String>):Function {
    if (fun.ret == null) {
        throw new Error("Return type hint expected", pos);
    }

    final coroArgs = fun.args.copy();
    final cfg      = FlowGraph.build(fun, found);

    coroArgs.push({ name: "_hx_completion", type: macro : coro.IContinuation<Any> });

    return {
        args: coroArgs,
        ret : macro : Any,
        expr: buildStateMachine(cfg.root, fun.expr.pos, funcName, fun)
    };
}

function buildClass(className:String, funcName:String, fun:Function):TypeDefinition {
    final owningClass = Context.getLocalClass().get().module;
    final args        = fun.args.map(arg -> {
        if (arg.type == null) {
            return macro null;
        }
        return switch arg.type.toString() {
            case 'Int', 'Float': macro 0;
            case 'Bool': macro false;
            case _: macro null;
        }
    });

    trace(owningClass);

    args.push(macro this);

    return macro class $className implements coro.IContinuation<Any> {
        public final _hx_completion:coro.IContinuation<Any>;
        public final _hx_context:coro.CoroutineContext;

        public var _hx_state:Int;
        public var _hx_result:Any;
        public var _hx_error:haxe.Exception;

        public function new(completion) {
            _hx_completion = completion;
            _hx_context    = completion._hx_context;
            _hx_state      = 0;
            _hx_result     = null;
            _hx_error      = null;
        }

        public function resume(result:Any, error:haxe.Exception) {
            _hx_result = result;
            _hx_error  = error;

            _hx_context.scheduler.schedule(() -> {
                try {
                    final result = @:privateAccess $i{ owningClass }.$funcName($a{ args });

                    if (result == coro.Primitive.suspended) {
                        return;
                    }

                    _hx_completion.resume(result, null);
                } catch (exn:haxe.Exception) {
                    _hx_completion.resume(null, exn);
                }
            });
        }
    };
}

function buildStateMachine(bbRoot:BasicBlock, pos:Position, funcName:String, fun:Function) {
    final cases    = new Array<Case>();
    final varDecls = [];

    function loop(bb:BasicBlock) {
        final exprs = [];
        for (v in bb.vars) {
            varDecls.push(v);
        }

        switch bb.edge {
            case Return:
                var last = bb.elements[bb.elements.length - 1];
                for (i in 0...bb.elements.length - 1)
                    exprs.push(bb.elements[i]);

                exprs.push(macro {
                    _hx_continuation._hx_state = -1;
                    return $last;
                });

            case Throw:
                var last = bb.elements[bb.elements.length - 1];
                for (i in 0...bb.elements.length - 1)
                    exprs.push(bb.elements[i]);

                exprs.push(macro {
                    _hx_continuation._hx_state = -1;
                    throw $last;
                });

            case Final:
                for (e in bb.elements) exprs.push(e);
                exprs.push(macro {
                    _hx_continuation._hx_state = -1;
                    return _hx_continuation._hx_result;
                });

            case Suspend(ef, args, bbNext):
                for (e in bb.elements) exprs.push(e);

                args.push(macro _hx_continuation);

                exprs.push(macro {
                    _hx_continuation._hx_state = $v{bbNext.id};

                    var _hx_tmp = $ef($a{args});
                    if (_hx_tmp == coro.Primitive.suspended) {
                        return coro.Primitive.suspended;
                    }
                    
                    _hx_continuation._hx_result = _hx_tmp;
                });
                loop(bbNext);

            case Next(bbNext) | Loop(bbNext, _, _):
                for (e in bb.elements) exprs.push(e);
                loop(bbNext);
                exprs.push(macro _hx_continuation._hx_state = $v{bbNext.id});

            case IfThen(bbThen, bbNext):
                var econd = bb.elements[bb.elements.length - 1];
                for (i in 0...bb.elements.length - 1)
                    exprs.push(bb.elements[i]);

                loop(bbThen);
                loop(bbNext);

                exprs.push(macro {
                    if ($econd) {
                        _hx_continuation._hx_state = $v{bbThen.id};
                    } else {
                        _hx_continuation._hx_state = $v{bbNext.id};
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
                        _hx_continuation._hx_state = $v{bbThen.id};
                    } else {
                        _hx_continuation._hx_state = $v{bbElse.id};
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
                        _hx_continuation._hx_state = $v{bbBody.id};
                    } else {
                        _hx_continuation._hx_state = $v{bbNext.id};
                    }
                });

            case LoopBack(bbGoto) | LoopContinue(bbGoto) | LoopBreak(bbGoto):
                for (e in bb.elements) exprs.push(e);
                exprs.push(macro {
                    _hx_continuation._hx_state = $v{bbGoto.id};
                });
        }

        cases.unshift({
            values: [macro $v{bb.id}],
            expr: macro $b{exprs}
        });
    }

    return switch bbRoot.edge {
        case Return:
            final last  = bbRoot.elements[bbRoot.elements.length - 1];
            final exprs = [];
            for (i in 0...bbRoot.elements.length - 1) {
                exprs.push(bbRoot.elements[i]);
            }

            exprs.push(macro return $last);

            macro {
                final _hx_continuation = _hx_completion;

                ${ { expr: EVars(bbRoot.vars), pos: pos} };

                $b{ exprs }
            }
        case Throw:
            final last  = bbRoot.elements[bbRoot.elements.length - 1];
            final exprs = [];
            for (i in 0...bbRoot.elements.length - 1) {
                exprs.push(bbRoot.elements[i]);
            }

            exprs.push(macro throw $last);

            macro {
                final _hx_continuation = _hx_completion;

                ${ { expr: EVars(bbRoot.vars), pos: pos} };

                $b{ exprs }
            }
        case _:
            loop(bbRoot);

            final className   = 'HxCoro_${ funcName }';
            final clazz       = buildClass(className, funcName, fun);
            final typePath    = { pack: [], name: className };
            final complexType = TPath(typePath);
            final eswitch     = {
                pos: pos,
                expr: ESwitch(macro _hx_continuation._hx_state, cases, macro throw new haxe.Exception("Invalid state"))
            };

            Context.defineType(clazz);

            return macro {
                final _hx_continuation = if (_hx_completion is $complexType) (cast _hx_completion : $complexType) else new $typePath(_hx_completion);

                ${ { expr: EVars(varDecls), pos: pos} };

                if (_hx_continuation._hx_error != null) {
                    throw _hx_continuation._hx_error;
                }

                while (true) {
                    $e{ eswitch };
                }
            }
    }
}