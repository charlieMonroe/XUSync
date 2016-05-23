//
//  XUDeletionSyncChange.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUSyncChange.h"

/** This sync change represents a deletion change. We don't need any further
 * information, since we have the syncID.
 */
DEPRECATED_MSG_ATTRIBUTE("Use XUCore.")
@interface XUDeletionSyncChange : XUSyncChange

@end
