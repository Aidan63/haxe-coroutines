package coro.macro;

import coro.macro.Transform;
import haxe.macro.Printer;
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.ExprTools;
using haxe.macro.ComplexTypeTools;
using Lambda;

function doTransform(funcName:String, fun:Function, pos:Position, found:Array<String>):Function {
    if (fun.ret == null) {
        throw new Error("Return type hint expected", pos);
    }

    final coroArgs = fun.args.map(arg -> {
        return switch arg.type {
            case TPath({ name: 'Coroutine', pack: [ 'coro' ], params: [ TPType(TFunction(fArgs, fRet)) ] }):

                final copy = fArgs.copy();
                copy.push(fRet);

                arg.type = TPath({ name: 'Coroutine', sub: 'Coroutine${ fArgs.length }', pack: [ 'coro' ], params: copy.map(t -> TPType(t)) });
                arg;
            case _:
                arg;
        }
    });
    final cfg      = FlowGraph.build(fun, found);

    coroArgs.push({ name: "_hx_completion", type: macro : coro.IContinuation<Any> });

    return {
        args: coroArgs,
        ret : macro : Any,
        expr: buildStateMachine(cfg.root, fun.expr.pos, funcName, fun)
    };
}

function buildClasses(className:String, funcName:String, fun:Function):Array<TypeDefinition> {
    final owningClass = Context.getLocalClass().get().module;
    final coroArgs    = fun.args.mapi((idx, arg) -> ({
        name : 'arg$idx',
        type : arg.type
    } : FunctionArg));

    coroArgs.push({
        name : 'completion',
        type : macro : coro.IContinuation<Any>
    });

    final continuation = {
        final args = {
            var idx = 0;
    
            fun.args.map(arg -> macro $i{ '_hx_arg${ idx++ }' });
        }
    
        args.push(macro this);

        final definition = macro class $className implements coro.IContinuation<Any> {
            public final _hx_completion:coro.IContinuation<Any>;
            public final _hx_context:coro.CoroutineContext;
    
            public var _hx_state:Int;
            public var _hx_result:Any;
            public var _hx_error:haxe.Exception;
    
            public function resume(result:Any, error:haxe.Exception) {
                _hx_result = result;
                _hx_error  = error;
    
                _hx_context.scheduler.schedule(() -> {
                    try {
                        final result = @:privateAccess $i{ owningClass }.$funcName($a{ args });
    
                        if (result is coro.Primitive) {
                            return;
                        }
    
                        _hx_completion.resume(result, null);
                    } catch (exn:haxe.Exception) {
                        _hx_completion.resume(null, exn);
                    }
                });
            }
        };

        var idx = 0;
        for (arg in fun.args) {
            definition.fields.push({
                name   : '_hx_arg${ idx++ }',
                pos    : Context.currentPos(),
                access : [ APublic ],
                kind   : FVar(arg.type, arg.value)
            });
        }

        definition.fields.push({
            name   : 'new',
            pos    : Context.currentPos(),
            access : [ APublic ],
            kind   : FFun({
                args: {
                    final args = new Array<FunctionArg>();

                    var idx = 0;
                    for (arg in fun.args) {
                        args.push({
                            name: 'arg${ idx++ }',
                            type: arg.type,
                        });
                    }

                    args.push({ name: 'completion' });

                    args;
                },
                expr: {
                    final args = new Array<Expr>();

                    var idx = 0;
                    for (arg in fun.args) {
                        args.push(macro $i{ '_hx_arg$idx' } = $i{ 'arg$idx' });

                        idx++;
                    }

                    macro {
                        _hx_completion = completion;
                        _hx_context    = if (completion == null) null else completion._hx_context;
                        _hx_state      = 0;
                        _hx_result     = null;
                        _hx_error      = null;

                        @:mergeBlock $b{ args }
                    }
                }
            })
        });

        definition;
    }

    final factory = {
        final factoryName = className+'Factory';
        final factoryTp   = {
            pack: [],
            name: factoryName
        }
        final extended    = {
            pack   : [ 'coro' ],
            name   : 'Coroutine',
            sub    : 'Coroutine${ fun.args.length }',
            params : fun.args.map(arg -> TPType(arg.type))
        };
    
        extended.params.push(TPType(fun.ret));

        final extendexCt = TPath(extended);
        final definition = macro class $factoryName extends $extended {
            public static final instance : $extendexCt = new $factoryTp();

            private function new() {}
        };

        final classTp = {
            pack: [],
            name: className
        };
        
        definition.fields.push({
            name   : 'create',
            pos    : definition.pos,
            access : [ APublic ],
            kind   : FFun({
                args : coroArgs,
                ret  : macro: coro.IContinuation<Any>,
                expr : macro {
                    return new $classTp($a{ coroArgs.map(a -> macro $i{ a.name }) });
                }
            }),
        });
    
        definition.fields.push({
            name   : 'start',
            pos    : definition.pos,
            access : [ APublic ],
            kind   : FFun({
                args : coroArgs,
                ret  : macro: Any,
                expr : macro {
                    return @:privateAccess $i{ owningClass }.$funcName($a{ coroArgs.map(a -> macro $i{ a.name }) });
                }
            }),
        });

        definition;
    }

    trace(new Printer().printTypeDefinition(continuation));
    trace(new Printer().printTypeDefinition(factory));

    return [ continuation, factory ];
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
                    if (_hx_tmp is coro.Primitive) {
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
            final typePath    = { pack: [], name: className };
            final complexType = TPath(typePath);
            final eswitch     = {
                pos: pos,
                expr: ESwitch(macro _hx_continuation._hx_state, cases, macro throw new haxe.Exception("Invalid state"))
            };

            for (clazz in buildClasses(className, funcName, fun)) {
                Context.defineType(clazz);
            }

            final args = fun.args.map(a -> macro $i{ a.name });
            args.push(macro $i{ '_hx_completion' });

            return macro {
                final _hx_continuation = if (_hx_completion is $complexType) (cast _hx_completion : $complexType) else new $typePath($a{ args });

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