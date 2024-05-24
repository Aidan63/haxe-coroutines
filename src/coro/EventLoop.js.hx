package coro;

import haxe.Timer;

/**
	When an event loop has an available event to execute.
**/
enum NextEventTime {
	/** There's already an event waiting to be executed */
	Now;
	/** No new events are expected. */
	Never;
	/**
		An event is expected to arrive at any time.
		If `time` is specified, then the event will be ready at that time for sure.
	*/
	AnyTime(time:Null<Float>);
	/** An event is expected to be ready for execution at `time`. */
	At(time:Float);
}

/**
	An event loop implementation used for `sys.thread.Thread`
**/
class EventLoop {
	final oneTimeEvents = new Array<Null<()->Void>>();
	var oneTimeEventsIdx = 0;
	var promisedEventsCount = 0;
	var regularEvents:Null<RegularEvent>;
	var isMainThread:Bool;
	static var CREATED : Bool;

	public function new():Void {
		isMainThread = !CREATED;
		CREATED = true;
	}

	/**
		Schedule event for execution every `intervalMs` milliseconds in current loop.
	**/
	public function repeat(event:()->Void, intervalMs:Int):EventHandler {
		var interval = 0.001 * intervalMs;
		var event = new RegularEvent(event, Timer.stamp() + interval, interval);
		inline insertEventByTime(event);
		return event;
	}

	function insertEventByTime(event:RegularEvent):Void {
		switch regularEvents {
			case null:
				regularEvents = event;
			case current:
				var previous = null;
				while(true) {
					if(current == null) {
						previous.next = event;
						event.previous = previous;
						break;
					} else if(event.nextRunTime < current.nextRunTime) {
						event.next = current;
						current.previous = event;
						switch previous {
							case null:
								regularEvents = event;
								case _:
								event.previous = previous;
								previous.next = event;
								current.previous = event;
						}
						break;
					} else {
						previous = current;
						current = current.next;
					}
				}
		}
	}

	/**
		Prevent execution of a previously scheduled event in current loop.
	**/
	public function cancel(eventHandler:EventHandler):Void {
		var event:RegularEvent = eventHandler;
		event.cancelled = true;
		if(regularEvents == event) {
			regularEvents = event.next;
		}
		switch event.next {
			case null:
			case e: e.previous = event.previous;
		}
		switch event.previous {
			case null:
			case e: e.next = event.next;
		}
		event.next = event.previous = null;
	}

	/**
		Notify this loop about an upcoming event.
		This makes the thread stay alive and wait for as many events as the number of
		times `.promise()` was called. These events should be added via `.runPromised()`.
	**/
	public function promise():Void {
		++promisedEventsCount;
	}

	/**
		Execute `event` as soon as possible.
	**/
	public function run(event:()->Void):Void {
		oneTimeEvents[oneTimeEventsIdx++] = event;
	}

	/**
		Add previously promised `event` for execution.
	**/
	public function runPromised(event:()->Void):Void {
		oneTimeEvents[oneTimeEventsIdx++] = event;
		--promisedEventsCount;
	}

	/**
		Executes all pending events.

		The returned time stamps can be used with `Sys.time()` for calculations.

		Depending on a target platform this method may be non-reentrant. It must
		not be called from event callbacks.
	**/
	public function progress():NextEventTime {
		return switch __progress(Timer.stamp(), [], []) {
			case {nextEventAt:-2}: Now;
			case {nextEventAt:-1, anyTime:false}: Never;
			case {nextEventAt:-1, anyTime:true}: AnyTime(null);
			case {nextEventAt:time, anyTime:true}: AnyTime(time);
			case {nextEventAt:time, anyTime:false}: At(time);
		}
	}

	/**
		Blocks until a new event is added or `timeout` (in seconds) to expires.

		Depending on a target platform this method may also automatically execute arriving
		events while waiting. However if any event is executed it will stop waiting.

		Returns `true` if more events are expected.
		Returns `false` if no more events expected.

		Depending on a target platform this method may be non-reentrant. It must
		not be called from event callbacks.
	**/
	public function wait(?timeout:Float):Bool {
		return true;
	}

	/**
		Execute all pending events.
		Wait and execute as many events as the number of times `promise()` was called.
		Runs until all repeating events are cancelled and no more events are expected.

		Depending on a target platform this method may be non-reentrant. It must
		not be called from event callbacks.
	**/
	public function loop():Void {
		var recycleRegular = [];
		var recycleOneTimers = [];
		while(true) {
			var r = __progress(Timer.stamp(), recycleRegular, recycleOneTimers);
			switch r {
				case {nextEventAt:-2}:
				case {nextEventAt:-1, anyTime:false}:
					break;
				case {nextEventAt:-1, anyTime:true}:
					//
				case {nextEventAt:time}:
					var timeout = time - Timer.stamp();
			}
		}
	}

	/**
		`.progress` implementation with a reusable array for internal usage.
		The `nextEventAt` field of the return value denotes when the next event
		is expected to run:
		* -1 - never
		* -2 - now
		* other values - at specified time
	**/
	inline function __progress(now:Float, recycleRegular:Array<RegularEvent>, recycleOneTimers:Array<()->Void>):{nextEventAt:Float, anyTime:Bool} {
		var regularsToRun = recycleRegular;
		var eventsToRunIdx = 0;
		// When the next event is expected to run
		var nextEventAt:Float = -1;

		// Collect regular events to run
		var current = regularEvents;
		while(current != null) {
			if(current.nextRunTime <= now) {
				regularsToRun[eventsToRunIdx++] = current;
				current.nextRunTime += current.interval;
				nextEventAt = -2;
			} else if(nextEventAt == -1 || current.nextRunTime < nextEventAt) {
				nextEventAt = current.nextRunTime;
			}
			current = current.next;
		}

		// Run regular events
		for(i in 0...eventsToRunIdx) {
			if(!regularsToRun[i].cancelled)
				regularsToRun[i].run();
			regularsToRun[i] = null;
		}
		eventsToRunIdx = 0;

		var oneTimersToRun = recycleOneTimers;
		// Collect pending one-time events
		for(i => event in oneTimeEvents) {
			switch event {
				case null:
					break;
				case _:
					oneTimersToRun[eventsToRunIdx++] = event;
					oneTimeEvents[i] = null;
			}
		}
		oneTimeEventsIdx = 0;
		var hasPromisedEvents = promisedEventsCount > 0;

		//run events
		for(i in 0...eventsToRunIdx) {
			oneTimersToRun[i]();
			oneTimersToRun[i] = null;
		}

		// run main events
		if( isMainThread ) {
			var next = @:privateAccess haxe.MainLoop.tick();
			if( haxe.MainLoop.hasEvents() ) {
				eventsToRunIdx++;
				if( nextEventAt > next )
					nextEventAt = next;
			}
		}

		// Some events were executed. They could add new events to run.
		if(eventsToRunIdx > 0) {
			nextEventAt = -2;
		}
		return {nextEventAt:nextEventAt, anyTime:hasPromisedEvents}
	}
}

abstract EventHandler(RegularEvent) from RegularEvent to RegularEvent {}

private class RegularEvent {
	public var nextRunTime:Float;
	public final interval:Float;
	public final run:()->Void;
	public var next:Null<RegularEvent>;
	public var previous:Null<RegularEvent>;
	public var cancelled:Bool = false;

	public function new(run:()->Void, nextRunTime:Float, interval:Float) {
		this.run = run;
		this.nextRunTime = nextRunTime;
		this.interval = interval;
	}
}