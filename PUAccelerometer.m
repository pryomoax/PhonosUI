//
//  PUAccelerometer.m
//  PhonosUI
//
//  Created by Paul Bates on 02/18/10.
//  Copyright 2010 The Evil Radish Corporation. All rights reserved.
//

#import "PUAccelerometer.h"
#import "PUAccelerationFilter.h"


// Singleton global for PUAccelerometer.
static PUAccelerometer *__PUAccelerometer = nil;
static PUAccelerationFilter *defaultAccelerationFilter = nil;


/*******************************************************************************
 PUAccelerometer private interface
 ******************************************************************************/
@interface PUAccelerometer()

// Factory method for creating the default acceleration filter, for filterless
// calls when starting an update. See startUpdating:atInterval.
- (PUAccelerationFilter *)createDefaultAccelerationFilter;

@end


/*******************************************************************************
 PUAccelerometer implementation
 ******************************************************************************/
@implementation PUAccelerometer

@synthesize delegate = _delegate;
@synthesize filter = _filter;
@synthesize updateInterval = _updateInterval;
@synthesize updating = _updating;


#pragma mark -
#pragma mark Singleton

+ (PUAccelerometer *)sharedAccelerometer
{
	@synchronized(self) {
		if (__PUAccelerometer == nil) {
			// No assignment necessary here, see allocWithZone, but allow
			// the LLVM analyzer to report all is well.
			__PUAccelerometer = [[self alloc] init];
		}
	}
	
	//PFAssertNotNil(g___PUAccelerometer);
	return __PUAccelerometer;
}


#pragma mark -
#pragma mark Public instance methods

- (BOOL)startUpdating:(NSObject<PUAccelerometerFilterDelegate> *)delegate atInterval:(NSTimeInterval)interval {
	if (self.isUpdating) {
		// Can't have two calls to update!!
		return NO;	
	}
	
	if (!self.isUpdating) {
		@synchronized(self) {			
			PUAccelerationFilter *defaultFilter = defaultAccelerationFilter;
			if (defaultFilter == nil) {
				defaultFilter = [self createDefaultAccelerationFilter];
				if (defaultFilter == nil) {
					// TODO: Raise exception					
				}
				defaultAccelerationFilter = defaultFilter;
			}
			//PFAssertTagNotNil(defaultAccelerationFilter);
			//PFAssertTagNotNil(defaultFilter);
			//PFAssertTagRefEq(defaultAccelerationFilter, defaultFilter);
			return [self startUpdating:delegate atInterval:interval usingFilter:defaultFilter];
		}
	}
	
	return YES;
}


- (BOOL)startUpdating:(NSObject<PUAccelerometerFilterDelegate> *)aDelegate atInterval:(NSTimeInterval)aInterval usingFilter:(PUAccelerationFilter *)aFilter {
	if (self.isUpdating) {
		// Can't have two calls to update!!
		return NO;	
	}
	
	@synchronized(self) {
		// Release any previous filter. This is not required but do it just for future proofing
		//PFAssertTagIsNil(filter_)
		if (_filter != nil) {
			[_filter release];
			_filter = nil;
		}

		// Set class attributes...
		_filter = [aFilter retain];
		_updateInterval = aInterval;

		// Yes we are updating (set before delegate assignment in case there is
		// an update call before
		_updating = YES;		
	}
	
	
	if (aDelegate != nil && [aDelegate respondsToSelector:@selector(accelerometerWillBeginUpdating:)]) {
		// Send message to delegate to notify it updates will begin shortly.
		[aDelegate accelerometerWillBeginUpdating:self];
	}
	_delegate = [aDelegate retain];
	
	// Now actually get the accelerometer to notify us.
	UIAccelerometer *accelerometer = [UIAccelerometer sharedAccelerometer];
	@synchronized(accelerometer){
		/*
		PFAssert1([[UIAccelerometer sharedAccelerometer] delegate] == nil,
				  @"UIAccelerometer already has a delegate, of the class type %@"
				  ", assigned to it. This is about to be changed and could cause issues.",
				  NSStringFromClass([accelerometer.delegate class])); 
		*/
		accelerometer.delegate = self;
		accelerometer.updateInterval = self.updateInterval;		  
	}
	
	return YES;
}


- (void)stopUpdating {
	if (!self.isUpdating)
		return; // Nothing to stop.

	// First stop the accelerometer from reporting...
	UIAccelerometer *accelerometer = [UIAccelerometer sharedAccelerometer];			
	if (accelerometer.delegate == self) {
		// The delegate is still the same, unset it.
		accelerometer.updateInterval = 0;
		accelerometer.delegate = nil;
	} else {
		NSLog(@"UIAccelerometer's delegate has changed. It is now an instance "
			  "of %@. As a result the accelerometer is still firing updates.", 
			  NSStringFromClass([accelerometer.delegate class]));
	}	
	
	// Now update the state to reflect no more updates will occur.
	NSObject<PUAccelerometerFilterDelegate> *currentDelegate = nil;
	@synchronized(self) {
		// No longer going to be updating.
		_updating = NO;
		
		currentDelegate = [_delegate retain]; // retain for MT preservation
		
		// Remove active filter...
		//PFAssertTNotNil(filter_);
		[_filter release];
		_filter = nil;
	}
	
	// Attempt to send delegate a accelerometerDidStopUpdating message.
	if (currentDelegate != nil) {
		@try {
			if ([currentDelegate respondsToSelector:@selector(accelerometerDidStopUpdating:)]) {
				[currentDelegate accelerometerDidStopUpdating:self];
			}
		}
		@finally {
			[currentDelegate release];
		}
	} 
}


#pragma mark -
#pragma mark UIAccelerometerDelegate methods

- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration {
	//PFAssert1(self.isUpdating, @"UIAccelerometer updated but %@ is not currently updating.", NSStringFromClass([self class]));
	
	PUAccelerationFilter *activeFilter = nil;
	NSObject<PUAccelerometerFilterDelegate> *currentDelegate = nil;
	@synchronized(self) {
		activeFilter = [self.filter retain]; // retain for MT preservation.
		currentDelegate = [self.delegate retain]; // retain for MT preservation.
	}

	//PFAssertTNotNil(activeFilter);
	//PFAssertTNotNil(currentDelegate);
	if (activeFilter != nil) {
		@try {
			[activeFilter addAcceleration:acceleration];
			if (currentDelegate != nil) {
				// Notify update.
				[currentDelegate accelerometer:self didFilterAcceleration:activeFilter];
			}
		}
		@finally {
			[activeFilter release];
			[currentDelegate release];
		}
	}
}


#pragma mark -
#pragma mark Private implementation methods

- (PUAccelerationFilter *)createDefaultAccelerationFilter {
	return [[[PUAccelerationFilter alloc] init] autorelease];
}


#pragma mark -
#pragma mark Memory management

+ (id)allocWithZone:(NSZone *)zone {
	@synchronized(self) {
		if (__PUAccelerometer == nil) {
			// Assignment and return on first allocation.
			__PUAccelerometer = [super allocWithZone:zone];
			return __PUAccelerometer; 
		}
	}
	
	// On subsequent allocation attempts return nil!
	return nil; 
} 


- (id)copyWithZone:(NSZone *)zone {
	return self;
}


- (id)retain {
	return self;
}


- (unsigned)retainCount {
	return UINT_MAX; //denotes an object that cannot be released
}


- (void)release {
	//do nothing
}


- (id)autorelease {
	return self;
}

@end
