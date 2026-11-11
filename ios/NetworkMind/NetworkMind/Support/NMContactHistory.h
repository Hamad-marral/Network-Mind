//  NMContactHistory.h
//  Thin Objective-C bridge over -[CNContactStore enumeratorForChangeHistoryFetchRequest:error:],
//  which is not callable from Swift. Converts CNChangeHistoryEvent subclasses into plain
//  value objects that Swift can consume.

#import <Foundation/Foundation.h>
#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NMContactChangeKind) {
    NMContactChangeKindDropEverything = 0,
    NMContactChangeKindAdded = 1,
    NMContactChangeKindUpdated = 2,
    NMContactChangeKindDeleted = 3,
};

@interface NMContactChange : NSObject
@property (nonatomic, readonly) NMContactChangeKind kind;
@property (nonatomic, readonly, copy, nullable) NSString *contactIdentifier;
- (instancetype)initWithKind:(NMContactChangeKind)kind contactIdentifier:(nullable NSString *)contactIdentifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface NMContactHistoryResult : NSObject
@property (nonatomic, readonly, copy) NSArray<NMContactChange *> *changes;
@property (nonatomic, readonly, copy, nullable) NSData *currentHistoryToken;
- (instancetype)initWithChanges:(NSArray<NMContactChange *> *)changes currentHistoryToken:(nullable NSData *)token NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface NMContactHistoryReader : NSObject
/// Fetches contact changes recorded after `token` (unified contacts, no group changes).
/// Fails with a Contacts error if the token is invalid or the history has expired.
+ (nullable NMContactHistoryResult *)fetchChangesInStore:(CNContactStore *)store
                                              sinceToken:(NSData *)token
                                                   error:(NSError **)error
    NS_SWIFT_NAME(fetchChanges(store:since:));
@end

NS_ASSUME_NONNULL_END
