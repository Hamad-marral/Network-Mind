//  NMContactHistory.m

#import "NMContactHistory.h"

@implementation NMContactChange

- (instancetype)initWithKind:(NMContactChangeKind)kind contactIdentifier:(NSString *)contactIdentifier {
    if ((self = [super init])) {
        _kind = kind;
        _contactIdentifier = [contactIdentifier copy];
    }
    return self;
}

@end

@implementation NMContactHistoryResult

- (instancetype)initWithChanges:(NSArray<NMContactChange *> *)changes currentHistoryToken:(NSData *)token {
    if ((self = [super init])) {
        _changes = [changes copy];
        _currentHistoryToken = [token copy];
    }
    return self;
}

@end

@implementation NMContactHistoryReader

+ (NMContactHistoryResult *)fetchChangesInStore:(CNContactStore *)store
                                     sinceToken:(NSData *)token
                                          error:(NSError **)error {
    CNChangeHistoryFetchRequest *request = [[CNChangeHistoryFetchRequest alloc] init];
    request.startingToken = token;
    request.shouldUnifyResults = YES;
    request.includeGroupChanges = NO;
    request.mutableObjects = NO;
    request.additionalContactKeyDescriptors = @[];

    NSError *fetchError = nil;
    CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *result =
        [store enumeratorForChangeHistoryFetchRequest:request error:&fetchError];
    if (result == nil) {
        if (error != NULL) {
            *error = fetchError ?: [NSError errorWithDomain:CNErrorDomain code:CNErrorCodeChangeHistoryInvalidAnchor userInfo:nil];
        }
        return nil;
    }

    NSMutableArray<NMContactChange *> *changes = [NSMutableArray array];
    for (CNChangeHistoryEvent *event in result.value) {
        if ([event isKindOfClass:[CNChangeHistoryDropEverythingEvent class]]) {
            [changes addObject:[[NMContactChange alloc] initWithKind:NMContactChangeKindDropEverything contactIdentifier:nil]];
        } else if ([event isKindOfClass:[CNChangeHistoryAddContactEvent class]]) {
            NSString *identifier = ((CNChangeHistoryAddContactEvent *)event).contact.identifier;
            [changes addObject:[[NMContactChange alloc] initWithKind:NMContactChangeKindAdded contactIdentifier:identifier]];
        } else if ([event isKindOfClass:[CNChangeHistoryUpdateContactEvent class]]) {
            NSString *identifier = ((CNChangeHistoryUpdateContactEvent *)event).contact.identifier;
            [changes addObject:[[NMContactChange alloc] initWithKind:NMContactChangeKindUpdated contactIdentifier:identifier]];
        } else if ([event isKindOfClass:[CNChangeHistoryDeleteContactEvent class]]) {
            NSString *identifier = ((CNChangeHistoryDeleteContactEvent *)event).contactIdentifier;
            [changes addObject:[[NMContactChange alloc] initWithKind:NMContactChangeKindDeleted contactIdentifier:identifier]];
        }
        // Group and membership events are ignored (includeGroupChanges = NO).
    }
    return [[NMContactHistoryResult alloc] initWithChanges:changes currentHistoryToken:result.currentHistoryToken];
}

@end
